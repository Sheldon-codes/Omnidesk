# Android native AT media — Gate 0/1 decisions

Status: Gate 0/1 decisions remain the architecture baseline. Gate 2 transport,
service ownership, Flutter bridge, and local tests are implemented. User
authorized beginning Gate 3 before Gate 2's complete lifecycle acceptance so
both can be exercised together. Gate 2 passed a real Samsung-device
registration handshake and reuse check; repeated dispose/reinitialize and
Activity-recreation acceptance remain open. Gate 3 outbound implementation
and local verification are in progress; real-device media acceptance has not
passed. Android continues to select `WebViewCallMediaService` by default; the
existing path is unchanged unless the opt-in flag is set.

## Scope and source-of-truth behavior

Android will implement the same Africa's Talking (AT) wire protocol and
observable call behavior as the working iOS Swift client, using Kotlin and
Android-native WebRTC APIs. It is a protocol/state-machine parity port, not a
line-by-line language port. Keep the existing `CallMediaService`, backend
`/calls/media-config` and accept/media-ready flow, Flutter call state machine,
and UI. No Baresip/SIP migration or cleanup is in scope.

The protocol baseline remains
[`africastalking-native-protocol.md`](africastalking-native-protocol.md):
`at-protocol` plus the capability token, Janus-compatible `create` then
`message/register`, SDK-derived call/answer/hangup/control messages, exact
candidate field shape, Unified Plan, balanced BUNDLE, RTCP mux, standard
DTLS-SRTP, and unmodified SDP. ICE servers remain the verified empty list;
Android must not add public STUN/TURN servers. Never persist or log the
capability token, SDP, ICE credentials, or full signaling frames.

## Native media lifetime ownership

**Owner:** `OmniDeskCallForegroundService` owns the active
`ATNativeMediaCoordinator`, `ATWebRTCSession`, and its single
`AndroidCallAudioCoordinator`.
Neither `MainActivity` nor a Flutter widget/engine owns either coordinator.
The service already exists and starts on the inbound Telecom `markAnswering`
path before `/accept` and media preparation; the outbound media bridge will
start/bind it before native media initialization and microphone capture.

The service creates both coordinators in `onCreate`, serializes commands on
its own handler/dispatcher, and publishes an immutable call/media snapshot
with monotonically increasing event sequence numbers. It remains foreground
for call setup and the active call. `START_NOT_STICKY` is the fail-safe after
process death: Android must not restart a phantom call from a stale intent.
On all normal terminal paths, one idempotent teardown closes the AT socket
and peer connection, releases the audio lease/routes/focus, clears active
identity, then allows Telecom cleanup to stop the service. Registration-only
sessions are also bounded and explicitly disposed; credentials are never
written to disk.

`AndroidCallMediaRuntime` is an application-context facade/binder client, not
the owner of media or audio resources. It binds/starts the foreground service,
queues bounded commands until binding completes, and exposes the current
snapshot/events to clients. `AndroidNativeCallMediaPlugin` is attached to a
Flutter engine and connects its method/event channel to this facade. Engine
detachment removes only that engine's listener/binding; it does not dispose
the service-owned coordinator.

| Lifecycle | Expected behavior |
|---|---|
| Activity recreation | The service and coordinator continue. The new Activity/engine attaches a new plugin client, binds, requests the latest snapshot, then subscribes from its sequence cursor. |
| Flutter navigation/rebuild | No native ownership change. Screen/widget disposal cannot end media. |
| App background / screen lock | The foreground service continues to own the active call and microphone use, subject to Android permission and foreground-service policy. UI visibility is irrelevant to media ownership. |
| Telecom-managed active call | `OmniDeskConnectionService`/`OmniDeskTelecomManager` send lifecycle/control requests through `AndroidCallMediaRuntime` to the service. They do not instantiate WebRTC or touch audio routes. |
| Flutter engine recreation | A new engine registers/attaches the plugin, reconnects to the service and receives the snapshot plus subsequent events. The service's single active-call identity prevents duplicate initialization. |
| Android process actually killed | Nothing can keep the socket/peer connection alive after process death. The call is considered lost; there is no automatic media resurrection or mid-call WebView fallback. On next app/FCM launch, reconcile durable Telecom/backend state, clear stale presentation, and report/finish the stale call. The remote/provider leg may persist until AT observes disconnect/timeout, so backend reconciliation is required. |

Telecom will reach media through the application-context runtime facade and
the foreground-service binder. Telecom callbacks remain the source of system
call actions; they only issue commands (`answer`, `end`, `hold`, `route`) and
reflect the resulting call state. A route command is not permission for a
Telecom class to call `AudioManager` directly.

## Single Android call-audio authority

`AndroidCallAudioCoordinator` is the sole app component allowed to mutate
call-related audio policy/state: `AudioManager.mode`, audio focus,
communication-device selection, speaker/earpiece selection, Bluetooth and
wired/USB route selection, and audio cleanup/reset. It owns an idempotent
audio lease for the service's active call, serializes requests, snapshots
prior state where supported, reports the effective route, observes device
changes, and restores/clears state exactly once on release.

- API 31+: use `AudioManager.setCommunicationDevice()` and
  `clearCommunicationDevice()`, and observe available/current devices. This
  covers modern communication routing; Android 13+ BLE Audio devices must be
  handled through this API. [Android self-managed call audio guide](https://developer.android.com/develop/connectivity/bluetooth/ble-audio/audio-manager?hl=en)
- API 26–30: coordinator owns `AudioFocusRequest`, `MODE_IN_COMMUNICATION`,
  legacy speakerphone selection, and Bluetooth SCO start/stop when required.
- API 24–25 (the app's current minimum): coordinator uses legacy audio-focus
  APIs, communication mode, speakerphone routing, and SCO routing. Wired
  device arrival/removal is observed and system routing is allowed to take
  precedence where the old API cannot explicitly select a device.

The pinned WebRTC `JavaAudioDeviceModule` is used only for capture/playout. A
source audit of its exact `WebRtcAudioManager` and module entry points found
that they query `AudioManager` for device/rate capabilities but do not call
`setMode`, request/abandon audio focus, or select communication devices.
`ATWebRTCSession` waits for the audio coordinator's ready lease and consumes
the selected route/status; it has no `AudioManager` reference. No independent
WebRTC audio-route manager is to be created.

Current code sites that must be centralized before enabling native Android:

- `OmniDeskTelecomManager.setSpeaker()` and its cleanup route reset currently
  mutate `AudioManager` directly; replace them with runtime/coordinator
  requests and remove those direct writes.
- `BaresipMediaCoordinator.setSpeaker()` also directly mutates routes. The
  Baresip call stack remains out of scope, but this setter must delegate to
  the same coordinator (or become unavailable) so it cannot violate the
  single-authority invariant.
- `MainActivity` may translate Flutter's route request but must not obtain or
  mutate `AudioManager` itself.
- `OmniDeskConnectionService`/`OmniDeskConnection` may report Telecom state
  and dispatch actions; they must not set audio mode or routes.

`JavaAudioDeviceModule` is not given a competing route policy. Tests and
static checks must reject direct route/focus/mode mutations outside
`AndroidCallAudioCoordinator`, except reads/listeners that only observe OS
state. Android's own Telecom/OS internals remain system-managed; this
single-owner rule applies to OmniDesk app code.

## Gate 1 dependency selection and verification

Selected artifact:

```text
Maven coordinate: io.github.webrtc-sdk:android:150.7871.01
Artifact: android-150.7871.01.aar
SHA-256: 0a1627b1a48c2bc17d9a40d62fc47bd45166f44a311e95917f147c402de379b0
License: BSD 3-Clause
```

The Android SDK release PR maps `150.7871.01` to the exact
`webrtc-sdk/webrtc` source commit
`73cb8180f7258ee292878d6edd05177f41883962`; it identifies the M150 / WebRTC
`branch-heads/7871` line. This is the SDK-maintained WebRTC source fork, not a
claim that the published AAR is built from Google's untouched tree. The
release correspondence and source commit are recorded by the [Android SDK
release PR](https://github.com/webrtc-sdk/android/pull/53) and its [source
commit](https://github.com/webrtc-sdk/webrtc/commit/73cb8180f7258ee292878d6edd05177f41883962).
The Maven POM identifies the AAR, BSD-3-Clause license, and source project.
The Maven `.sha256` sidecar and an independent local SHA-256 of the downloaded
AAR both equal the hash above.

The AAR was inspected directly:

- Contains native `libjingle_peerconnection_so.so` for `arm64-v8a`,
  `armeabi-v7a`, `x86_64`, and `x86`; current project declares no ABI filter.
- Its manifest minimum is API 21, compatible with this app's effective
  `minSdk 24`. The artifact manifest target 23 does not raise or replace the
  application's target SDK.
- `arm64-v8a` and `x86_64` ELF `PT_LOAD` segments have 16 KB alignment;
  32-bit ABIs have 4 KB alignment. The artifact is ~46.8 MiB, so split APKs
  or app-bundle delivery should be used to avoid shipping every ABI to each
  device.
- It is a standard AAR with Java API classes and packaged JNI `.so` files;
  its POM declares no transitive dependencies and no Gradle plugin or Kotlin
  API. It is consumed by the app's existing Android Gradle plugin.

Project toolchain at audit time: `minSdk 24`, `targetSdk 36`, `compileSdk 37`,
AGP `9.3.3`, Gradle wrapper `9.5.0`, Kotlin Gradle plugin `2.3.20`, Java/JVM
17. The dependency is an AAR, not a Gradle/Kotlin plugin, so its bytecode/API
does not impose a Kotlin compiler or AGP plugin-version constraint; the
manifest minSdk is lower than the app minimum. Compatibility was exercised
by temporarily injecting the exact dependency into `debugImplementation`
without changing the checked-in Gradle file or provider: dependency
resolution, `:app:checkDebugAarMetadata`, Flutter/Kotlin compilation,
`:app:mergeDebugNativeLibs`, and native symbol stripping all passed with AGP
9.3.3 / Gradle 9.5.0 / Kotlin 2.3.20. Final `:app:packageDebug` failed with
`No space left on device`; this is an environment-capacity failure, not an
AAR or toolchain incompatibility. The temporary dependency declaration has
been removed, so current Android builds do not package the 46.8 MiB library.
Before Gate 2 runtime code, add the exact coordinate with Gradle dependency
verification using the SHA-256 above and complete a package build after
resolving disk capacity. Do not use a dynamic version. Keep the WebView
provider selected; do not add a migration selector or change media behavior
in Gate 1.

The peer-connection configuration must explicitly set Unified Plan,
`BALANCED` BUNDLE, required RTCP mux and `iceServers = []`. Do not rewrite SDP;
let native WebRTC perform standard DTLS-SRTP. The AT candidate serialization
remains the iOS-proven `candidate`, `sdpMid`, and `sdpMLineIndex` shape,
including the SDK's end-of-candidates representation.

## Gate 2 implementation status — transport and registration

The implementation adds the pinned
`io.github.webrtc-sdk:android:150.7871.01` runtime dependency and strict Gradle
SHA-256 dependency verification in
[`android/gradle/verification-metadata.xml`](../../android/gradle/verification-metadata.xml).
The WebRTC artifact entry is the Gate 1 checksum
`0a1627b1a48c2bc17d9a40d62fc47bd45166f44a311e95917f147c402de379b0`. The
Debug package build ran with the actual AAR resolved and packaged all four
declared ABIs. The current opt-in universal Debug APK is large (~280 MiB),
since this project does not ABI-split its debug output.

The signaling WebSocket uses pinned OkHttp `5.4.0` (Apache-2.0; upstream
[release history](https://github.com/square/okhttp/blob/master/CHANGELOG.md)).
No HTTP logging interceptor is present. The request offers the same ordered
subprotocol values as iOS: `at-protocol, <capability-token>`. The only
credential source is the Flutter `CallMediaConfig` populated by
`/calls/media-config`; Android requires a non-empty backend gateway URL and
does not substitute a hardcoded gateway. The token is neither persisted nor
included in logs, diagnostics, channel results, or errors.

`OmniDeskCallForegroundService.onCreate()` creates the service-owned
`ATNativeMediaCoordinator` and `AndroidCallAudioCoordinator`. Its local Binder
provides initialize/dispose, route delegation, immutable snapshots, and
monotonic event sequence numbers. `AndroidCallMediaRuntime` owns only an
application-context binding and listener registry; engine detach unbinds that
listener and does not dispose the started service's registration. A reattached
engine receives the current snapshot and sequence before consuming new events.
Service restart remains `START_NOT_STICKY`; process death is terminal.

The signaling state machine is serialized on one scheduled executor and
generation-fences every socket callback. It performs only:

```text
WebSocket opened → Janus create → response/success → message/register → AT registered
```

Connect is bounded by 12 seconds at the socket and 15 seconds in the
registration state machine; Janus create and AT register each have bounded
10/15-second waits. The keepalive interval is 30 seconds after registration.
Unknown messages are ignored with a sanitized diagnostic. Duplicate initialize
joins/reuses the same matching registration; disposal is idempotent. There is
no reconnect/recovery loop and no native-to-WebView fallback. A real Samsung
SM-A165F logged in and supplied fresh `/calls/media-config` credentials; the
sanitized device sequence recorded WebSocket open with
`accepted_at_protocol`, Janus `create_success`, `register_sent`, and AT
`registered`. Follow-up app background/foreground cycles reused generation 1
without opening duplicate sockets. Explicit dispose/reinitialize and Activity
recreation remain untested, so Gate 2 is pending those lifecycle checks.

The engine plugin is added by `MainActivity` to each Flutter engine and exposes
`africa.omnidesk/media` plus `africa.omnidesk/media_events`. Android native
media is selected by default; pass
`--dart-define=USE_ANDROID_NATIVE_AT_MEDIA=false` to explicitly select the
existing WebView implementation. Existing Telecom speaker and cleanup
requests delegate through the service audio coordinator; the only remaining
app-code `AudioManager` mutation site is `AndroidCallAudioCoordinator`.

Local test coverage exercises wire command serialization, Janus response
decoding, create/register progression, connect/create/register timeout or
registration rejection, stale-generation callbacks, duplicate initialize,
idempotent disposal, token redaction, and Flutter-engine detach/reattach without
disposing the service-owned registration, outbound offer/candidate signaling,
and requiring both AT acceptance and ICE connectivity before `connected`.
Dart tests cover backend config forwarding and outbound native operations;
inbound answer remains unavailable. Kotlin unit tests, targeted Flutter tests,
Flutter analysis, and a debug APK assembly have passed.

## Gate 3 implementation status — outbound only

`ATWebRTCSession` owns one audio-only Unified Plan PeerConnection and uses the
pinned WebRTC ADM for audio capture/playout. It requests the service-owned
audio lease before creating the peer connection, configures balanced BUNDLE,
required RTCP mux, and an empty ICE-server list, and passes SDP and AT
candidate fields without munging. Local candidates are buffered until the
outbound `call` request has been sent, then serialized as AT `trickle`
messages; end-of-candidates uses the protocol's completed representation.
Provider `accepted` plus WebRTC peer connectivity are both required before
publishing `connected`. A bounded connection timeout terminates the native
media leg. Flutter still creates the backend call through the existing flow;
the native service handles only the media leg. Inbound events are ignored and
answer remains unimplemented. There is no WebView fallback after native
selection.

The service promotes to microphone foreground-service mode before creating
the offer and releases the peer/audio lease on terminal events. Native Android
media is enabled by default, with WebView available through the explicit
`USE_ANDROID_NATIVE_AT_MEDIA=false` opt-out. Physical
outbound negotiation, two-way audio, route controls, and call teardown are not
yet validated; do not count Gate 3 as passed until tested on the Samsung
device with a safe destination.

**Remaining real-device acceptance:** repeat registration with dispose then
reinitialize, recreate the Activity/Flutter engine while preserving service
registration, and capture sanitized evidence. Then test Gate 3 outbound setup
and connected two-way audio. Local tests and APK builds do not substitute for
these device checks.

## Planned implementation file map (Gate 2 onward)

Add:

- `android/app/src/main/kotlin/com/bigbrainzsolutions/omnidesk/ATNativeMediaCoordinator.kt`
- `.../ATSignalingClient.kt` and `.../ATSignalingModels.kt`
- `.../ATWebRTCSession.kt`
- `.../AndroidCallAudioCoordinator.kt`
- `.../AndroidCallMediaRuntime.kt` (application-context facade, binder,
  reconnect/snapshot/event sequencing; not a media owner)
- `.../AndroidNativeCallMediaPlugin.kt` (engine-scoped Flutter channel client)
- `lib/services/calls/android_native_call_media_service.dart`
- protocol/state-machine tests under `android/app/src/test`, plugin/service
  tests where feasible, and Flutter adapter/provider tests under `test/`.

Change:

- `OmniDeskCallForegroundService.kt` to own coordinator construction,
  service binding, event snapshots, and active-call lifetime.
- `OmniDeskTelecomManager.kt`, `OmniDeskConnectionService.kt`,
  `OmniDeskCallActionReceiver.kt`, and `MainActivity.kt` to route system and
  Flutter actions through the runtime/audio authority, with no direct
  `AudioManager` mutations outside `AndroidCallAudioCoordinator`.
- `BaresipMediaCoordinator.kt` only to remove/delegate its direct speaker
  route mutation; no Baresip cleanup or SIP behavior change.
- `call_media_provider.dart` to add `USE_ANDROID_NATIVE_AT_MEDIA`, defaulting
  to `true` for the current native validation rollout. `false` is an explicit
  pre-call rollback to the intact Android WebView path; never switch engines
  after a call has started.
- `android/app/build.gradle.kts` and Gradle verification metadata to pin the
  exact AAR/hash when runtime implementation begins. Keep native dependency
  packaging out of current production builds until it is actually selected,
  avoiding a premature ~47 MiB app increase.

## Android differences from Swift/iOS

- Swift signaling is serialized on iOS queues/MainActor and media lifetime is
  in the Runner process. Android uses Kotlin coroutines/handler serialization
  and a foreground-service-owned coordinator that outlives Activities and
  Flutter engines.
- CallKit activation owns iOS `AVAudioSession`. For native Android Telecom
  calls, Telecom owns system focus and call audio mode. The foreground-service
  `AndroidCallAudioCoordinator` owns the app-side readiness lease and is the
  only app component that may request call routes; it delegates those requests
  through the matching Telecom `Connection`. WebRTC cannot start capture or
  playout until this lease is ready and never requests AudioManager focus.
- `URLSessionWebSocketTask` becomes an Android WebSocket transport; preserve
  the same subprotocol negotiation and never put the token in logs or URL.
- Android runtime microphone permission and foreground-service restrictions
  apply while capturing. Start the existing call FGS from the Telecom answer
  path (already done for inbound) and before outbound native capture; do not
  assume Activity visibility grants process survival.
- Native API types and audio callbacks differ, but wire messages, SDP policy,
  candidate shape, ICE source, success criteria, and terminal semantics must
  remain the same as the working Swift implementation.

## Incoming Telecom audio-focus correction

The Samsung capture established that Telecom remained in `RINGING` after the
answer action while the WebRTC path requested its own AudioManager focus. The
request failed while Telecom owned ringing focus. The native answer path now
leaves the connection ringing while permission and backend `/accept` complete;
only the matching accepted call transitions to Telecom `ACTIVE`. This system
transition is not a Flutter-connected event. Native media starts only after
the service confirms foreground promotion, eligible connection state, and
Telecom focus (API 28+); API 26–27 use the eligible connection's audio-state
callback as their compatibility signal. System route requests use Telecom
endpoint APIs on API 34+ and the legacy Telecom route API below that.

The intermittent Bluetooth/audio-focus behavior remains a separate hardening
item. It has succeeded on-device without code changes and is not being tuned
as part of this deterministic focus-ownership correction. Hardening should
exercise focus loss/gain races, endpoint changes, Bluetooth and wired route
changes, and cleanup/repeated-call behavior on representative Samsung and
non-Samsung devices.
