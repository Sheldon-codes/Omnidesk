#!/usr/bin/env bash
# Produces TLS-enabled Baresip static libraries for the Android JNI bridge.
# The generated files are build artifacts and must not be committed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
NDK_ROOT="${ANDROID_NDK_ROOT:-$SDK_ROOT/ndk/28.2.13676358}"
API=24
OUT="$ROOT/android/app/src/main/jniLibs"
INCLUDE_OUT="$ROOT/android/app/src/main/cpp/generated/include"
BUILD_ROOT="${TMPDIR:-/tmp}/omnidesk-baresip-android"

BARESIP_SHA="42286be6b221398c0523165352a37a5b26ed0af0"
LIBRE_SHA="16bb5c7662029def4b62b4ba686fd5d0c029086c"
OPENSSL_SHA="fa1e5dfb142bb1c26c3c38a10aafa7a095df52e5"

test -d "$NDK_ROOT" || {
  echo "Android NDK not found at $NDK_ROOT. Set ANDROID_NDK_ROOT." >&2
  exit 1
}
# OpenSSL 3.x detects modern NDKs by finding clang/llvm-ar on PATH. New NDKs
# intentionally do not ship the legacy *-gcc executables.
LLVM_PREBUILT="$(find "$NDK_ROOT/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d -print -quit)"
test -d "$LLVM_PREBUILT/bin" || {
  echo "NDK LLVM toolchain not found under $NDK_ROOT." >&2
  exit 1
}
export PATH="$LLVM_PREBUILT/bin:$PATH"
for dependency in baresip re openssl; do
  test -f "$ROOT/third_party/$dependency/.git" || {
    echo "Missing third_party/$dependency submodule." >&2
    exit 1
  }
done
test "$(git -C "$ROOT/third_party/baresip" rev-parse HEAD)" = "$BARESIP_SHA"
test "$(git -C "$ROOT/third_party/re" rev-parse HEAD)" = "$LIBRE_SHA"
test "$(git -C "$ROOT/third_party/openssl" rev-parse HEAD)" = "$OPENSSL_SHA"

rm -rf "$BUILD_ROOT" "$OUT" "$INCLUDE_OUT"
mkdir -p "$BUILD_ROOT" "$OUT" "$INCLUDE_OUT"

cleanup_source() {
  git -C "$ROOT/third_party/openssl" restore --source=HEAD --staged --worktree . >/dev/null 2>&1 || true
  git -C "$ROOT/third_party/openssl" clean -fd >/dev/null 2>&1 || true
}
trap cleanup_source EXIT

build_abi() {
  local abi="$1"
  local openssl_target="$2"
  local slice="$BUILD_ROOT/$abi"
  local prefix="$slice/prefix"

  pushd "$ROOT/third_party/openssl" >/dev/null
  make distclean >/dev/null 2>&1 || true
  ANDROID_NDK_ROOT="$NDK_ROOT" ./Configure "$openssl_target" \
    no-shared no-tests --prefix="$prefix/openssl" >/dev/null
  make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)" build_libs >/dev/null
  make install_dev >/dev/null
  popd >/dev/null

  # Libre 3.24 unconditionally adds its native test target.  That target is
  # not needed in an Android production build and causes CMake's OpenSSL
  # variables to be evaluated a second time through the test package. Build a
  # temporary source copy with only that test subdirectory disabled; the
  # checked-in submodule remains untouched and reproducible.
  local re_source="$slice/re-source"
  cp -R "$ROOT/third_party/re/." "$re_source"
  sed -i.bak 's/^add_subdirectory(test EXCLUDE_FROM_ALL)$/# Android production build: tests disabled/' \
    "$re_source/CMakeLists.txt"
  rm -f "$re_source/CMakeLists.txt.bak"

  local openssl_include="$prefix/openssl/include"
  local openssl_ssl="$prefix/openssl/lib/libssl.a"
  local openssl_crypto="$prefix/openssl/lib/libcrypto.a"
  test -f "$openssl_ssl" && test -f "$openssl_crypto" && test -f "$openssl_include/openssl/ssl.h" || {
    echo "OpenSSL install is incomplete for $abi (expected static libraries and headers under $prefix/openssl)." >&2
    exit 1
  }

  cmake -S "$re_source" -B "$slice/re" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DCMAKE_SYSTEM_NAME=Android -DCMAKE_ANDROID_NDK="$NDK_ROOT" \
    -DANDROID_ABI="$abi" -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix/re" \
    -DOPENSSL_ROOT_DIR="$prefix/openssl" \
    -DOPENSSL_INCLUDE_DIR="$openssl_include" \
    -DOPENSSL_SSL_LIBRARY="$openssl_ssl" \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl_crypto" -DUSE_OPENSSL=ON \
    -DLIBRE_BUILD_SHARED=OFF -DLIBRE_BUILD_STATIC=ON >/dev/null
  cmake --build "$slice/re" --parallel >/dev/null
  cmake --install "$slice/re" >/dev/null

  # Baresip's own CMake build supports a framework-only mode.  Unlike the
  # old line-based source rewrite this is resilient to indentation/upstream
  # formatting changes, and prevents both the executable and self-test
  # targets from being configured.  NDK 28 exposes sys/user.h, whose `struct
  # user` conflicts with Baresip's test-only SIP fixture; the production
  # static library itself is unaffected.
  cmake -S "$ROOT/third_party/baresip" -B "$slice/baresip" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DCMAKE_SYSTEM_NAME=Android -DCMAKE_ANDROID_NDK="$NDK_ROOT" \
    -DANDROID_ABI="$abi" -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$prefix/re" \
    -DRE_INCLUDE_DIR="$ROOT/third_party/re/include" \
    -DRE_LIBRARY="$prefix/re/lib/libre.a" \
    -Dre_DIR="$prefix/re/lib/cmake/re" \
    -DOPENSSL_ROOT_DIR="$prefix/openssl" \
    -DOPENSSL_INCLUDE_DIR="$openssl_include" \
    -DOPENSSL_SSL_LIBRARY="$openssl_ssl" \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl_crypto" -DSTATIC=ON \
    -DOMNIDESK_FRAMEWORK_ONLY=ON \
    -DMODULES="opensles;g711;srtp" >/dev/null
  cmake --build "$slice/baresip" --parallel >/dev/null

  mkdir -p "$OUT/$abi"
  cp "$slice/baresip/libbaresip.a" "$OUT/$abi/"
  cp "$prefix/re/lib/libre.a" "$OUT/$abi/"
  cp "$prefix/openssl/lib/libssl.a" "$OUT/$abi/"
  cp "$prefix/openssl/lib/libcrypto.a" "$OUT/$abi/"
}

build_abi arm64-v8a android-arm64
build_abi x86_64 android-x86_64
cp "$ROOT/third_party/baresip/include/baresip.h" "$INCLUDE_OUT/"
cp -R "$ROOT/third_party/re/include/." "$INCLUDE_OUT/"

echo "Built Baresip Android libraries in $OUT"
