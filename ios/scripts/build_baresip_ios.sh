#!/usr/bin/env bash
# Builds the pinned native SIP/RTP dependencies for Runner. Run this on macOS
# with Xcode installed; it intentionally writes all intermediate output outside
# the repository and commits only the final reproducible XCFramework.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/ios/ThirdParty/Baresip.xcframework"
BUILD_ROOT="${TMPDIR:-/tmp}/omnidesk-baresip-ios"
MIN_IOS="15.0"

# Source revisions are gitlinks under third_party. Keep OpenSSL as a submodule
# too: TLS registration must never rely on an OpenSSL copied from the host.
BARESIP_SHA="42286be6b221398c0523165352a37a5b26ed0af0"
LIBRE_SHA="16bb5c7662029def4b62b4ba686fd5d0c029086c"
OPENSSL_SHA="fa1e5dfb142bb1c26c3c38a10aafa7a095df52e5"

for dependency in baresip re openssl; do
  test -f "$ROOT/third_party/$dependency/.git" || {
    echo "Missing third_party/$dependency submodule. Run git submodule update --init --recursive." >&2
    exit 1
  }
done

test "$(git -C "$ROOT/third_party/baresip" rev-parse HEAD)" = "$BARESIP_SHA"
test "$(git -C "$ROOT/third_party/re" rev-parse HEAD)" = "$LIBRE_SHA"
test "$(git -C "$ROOT/third_party/openssl" rev-parse HEAD)" = "$OPENSSL_SHA"

rm -rf "$BUILD_ROOT" "$OUT"
mkdir -p "$BUILD_ROOT"

build_slice() {
  local platform="$1"
  local arch="$2"
  local sdk="iphone${platform}"
  local slice="$BUILD_ROOT/$platform-$arch"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local prefix="$slice/prefix"

  mkdir -p "$slice"

  pushd "$ROOT/third_party/openssl" >/dev/null
  make distclean >/dev/null 2>&1 || true
  if [[ "$platform" == "simulator" ]]; then
    export CFLAGS="-arch $arch -isysroot $sdk_path -mios-simulator-version-min=$MIN_IOS"
  else
    export CFLAGS="-arch $arch -isysroot $sdk_path -mios-version-min=$MIN_IOS"
  fi
  export LDFLAGS="-arch $arch -isysroot $sdk_path"
  if [[ "$platform" == "os" ]]; then
    ./Configure ios64-xcrun no-shared no-tests --prefix="$prefix/openssl"
  else
    ./Configure iossimulator-xcrun no-shared no-tests --prefix="$prefix/openssl"
  fi
  make -j"$(sysctl -n hw.ncpu)" build_libs >/dev/null
  make install_dev >/dev/null
  popd >/dev/null

  cmake -S "$ROOT/third_party/re" -B "$slice/re" \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_OSX_SYSROOT="$sdk_path" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix/re" \
    -DOPENSSL_ROOT_DIR="$prefix/openssl" \
    -DUSE_OPENSSL=ON \
    -DLIBRE_BUILD_SHARED=OFF \
    -DLIBRE_BUILD_STATIC=ON
  cmake --build "$slice/re" --config Release --parallel
  cmake --install "$slice/re" --config Release

  cmake -S "$ROOT/third_party/baresip" -B "$slice/baresip" \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_OSX_SYSROOT="$sdk_path" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$prefix/re" \
    -DOPENSSL_ROOT_DIR="$prefix/openssl" \
    -DSTATIC=ON \
    -DOMNIDESK_FRAMEWORK_ONLY=ON \
    -DMODULES="audiounit;g711;srtp"
  cmake --build "$slice/baresip" --config Release --parallel

  mkdir -p "$slice/include"
  cp "$ROOT/third_party/baresip/include/baresip.h" "$slice/include/"
  cp -R "$ROOT/third_party/re/include/." "$slice/include/"
  # Apple's libtool preserves duplicate archive members (including the
  # duplicate basenames present inside libre.a), whereas extracting with
  # `ar -x` would overwrite those members and drop exported symbols.
  # System Apple frameworks remain linked by the Runner target.
  libtool -static -o "$slice/libomnidesk_baresip.a" \
    "$slice/baresip/libbaresip.a" \
    "$prefix/re/lib/libre.a" \
    "$prefix/openssl/lib/libssl.a" \
    "$prefix/openssl/lib/libcrypto.a"
}

build_slice os arm64
build_slice simulator arm64
build_slice simulator x86_64

# XCFramework accepts one simulator library for a platform.  Combine both
# simulator architectures into a universal archive so the same artifact works
# on Intel and Apple Silicon simulator hosts.
SIMULATOR_UNIVERSAL="$BUILD_ROOT/simulator-universal"
mkdir -p "$SIMULATOR_UNIVERSAL"
lipo -create \
  "$BUILD_ROOT/simulator-arm64/libomnidesk_baresip.a" \
  "$BUILD_ROOT/simulator-x86_64/libomnidesk_baresip.a" \
  -output "$SIMULATOR_UNIVERSAL/libomnidesk_baresip.a"
cp -R "$BUILD_ROOT/simulator-arm64/include" "$SIMULATOR_UNIVERSAL/"

xcodebuild -create-xcframework \
  -library "$BUILD_ROOT/os-arm64/libomnidesk_baresip.a" \
  -headers "$BUILD_ROOT/os-arm64/include" \
  -library "$SIMULATOR_UNIVERSAL/libomnidesk_baresip.a" \
  -headers "$SIMULATOR_UNIVERSAL/include" \
  -output "$OUT"

echo "Built $OUT"
