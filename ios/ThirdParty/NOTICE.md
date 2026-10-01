# Native SIP third-party notices (RETIRED)

Baresip is no longer wired into the Runner target. Media is Africa's
Talking WebRTC in a hidden WebView; iOS native owns PushKit + CallKit
only. This note and `ios/scripts/build_baresip_ios.sh` remain for history.

- Baresip `v3.24.0` — BSD-3-Clause
- Libre `v3.24.0` — BSD-3-Clause
- OpenSSL `3.0.16` — Apache-2.0

Their complete license texts remain in the corresponding `third_party/`
submodules. `ios/scripts/build_baresip_ios.sh` verifies the pinned revisions
before compiling. The generated `Baresip.xcframework` is a build artifact and
is intentionally not committed.
