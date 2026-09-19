# Native SIP third-party notices

The iOS build script pins and builds these source dependencies:

- Baresip `v3.24.0` — BSD-3-Clause
- Libre `v3.24.0` — BSD-3-Clause
- OpenSSL `3.0.16` — Apache-2.0

Their complete license texts remain in the corresponding `third_party/`
submodules. `ios/scripts/build_baresip_ios.sh` verifies the pinned revisions
before compiling. The generated `Baresip.xcframework` is a build artifact and
is intentionally not committed.
