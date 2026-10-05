Yes. **I think this is the right next experiment**, but I would build it as an isolated iOS native-media proof first, behind your existing `CallMediaService`, rather than immediately deleting the WebView implementation.

The current AT package is actively published as **1.0.8**, uses capability tokens, and publicly exposes the same call/answer/hangup/DTMF/mute/hold contract you're already using. [npm](https://www.npmjs.com/package/africastalking-client?activeTab=readme\&utm_source=chatgpt.com) Combined with what we found in your exact 1.0.7 bundle—WebSocket signaling + SDP/JSEP + standard WebRTC—the native-client approach is credible enough to implement and test.

The critical goal is very simple:

> **Can a physical iPhone establish a two-way Africa's Talking call using native WebRTC, with `outboundAudioBytes > 0`, `inboundAudioBytes > 0`, audible remote audio, and audible microphone audio?**

If yes, the WKWebView can be retired on iOS.

---

# Codex implementation specification: Native Africa's Talking WebRTC client for iOS

## 1. Objective

Implement an **experimental native iOS Africa's Talking WebRTC media client** for OmniDesk that replaces the WKWebView media engine **on iOS only**.

Do not rewrite the rest of the calling architecture.

The target is:

```text
                        OmniDesk Flutter
                              │
                     CallSessionController
                              │
                       CallMediaService
                              │
               ┌──────────────┴──────────────┐
               │                             │
            Android                         iOS
               │                             │
 WebViewCallMediaService          IOSNativeCallMediaService
               │                             │
       AT JavaScript SDK                 MethodChannel
                                             │
                                      Swift native client
                                             │
                              ┌──────────────┴──────────────┐
                              │                             │
                       AT signaling                   WebRTC native
                              │                             │
                   WebSocket/JSEP/ICE              microphone/audio
                              │                             │
                              └──────────────┬──────────────┘
                                             │
                                   Africa's Talking
```

Android must remain untouched.

The existing WebView implementation must initially remain available as an iOS fallback/debug comparison until the native proof succeeds.

---

# 2. First gate: extract the exact AT protocol

**Do not start by guessing network messages.**

Before implementing the Swift client, inspect:

```text
assets/js/africastalking-client-1.0.7.min.js
```

and the current 1.0.8 package if available.

The public API confirms the client contract includes `call`, `answer`, `hangup`, `dtmf`, `mute`, `unmute`, `hold`, `unhold`, and `destroy`, with events including `ready`, `notready`, `calling`, `incomingcall`, `callaccepted`, `hangup`, `offline`, and `closed`. [npm](https://www.npmjs.com/package/africastalking-client?activeTab=readme\&utm_source=chatgpt.com)

Create:

```text
docs/voice/africastalking-native-protocol.md
```

Document, from the actual source:

```text
WebSocket endpoint
WebSocket subprotocol/authentication
registration request
registration success
registration failure
keepalive interval/frame
outgoing call request
incoming call event
ringing/progress event
accepted event
SDP offer format
SDP answer format
local ICE candidate format
remote ICE candidate format
end-of-candidates behavior
hangup request/event
decline request/event
hold/unhold
DTMF
mute semantics
server errors
token expiry/offline
WebSocket close
reconnect behavior
session/call identifiers
```

For every protocol frame, record:

```text
direction
event/request name
required fields
optional fields
state in which it is valid
corresponding AT SDK method/event
```

### Very important

Do not invent fields from memory.

Do not reverse engineer credentials.

Do not bypass AT authentication.

Use only the capability token already legitimately returned by:

```text
GET /calls/media-config
```

Do not put the Africa's Talking API key in the mobile application.

The current AT documentation says capability-token creation itself requires the server-side API key; the mobile client should continue receiving only the resulting capability token. [npm](https://www.npmjs.com/package/africastalking-client?activeTab=readme\&utm_source=chatgpt.com)

---

# 3. Compare 1.0.7 against 1.0.8

Before copying protocol behavior, obtain the current `africastalking-client@1.0.8` package and diff its relevant source against 1.0.7.

Specifically inspect changes around:

```text
WebSocket creation
registration
RTCPeerConnection
getUserMedia
audio tracks
ICE
SDP
call()
answer()
hangup()
hold()
DTMF
mute/unmute
reconnection
Safari/iOS handling
```

Do not automatically upgrade OmniDesk's WebView client.

The purpose is to determine which protocol behavior represents the current server contract.

Document differences in:

```text
docs/voice/africastalking-1.0.7-vs-1.0.8.md
```

If the signaling protocol differs, implement the current 1.0.8 behavior unless doing so is incompatible with the capability tokens currently returned by OmniDesk.

---

# 4. Native dependency selection

Use a maintained native WebRTC implementation exposing the standard iOS WebRTC APIs:

```text
RTCPeerConnectionFactory
RTCPeerConnection
RTCAudioTrack
RTCRtpSender
RTCSessionDescription
RTCIceCandidate
RTCConfiguration
RTCMediaConstraints
```

Do **not** introduce:

```text
flutter_webrtc
another WebView
JavaScriptCore executing AT SDK
Node runtime
SIP
CallKeep
```

for this experiment.

The purpose is specifically to test:

```text
Swift
+
native WebRTC
+
AVAudioSession
+
CallKit
```

without browser media in between.

Before modifying Podfile/SPM dependencies, verify the current maintained iOS WebRTC distribution and its minimum iOS requirements. Don't have Codex blindly select an old pod just because an old tutorial uses it.

---

# 5. Create a native AT client independent of Flutter

I would structure the Swift implementation approximately like this:

```text
ios/Runner/Calling/ATNative/
    ATNativeClient.swift
    ATSignalingClient.swift
    ATWebRTCSession.swift
    ATAudioSessionController.swift
    ATProtocolModels.swift
    ATNativeClientDelegate.swift
    ATNativeDiagnostics.swift
```

Keep these responsibilities separate.

### `ATSignalingClient`

Owns:

```text
URLSessionWebSocketTask
connection
AT WebSocket subprotocol
capability token
register/unregister
keepalive
JSON encoding/decoding
signaling events
reconnection
```

It must **not** own AVAudioSession.

### `ATWebRTCSession`

Owns:

```text
RTCPeerConnectionFactory
RTCPeerConnection
local audio source
local audio track
remote audio track
offer/answer
local description
remote description
ICE candidate generation
remote ICE candidate application
candidate buffering
WebRTC statistics
cleanup
```

### `ATAudioSessionController`

Owns coordination with the CallKit-activated:

```text
AVAudioSession
```

It should not fight CallKit.

Your existing architecture correctly allows CallKit to activate the audio session.

Preserve that.

### `ATNativeClient`

High-level state machine combining signaling + WebRTC:

```text
idle
connecting
registering
ready
dialing
ringing
incoming
connectingMedia
connected
held
ending
ended
failed
```

---

# 6. Do not let native media own CallKit

This distinction matters.

The new native client is:

```text
MEDIA
```

not:

```text
SYSTEM CALL LIFECYCLE
```

Your existing `AppDelegate`/CallKit layer continues owning:

```text
PushKit
CXProvider
CXCallController
CXAnswerCallAction
CXEndCallAction
CXStartCallAction
CallKit UUID mapping
AVAudioSession activation callback
```

Native AT client owns:

```text
AT WebSocket
WebRTC
RTP
microphone
remote audio
```

Do not combine those into one enormous Swift class.

---

# 7. Add an explicit CallKit audio activation gate

This is worth fixing while creating the native implementation.

Maintain native state:

```swift
enum CallKitAudioState {
    case inactive
    case activating
    case active
}
```

When:

```swift
provider(_:didActivate:)
```

fires:

```text
CallKitAudioState → active
```

The native WebRTC client may:

```text
connect signaling
register
create peer connection
prepare call state
```

before that.

But **microphone/audio transport must not begin until CallKit has activated the session for an active CallKit call.**

For incoming:

```text
PushKit
→ report CallKit incoming call
→ AT signaling may initialize/prewarm
→ user answers
→ CXAnswerCallAction
→ CallKit activates AVAudioSession
→ native media allowed to start/attach audio
```

For outgoing:

```text
Flutter initiate
→ CXStartCallAction
→ AT signaling initialization
→ CallKit activation
→ native WebRTC audio
```

Use a bounded timeout rather than waiting forever.

---

# 8. Implement WebSocket authentication exactly like AT

From the 1.0.7 bundle analysis, the AT client opens its provider WebSocket using the AT protocol and capability token as WebSocket subprotocol values.

Implement the exact extracted behavior.

Conceptually:

```swift
var request = URLRequest(
    url: URL(string: gateway)!
)

request.setValue(
    "...exact protocol values...",
    forHTTPHeaderField: "Sec-WebSocket-Protocol"
)
```

But Codex must follow the documented protocol extraction rather than copying this conceptual snippet blindly.

Do not log the capability token.

Diagnostics may log:

```text
gateway host
connection state
selected WebSocket protocol
registration state
elapsed milliseconds
```

Never:

```text
full token
Authorization
API key
SDP
ICE credentials
```

---

# 9. Implement registration before calls

Native initialization should correspond to the existing:

```dart
CallMediaService.initialize(config)
```

Expected lifecycle:

```text
initialize(config)
      ↓
validate:
  transport == webrtc
  token present
  gateway present
  clientName present
      ↓
connect WebSocket
      ↓
register client
      ↓
receive registered/ready
      ↓
emit CallMediaEvent.ready
```

`initialize()` must be idempotent for the same valid configuration.

Do not create a new WebSocket every time `dial()` is called if an existing healthy registered client can be reused.

---

# 10. Outgoing native call flow

Map:

```dart
media.dial(destination)
```

to:

```text
ensure registered
      ↓
ensure CallKit audio active
      ↓
create RTCPeerConnection
      ↓
create native microphone audio track
      ↓
add audio sender
      ↓
createOffer
      ↓
setLocalDescription
      ↓
send AT "call" request + JSEP
      ↓
receive calling/progress
      ↓
emit ringing
      ↓
receive remote JSEP
      ↓
setRemoteDescription
      ↓
exchange ICE
      ↓
peer connection connected
      ↓
AT accepted
      ↓
emit connected
```

Do not infer connected merely from one event.

Define the exact readiness condition based on the AT client behavior discovered during protocol extraction.

Ideally require:

```text
AT call accepted
AND
WebRTC connection connected
```

before reporting media connected.

---

# 11. Incoming native media flow

Preserve your current backend ordering:

```text
PushKit
→ CallKit incoming UI
→ Answer
→ /accept
→ media-config
→ native media initialize/register
→ /media-ready
→ backend bridges PSTN
→ AT incomingcall
→ media.answerIncoming()
```

Do not change this contract unless backend evidence requires it.

When AT emits incoming call:

```text
store remote offer/JSEP
store provider/session identity
emit CallMediaEvent.incoming
```

Then:

```dart
answerIncoming()
```

causes:

```text
ensure CallKit audio active
→ apply remote offer
→ createAnswer
→ setLocalDescription
→ send AT accept + JSEP
→ exchange ICE
→ connected
```

Never answer the provider call merely because `/media-ready` returned successfully.

That invariant from your current implementation must remain.

---

# 12. ICE handling must be complete

This is an area where a prototype can appear to work on Wi-Fi and fail everywhere else.

Implement:

```text
local ICE candidates
remote ICE candidates
candidate buffering before remoteDescription
flush buffered candidates after remoteDescription
end-of-candidates
ICE gathering state
ICE connection state
connection state
failed/disconnected recovery
```

If the AT SDK obtains ICE servers dynamically from signaling, reproduce that exact behavior.

Do not hardcode Google's STUN server or some random TURN server to make the test pass.

Use whatever configuration AT actually supplies/uses.

---

# 13. Native audio

This is the entire reason we're doing the experiment.

The WebRTC session should use a native audio track:

```text
native microphone
→ WebRTC audio source
→ RTCAudioTrack
→ RTCRtpSender
```

Remote:

```text
RTP receiver
→ native WebRTC audio output
→ AVAudioSession route
```

There should be **no**:

```text
HTMLAudioElement
MediaStream
getUserMedia
WKWebView
JavaScript audio track
```

on iOS native calls.

---

# 14. Audio route ownership

Preserve your existing CallKit-compatible audio-session configuration:

```text
.playAndRecord
.voiceChat
Bluetooth support
```

Do not repeatedly call:

```swift
AVAudioSession.setActive(true)
```

from the WebRTC client while CallKit owns activation.

Handle:

```text
receiver
speaker
Bluetooth HFP
wired headset
route changes
interruptions
CallKit didActivate
CallKit didDeactivate
```

Your existing:

```dart
setSystemSpeaker(...)
```

must still work.

Map it through native code to the appropriate output route behavior without resetting the whole session.

---

# 15. Mute

Implement:

```dart
setMuted(true)
```

by disabling the native local WebRTC audio track/sender—not by changing global iOS microphone permission or tearing down AVAudioSession.

Expected:

```text
muted:
localAudioTrack.isEnabled = false

unmuted:
localAudioTrack.isEnabled = true
```

The exact API depends on the selected native WebRTC distribution.

---

# 16. Hold

Don't fake hold.

First reproduce whatever AT's 1.0.8 client actually does for:

```text
hold()
unhold()
```

If AT signaling sends explicit hold/unhold requests, implement them.

If it also manipulates transceivers/tracks, reproduce that.

Then map:

```dart
setHeld(true/false)
```

to native.

Also synchronize with CallKit's hold state eventually.

For the first two-way-audio proof, hold can remain behind a feature gate if necessary. It must not block proving the core call.

---

# 17. DTMF

Inspect whether AT uses:

```text
RTCDTMFSender
```

or a signaling request.

Reproduce exactly.

Map:

```dart
sendDtmf("5")
```

to the native equivalent.

Again, DTMF is not required for the first audio proof, but the architecture should leave it straightforward.

---

# 18. Hangup and cleanup

Both local and remote hangup must converge on one idempotent cleanup path.

It should:

```text
stop call timers
close RTCPeerConnection
release tracks/senders
clear candidate buffers
clear call-specific AT state
emit ended once
preserve registered WebSocket if reusable
```

Do **not** destroy the entire registered AT client after every successful call unless the protocol requires it.

This gives you the same future prewarming advantage you were trying to achieve with the WebView.

---

# 19. Connection reuse

Design the native client to remain registered while the authenticated agent is available.

Target:

```text
app/process alive
       ↓
AT client registered
       ↓
idle
       ↓
incoming/outgoing call
       ↓
peer connection created
       ↓
call ends
       ↓
peer connection destroyed
       ↓
AT signaling remains registered
```

This can dramatically reduce subsequent call setup latency.

Reconnect if:

```text
WebSocket closes unexpectedly
token expires
network changes
registration fails
```

with bounded exponential backoff.

Do not reconnect indefinitely after logout/dispose.

---

# 20. Flutter bridge

Add native methods behind your existing calls channel or, preferably, a clearly namespaced native-media bridge.

For example:

```text
nativeMediaInitialize
nativeMediaDial
nativeMediaAnswer
nativeMediaHangup
nativeMediaSetMuted
nativeMediaSetHeld
nativeMediaSendDtmf
nativeMediaDispose
nativeMediaGetDiagnostics
```

Native → Dart events:

```text
nativeMediaReady
nativeMediaRinging
nativeMediaIncoming
nativeMediaConnected
nativeMediaEnded
nativeMediaHeld
nativeMediaError
nativeMediaDiagnostic
```

Do not expose raw AT protocol frames to the Flutter state machine.

---

# 21. Implement `IOSNativeCallMediaService`

In Dart:

```text
lib/services/calls/ios_native_call_media_service.dart
```

Implement the exact existing:

```dart
CallMediaService
```

contract.

It should translate native events into the same:

```text
ready
ringing
incoming
connected
ended
held
error
micStatus
processTerminated
```

semantics the rest of OmniDesk already expects.

The `CallSessionController` should **not care** whether media came from:

```text
WKWebView
or
Swift
```

That's the acceptance criterion for the abstraction.

---

# 22. Provider selection

Initially use a debug/feature flag.

Conceptually:

```dart
if (Platform.isIOS && nativeAtMediaEnabled) {
  return iosNativeCallMediaService;
}

return webViewCallMediaService;
```

Android must always continue using the proven WebView implementation during this experiment.

For iOS development, make switching between:

```text
native
webview
```

easy so the exact same backend call can be compared.

Once native passes acceptance testing, make:

```text
iOS → native
Android → WebView
```

the production default.

---

# 23. Do not delete the WebView yet

This is important.

Do not let Codex do:

```text
native implementation
+
delete WebView
+
remove assets
+
rewrite call controller
```

in one enormous change.

Keep:

```text
WebViewCallMediaService
AT JS assets
bridge
```

until native passes.

Then remove the iOS dependency on them in a separate cleanup.

Android still needs them anyway.

---

# 24. Diagnostics must be first-class

The native implementation should be considerably easier to debug than the current WebView.

Every call should produce a correlated timeline such as:

```text
[ATNative][call_id]
+0ms initialize
+4ms websocket_connect_start
+180ms websocket_connected
+185ms register_sent
+312ms registered

+1240ms call_start
+1245ms callkit_audio_active
+1250ms peer_connection_created
+1260ms local_audio_track_created
+1270ms offer_create_start
+1290ms offer_created
+1305ms local_description_set
+1310ms call_request_sent
+1500ms ice_candidate_local
+1720ms progress
+1810ms remote_description_set
+2100ms ice_connected
+2230ms peer_connected
+2290ms at_accepted
+2300ms media_connected
```

Never log:

```text
capability token
API key
Authorization header
full SDP
ICE username/password
full customer phone number
```

---

# 25. Native WebRTC statistics

Add periodic stats while a call is connected.

At minimum:

```text
outbound audio bytesSent
outbound packetsSent
inbound audio bytesReceived
inbound packetsReceived
packetsLost
jitter
roundTripTime where available
audioLevel where available
ICE candidate pair state
connectionState
iceConnectionState
signalingState
selected local candidate type
selected remote candidate type
```

This is essential because our success condition is not merely:

```text
connected event fired
```

It is:

```text
real audio is moving both ways.
```

---

# 26. The first proof must be intentionally tiny

Do **not** implement every feature before testing.

### Milestone A — registration

Physical iPhone:

```text
media-config
→ native WebSocket
→ register
→ READY
```

Nothing else.

**Gate:** native client can register consistently 10/10 times.

### Milestone B — outbound signaling

```text
native client
→ create offer
→ AT call request
→ destination phone rings
```

Don't worry about beautiful UI.

**Gate:** normal phone receives the call.

### Milestone C — two-way native audio

This is the decisive milestone.

Agent speaks into iPhone:

```text
iPhone mic
→ native WebRTC
→ AT
→ normal phone
```

Normal phone speaks:

```text
normal phone
→ AT
→ native WebRTC
→ iPhone receiver/speaker
```

Require:

```text
local audio track enabled
outbound packets > 0
outbound bytes continuously increasing

inbound packets > 0
inbound bytes continuously increasing

human hears both directions
```

If this passes, **the architecture is validated**.

Only then continue.

### Milestone D — incoming

```text
PushKit
→ CallKit
→ Answer
→ /accept
→ native media ready
→ AT incoming
→ native answer
→ two-way audio
```

### Milestone E — controls

Add:

```text
mute
speaker
DTMF
hold
Bluetooth
wired headset
```

### Milestone F — resilience

Test:

```text
Wi-Fi → cellular
screen lock
background app
foreground app
Bluetooth connect/disconnect
audio interruption
remote hangup
caller cancels while ringing
network loss
token expiry
app termination
```

---

# 27. Do not modify backend protocol initially

Your existing backend already provides:

```text
transport=webrtc
token
gateway_url
client_name
```

That should be enough if the native client faithfully reproduces the AT browser client's behavior.

Do not introduce:

```text
/native-media-config
new AT credentials
SIP credentials
AT API key
```

unless protocol extraction proves additional information is genuinely required.

The capability-token model is documented by AT and remains present in current 1.0.8. [npm](https://www.npmjs.com/package/africastalking-client?activeTab=readme\&utm_source=chatgpt.com)

---

# 28. Security

The native client must follow these rules:

```text
AT API key stays backend-only.
Capability token is ephemeral client credential.
Never persist capability token unnecessarily.
Never log capability token.
Never log SDP.
Never log ICE credentials.
Never log Authorization.
TLS certificate validation remains enabled.
Do not disable ATS.
Do not accept arbitrary certificates.
Do not hardcode production secrets.
```

Do not add certificate-pinning during the proof unless OmniDesk already has a pinning strategy; that introduces an unrelated failure variable.

---

# 29. Failure taxonomy

Return structured native errors rather than strings like:

```text
"native call failed"
```

Use categories such as:

```text
signalingConnectionFailed
signalingRegistrationFailed
tokenRejected
tokenExpired
callRejected
remoteHangup
peerConnectionFailed
iceFailed
audioSessionUnavailable
microphoneUnavailable
offerCreationFailed
answerCreationFailed
remoteDescriptionFailed
localDescriptionFailed
protocolViolation
timeout
```

Translate them into your existing `CallMediaFailure` model where appropriate.

---

# 30. Tests

Add unit tests for the protocol/state machine without requiring real AT calls.

Mock:

```text
WebSocket transport
native peer abstraction where practical
clock/timers
```

Test:

```text
connect → registered → ready
registration failure
outgoing call state transitions
incoming call state transitions
remote candidate before remote SDP
candidate buffering/flush
remote hangup
local hangup
duplicate events
late events after teardown
token expiry
WebSocket close
reconnect
destroy during connect
two calls attempted simultaneously
```

Do not try to unit-test native WebRTC itself.

That gets physical-device integration tests.

---

# 31. Physical iPhone acceptance matrix

Before replacing the WebView implementation, test at least:

| Scenario | Required |
|---|---|
| Outbound over Wi-Fi | pass |
| Outbound over cellular | pass |
| Incoming over Wi-Fi | pass |
| Incoming over cellular | pass |
| Receiver audio | pass |
| Speaker audio | pass |
| Mic outbound | pass |
| Mute/unmute | pass |
| DTMF | pass |
| Hold/resume | pass |
| Remote hangup | pass |
| Local hangup | pass |
| Screen locked | pass |
| App foreground | pass |
| App background | pass |
| Cold incoming via PushKit | pass |
| Bluetooth headset | pass |
| Wired headset if available | pass |
| Repeat 10 calls | no progressive failure |

The critical regression metric is:

```text
10 consecutive calls
→ 10 two-way-audio successes
```

not simply 10 successful signaling connections.

---

# 32. Keep the separate iOS lifecycle fixes separate

Do not mix these into the native-media experiment unless required:

```text
call_cancelled delivery
PushKit malformed-payload handling
CallKit UUID cleanup
cold-start routing
ngrok replacement
```

They are real issues, but combining everything into one PR will make it impossible to tell why native media succeeds or fails.

---

# 33. Git/implementation sequence

I would have Codex make separate checkpoints:

```text
1. docs: document AT 1.0.7/1.0.8 signaling protocol
2. feat(ios): add native WebRTC dependency and AT signaling skeleton
3. feat(ios): implement AT registration
4. feat(ios): implement outbound native WebRTC
5. feat(ios): add native audio diagnostics
6. feat(ios): integrate IOSNativeCallMediaService
7. feat(ios): implement incoming native media
8. feat(ios): implement call controls
9. test(ios): harden native AT state machine
10. chore(ios): make native media default after acceptance
```

No giant one-shot commit.

---

# 34. Stop conditions

Codex should stop and report rather than inventing behavior if protocol extraction encounters:

```text
encrypted/opaque signaling frames
unknown binary payloads
undocumented token transformation
server-generated state that cannot be reproduced
required proprietary browser API
unknown ICE configuration
behavior that differs materially between 1.0.7 and 1.0.8
```

Likewise, don't “fix” protocol rejection by guessing message formats.

Capture the sanitized server response and inspect the AT implementation again.

---

# 35. Definition of success

The experiment is successful when a physical iPhone can do this **without creating a WKWebView**:

```text
CallKit active
        ↓
native AT client registered
        ↓
native RTCPeerConnection
        ↓
native microphone
        ↓
outbound RTP > 0
        ↓
Africa's Talking
        ↓
normal phone hears iPhone


normal phone
        ↓
Africa's Talking
        ↓
inbound RTP > 0
        ↓
native WebRTC audio output
        ↓
iPhone user hears normal phone
```

If that succeeds reliably, then we have the answer to the architecture question.

At that point production becomes:

```text
ANDROID
────────
FCM
Telecom
AT WebView media
Flutter UI


iOS
────────
PushKit
CallKit
AT native signaling
native WebRTC media
Flutter UI
```

and the troublesome iOS WKWebView media path can be retired.

---

## Prompt to give Codex

You can give the agent the specification above plus this instruction at the top:

> **Implement this sequentially with hard gates. Do not attempt the entire native client in one pass. Start by inspecting the exact bundled `africastalking-client-1.0.7.min.js`, the current 1.0.8 package, our existing `CallMediaService`, `WebViewCallMediaService`, `CallSessionController`, `NativeCallService`, and iOS `AppDelegate`. Produce `africastalking-native-protocol.md` and a concrete file-by-file implementation plan before changing runtime code.**
>
> **The goal is an iOS-only native Africa's Talking WebRTC client that reproduces the supported behavior of the AT JavaScript client without WKWebView. Android must remain unchanged. Preserve the existing Flutter `CallMediaService` contract, backend `/calls/media-config` contract, PushKit/CallKit architecture, and Flutter call UI. Do not introduce a SIP stack, `flutter_webrtc`, another WebView, or a second call state machine.**
>
> **The first implementation gate is AT WebSocket registration on a physical iPhone. The second is outbound signaling. The decisive third gate is real two-way native audio with increasing inbound and outbound RTP bytes. Stop and report if the AT wire protocol contains behavior that cannot be confidently derived from the shipped/public client; do not invent protocol messages.**

One correction from our earlier discussion is worth keeping in mind: current npm shows **`africastalking-client` 1.0.8 as the active release, published recently**, while search results for the older 1.0.7 metadata can still surface the old deprecation state. [npm](https://www.npmjs.com/package/africastalking-client?activeTab=readme\&utm_source=chatgpt.com) So Codex should treat **1.0.8 as the current comparison target**, while using your bundled 1.0.7 as the exact behavioral baseline that already works with your backend.

I would proceed with this now. It gives us a much cleaner yes/no result than continuing to tweak WKWebView audio.
