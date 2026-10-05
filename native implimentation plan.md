Yes. I think **this is the next thing to do**, but I would build it as an **isolated iOS-native proof of concept behind your existing `CallMediaService` boundary**, not immediately replace the WebView implementation.

That gives you a clean answer to the only question that now matters:

> Can the iPhone connect directly to Africa’s Talking using the same capability token and protocol, with native WebRTC audio, and achieve reliable two-way audio?

I inspected the exact `africastalking-client-1.0.7.min.js` bundle you uploaded. The protocol is sufficiently visible to attempt this. The current npm package is also active again at 1.0.8 and exposes the same high-level Voice client surface. [npm](https://www.npmjs.com/package/africastalking-client?activeTab=readme\&utm_source=chatgpt.com)

One implementation detail matters: the old `GoogleWebRTC` CocoaPod is deprecated, so I would **not design the production solution around that pod**. Official WebRTC still documents building `WebRTC.framework` directly from the upstream source, which is the safer long-term route. [CocoaPods](https://www.cocoapods.org/pods/GoogleWebRTC?utm_source=chatgpt.com)

Here is the plan I would give Codex.

---

# OmniDesk iOS Native Africa’s Talking WebRTC Client

## Goal

Build an **iOS-only native media implementation** that reproduces the behavior currently provided by `africastalking-client` inside WKWebView, while preserving:

```text
Flutter call UI
CallSessionController
CallLifecycleCoordinator
CallMediaService
backend call APIs
PushKit
CallKit
Android WebView media
```

Only replace:

```text
iOS:
WebViewCallMediaService
        ↓
IOSNativeATCallMediaService
        ↓
Swift AT native client
        ↓
native WebRTC
```

Do not rewrite Android.

Do not modify the backend call lifecycle unless the native protocol proves a backend contract change is necessary.

---

# 1. Architecture

Target:

```text
Flutter
─────────────────────────────────

CallSessionController
        │
        ▼
CallMediaService
        │
        ├── Android
        │      ↓
        │ WebViewCallMediaService
        │      ↓
        │ AT JavaScript SDK
        │
        └── iOS
               ↓
        IOSNativeCallMediaService
               ↓ MethodChannel
               ↓
Swift
─────────────────────────────────

ATNativeMediaCoordinator
        │
        ├── ATSignalingClient
        │       ↓
        │ URLSessionWebSocketTask
        │       ↓
        │ wss://webrtc.africastalking.com/connect
        │
        ├── ATWebRTCSession
        │       ↓
        │ RTCPeerConnection
        │       ↓
        │ native microphone/audio
        │
        └── CallKit / AVAudioSession
```

Important architectural rule:

```text
NativeCallService
= OS call surface only

CallMediaService
= media only
```

Do **not** add WebRTC methods into `NativeCallService`.

Your current abstraction explicitly separates those concerns already. native_call_service

Create a separate native media channel, for example:

```text
africa.omnidesk/media
```

not:

```text
africa.omnidesk/calls
```

---

# 2. Keep Android completely unchanged

Current provider:

```dart
final callMediaServiceProvider = Provider<CallMediaService>(
  (ref) => ref.watch(webViewCallMediaServiceProvider),
);
```

call_media_provider

Change only selection:

```dart
if (Platform.isIOS) {
  return ref.watch(iosNativeCallMediaServiceProvider);
}

return ref.watch(webViewCallMediaServiceProvider);
```

Initially put this behind a development flag:

```text
USE_IOS_NATIVE_AT_MEDIA=true
```

so you can instantly switch back to WKWebView during testing.

No fallback during an active call.

Do not attempt:

```text
native fails
→ silently switch to WebView
```

because that can create multiple AT registrations/media sessions.

---

# 3. Protocol baseline to reproduce

This section should be treated as the protocol specification derived from the exact 1.0.7 bundle currently proven against your backend.

## WebSocket connection

The JS client connects to:

```text
wss://webrtc.africastalking.com/connect
```

with WebSocket subprotocols:

```text
at-protocol
<capability-token>
```

Equivalent browser code:

```javascript
new WebSocket(server, [
  "at-protocol",
  capabilityToken
])
```

So Swift must negotiate the same WebSocket subprotocol headers.

Codex must verify that `URLSessionWebSocketTask` can send both expected subprotocol values in exactly the format AT accepts.

If Apple's API only exposes a single protocol entry cleanly, test the precise header serialization before proceeding.

Do not alter or decode the AT capability token.

---

# 4. WebSocket command model

Implement typed Swift models rather than throwing dictionaries around.

Suggested:

```swift
enum ATOutgoingCommand {
    case message(...)
    case trickle(...)
    case keepalive
    case destroy
}
```

The JS client sends application requests using:

```json
{
  "command": "message",
  "body": {
    "request": "..."
  }
}
```

Optional SDP/JSEP:

```json
{
  "command": "message",
  "body": {
    "request": "call"
  },
  "jsep": {
    "type": "offer",
    "sdp": "..."
  }
}
```

Trickle ICE:

```json
{
  "command": "trickle",
  "candidate": {
    ...
  }
}
```

Keepalive:

```json
{
  "command": "keepalive"
}
```

approximately every:

```text
30 seconds
```

Shutdown:

```json
{
  "command": "destroy"
}
```

before clean WebSocket close where possible.

---

# 5. AT request types

Implement these exact high-level operations first:

```text
register
unregister
call
accept
decline
hangup
hold
unhold
```

Do not add extra undocumented operations.

Registration:

```json
{
  "command": "message",
  "body": {
    "request": "register"
  }
}
```

Outbound:

```json
{
  "command": "message",
  "body": {
    "request": "call",
    "to": "+254..."
  },
  "jsep": {
    "type": "offer",
    "sdp": "..."
  }
}
```

Incoming accept:

```json
{
  "command": "message",
  "body": {
    "request": "accept"
  },
  "jsep": {
    "type": "answer",
    "sdp": "..."
  }
}
```

Decline:

```json
{
  "command": "message",
  "body": {
    "request": "decline"
  }
}
```

Hangup:

```json
{
  "command": "message",
  "body": {
    "request": "hangup"
  }
}
```

Hold:

```json
{
  "command": "message",
  "body": {
    "request": "hold"
  }
}
```

Resume:

```json
{
  "command": "message",
  "body": {
    "request": "unhold"
  }
}
```

---

# 6. Incoming WebSocket responses

Create a decoder for top-level responses.

The existing SDK recognizes:

```text
keepalive
ack
success
closed
offline
trickle
webrtcup
hangup
media
slowlink
error
event
```

Do not let unknown messages crash the call.

Unknown response:

```text
log sanitized payload type
ignore
```

unless it invalidates the current session.

---

# 7. Application-level AT events

For:

```text
response = "event"
```

inspect:

```text
eventdata.result.event
```

The current client handles:

```text
registration_failed
registered
unregistered
calling
incomingcall
progress
missed_call
accepted
hangup
decline
```

Map them to your existing Flutter media events.

Suggested mapping:

| AT | `CallMediaEvent` |
|---|---|
| `registered` | `ready` |
| `calling` | `ringing` |
| `incomingcall` | `incoming` |
| `accepted` | `connected` |
| `hangup` | `ended` |
| `decline` | `ended` |
| `offline` | `error` |
| WebSocket fatal close | `processTerminated` |
| protocol error | `error` |

Keep:

```text
progress
```

as signaling/media information.

It can contain remote JSEP and must be applied even though it does not directly change Flutter call state.

---

# 8. Build the native WebRTC session

Create:

```text
ATWebRTCSession.swift
```

Responsibilities only:

```text
RTCPeerConnectionFactory
RTCPeerConnection
local audio track
remote audio track
SDP
ICE
DTMF
mute
stats
cleanup
```

It should know nothing about Flutter.

It should know nothing about backend `/accept`.

It should know nothing about CallOffer.

---

# 9. PeerConnection creation

For every real call:

```text
create RTCPeerConnection
↓
add native audio track
↓
configure ICE servers
↓
set delegates
```

Do not create video.

Audio only.

Do not request camera permissions.

---

# 10. ICE server handling

Your `CallMediaConfig` currently supports WebRTC config and can already represent credentials returned by backend. call_models

However, inspect what the AT JavaScript client actually receives as `iceServers`.

If current backend `/media-config` does not return ICE servers, preserve the same behavior as JS.

Do not invent TURN credentials.

If 1.0.8 adds different ICE handling, document it before changing behavior.

---

# 11. Outbound WebRTC flow

Exact native sequence:

```text
initialize(config)
        ↓
connect WebSocket
        ↓
register
        ↓
wait registered
        ↓
return mediaSessionId
```

Then:

```text
dial(phone)
        ↓
ensure CallKit audio ready
        ↓
create microphone audio track
        ↓
create RTCPeerConnection
        ↓
createOffer()
        ↓
setLocalDescription()
        ↓
send request=call + JSEP offer
        ↓
send trickle candidates
        ↓
AT calling
        ↓
emit ringing
        ↓
AT progress + JSEP
        ↓
setRemoteDescription()
        ↓
AT accepted + JSEP if supplied
        ↓
setRemoteDescription if needed
        ↓
WebRTC connected
        ↓
emit connected
```

Do not emit `connected` just because AT says `accepted` if the PeerConnection/media state is not actually usable.

Prefer:

```text
AT accepted
+
RTCPeerConnection connected
```

before final media `connected`.

That prevents another silent-ACTIVE scenario.

---

# 12. Incoming flow

Your higher-level Dart flow must remain:

```text
PushKit
→ CallKit
→ /accept
→ media initialize
→ /media-ready
→ AT incoming
→ answerIncoming()
```

Do not alter that contract.

Native media:

```text
registered
        ↓
wait
        ↓
AT incomingcall
        ↓
store:
remote JSEP offer
counterpart identity
        ↓
emit incoming
```

Then Dart eventually calls:

```text
answerIncoming(callSid)
```

Native:

```text
take stored remote offer
↓
setRemoteDescription(offer)
↓
createAnswer()
↓
setLocalDescription(answer)
↓
send request=accept + JSEP answer
↓
send ICE candidates
↓
wait connected
```

Do not auto-answer merely because `incomingcall` arrives.

---

# 13. Remote JSEP handling

The JavaScript client explicitly processes JSEP received with:

```text
progress
accepted
incomingcall
```

depending on direction.

Native implementation must support:

```text
offer
answer
```

and must tolerate duplicate/final JSEP when already set.

Do not blindly call:

```text
setRemoteDescription
```

twice.

Track signaling state.

---

# 14. Trickle ICE

This is important.

The JS client uses:

```json
{
  "command": "trickle",
  "candidate": ...
}
```

Native outgoing candidates should be serialized as AT expects.

Incoming:

```text
response = trickle
candidate = ...
```

If remote description exists:

```text
addIceCandidate immediately
```

otherwise:

```text
queue candidate
```

Then after `setRemoteDescription`:

```text
drain queued candidates
```

The JS SDK explicitly does this.

Also support end-of-candidates.

The JS client recognizes:

```text
candidate.completed == true
```

as a completed/end candidate signal.

---

# 15. DTMF

Do not send DTMF as arbitrary WebSocket messages.

The current JS SDK uses the WebRTC sender's DTMF functionality.

Implement using native WebRTC's DTMF sender attached to the audio sender.

Expose through:

```dart
sendDtmf(String digit)
```

same as today.

---

# 16. Mute

The JS implementation mutes by toggling:

```text
local audio track enabled
```

Your native version should mirror that.

Conceptually:

```swift
localAudioTrack.isEnabled = !muted
```

Do not deactivate AVAudioSession to mute.

Do not stop the track.

Do not renegotiate SDP.

---

# 17. Hold

Initially preserve the AT signaling semantics:

```text
request=hold
request=unhold
```

Do not assume hold means just disabling audio.

Observe whether AT sends any corresponding JSEP/connection change.

For the PoC:

```text
Flutter hold
→ AT hold request
```

Then implement media behavior only after verified against AT.

Your current CallKit `CXSetHeldCallAction` behavior can be revisited later.

Hold is not required to prove native two-way audio.

---

# 18. CallKit audio synchronization

This is critical.

Do not repeat the current timing ambiguity.

Native WebRTC must know whether CallKit has activated the call audio session.

Add process-wide native state:

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
mark audio active
configure voice-call audio
notify native media engine
```

When:

```swift
provider(_:didDeactivate:)
```

fires:

```text
mark inactive
notify media engine
```

Your current CallKit configuration is already essentially:

```text
.playAndRecord
.voiceChat
.allowBluetooth
```

and does not call `setActive()` itself. AppDelegate

Preserve that authority model:

```text
CallKit owns activation
native WebRTC consumes the activated session
```

Do not let Flutter or WebRTC independently fight CallKit with arbitrary:

```swift
setActive(true)
setActive(false)
```

---

# 19. Native WebRTC audio-session integration

This deserves its own implementation gate.

Native WebRTC has its own audio-session abstraction.

Codex must inspect the exact APIs of the pinned WebRTC framework being used and configure its audio device to cooperate with the CallKit-owned `AVAudioSession`.

Requirements:

```text
receiver default
speaker override supported
Bluetooth HFP
wired headset
interruptions
route changes
CallKit activation/deactivation
```

No hardcoded speaker default.

Existing:

```dart
setSystemSpeaker(bool enabled)
```

should remain the public Flutter API.

CallKit/native layer owns actual routing.

---

# 20. WebRTC dependency strategy

For the prototype:

Do **not** use the old deprecated `GoogleWebRTC` CocoaPod. The published pod is old/deprecated. [CocoaPods](https://www.cocoapods.org/pods/GoogleWebRTC?utm_source=chatgpt.com)

Preferred production route:

```text
pin an exact upstream WebRTC revision
build WebRTC.framework/XCFramework
record revision
record build flags
record SHA-256
include licenses
```

Official upstream instructions still describe building the iOS framework directly. [WebRTC](https://webrtc.googlesource.com/src/%2Bshow/refs/heads/main/docs/native-code/ios/README.md?utm_source=chatgpt.com)

For the first PoC, Codex may use a recent reproducible prebuilt WebRTC XCFramework **only if**:

```text
source revision known
license available
checksum pinned
arm64 device supported
simulator supported if needed
```

Do not let Codex pull:

```text
latest
main
floating version
```

into production.

---

# 21. Swift file structure

I would use:

```text
ios/Runner/Calling/Media/
│
├── ATNativeMediaCoordinator.swift
├── ATSignalingClient.swift
├── ATSignalingModels.swift
├── ATWebRTCSession.swift
├── ATWebRTCStats.swift
├── ATNativeMediaChannel.swift
├── ATNativeMediaError.swift
└── ATNativeMediaLogger.swift
```

### `ATSignalingClient`

Owns only:

```text
WebSocket
auth subprotocol
keepalive
JSON encoding/decoding
reconnect/close
AT messages
```

### `ATWebRTCSession`

Owns only:

```text
PeerConnection
SDP
ICE
tracks
DTMF
stats
```

### `ATNativeMediaCoordinator`

Owns state machine:

```text
idle
connecting
registered
incoming
dialing
connectingMedia
connected
ending
failed
```

Coordinates signaling + PeerConnection.

### `ATNativeMediaChannel`

Flutter MethodChannel bridge.

### `ATNativeMediaLogger`

Strict redaction.

---

# 22. Flutter implementation

Create:

```text
lib/services/calls/ios_native_call_media_service.dart
```

Implement existing interface exactly:

```dart
class IOSNativeCallMediaService implements CallMediaService {
  Stream<CallMediaEvent> get events;

  Future<String> initialize(...);
  Future<String> dial(...);
  Future<void> answerIncoming(...);
  Future<void> endMedia(...);
  Future<void> setMuted(...);
  Future<void> setHeld(...);
  Future<void> sendDtmf(...);
  Future<void> dispose();
}
```

Do not change `CallMediaService` merely to accommodate Swift unless absolutely necessary.

The point of this project is to prove the existing abstraction works.

---

# 23. Native media channel protocol

Flutter → Swift:

```text
initialize
dial
answerIncoming
end
mute
hold
dtmf
getStats
dispose
```

Example initialize arguments:

```json
{
  "token": "...",
  "gatewayUrl": "...",
  "clientName": "...",
  "mediaSessionId": "..."
}
```

Do not pass backend bearer Authorization tokens.

Only AT capability token.

Native → Flutter events:

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
diagnostic
```

Match your existing `CallMediaEvent` semantics. call_media_service

---

# 24. Correlation

Native client should track:

```text
mediaSessionId
callSid
direction
```

Do not use AT session IDs as your backend `call_id`.

Keep canonical identifiers separated exactly as current architecture intends.

---

# 25. State machine rules

Native implementation must enforce:

```text
one AT registration/client
one active PeerConnection
one active call
```

No simultaneous calls in PoC.

Reject:

```text
dial while call active
answer without incoming offer
duplicate initialize
duplicate answer
```

with deterministic errors.

---

# 26. Connection lifecycle

`initialize()`:

```text
IDLE
→ CONNECTING_SOCKET
→ REGISTERING
→ READY
```

Failure anywhere:

```text
→ FAILED
→ close socket
→ dispose peer connection
→ release media resources
```

---

# 27. Do not implement automatic reconnect during an active call initially

Reconnect is dangerous while proving protocol correctness.

Phase 1 behavior:

```text
WebSocket closes during active call
→ emit processTerminated/error
→ terminate call
```

Later:

```text
idle registration reconnect
```

can be added.

---

# 28. Logging

Every phase needs timing.

Example:

```text
[ATNativeMedia]
socket_connect_start
socket_open
register_sent
registered
audio_session_active
peer_connection_created
microphone_track_created
offer_created
local_description_set
call_sent
first_local_candidate
calling
remote_jsep_received
remote_description_set
ice_checking
ice_connected
peer_connected
first_inbound_rtp
first_outbound_rtp
```

Never log:

```text
capability token
Authorization
full SDP
ICE credentials
full phone number
```

For debugging SDP:

```text
type
length
m-line count
codec names
```

only.

---

# 29. Native stats watchdog

This is one of the biggest benefits of moving native.

Every 2–5 seconds during a connected call, collect stats:

```text
outbound audio bytesSent
outbound packetsSent
inbound audio bytesReceived
inbound packetsReceived
audio level if available
ICE state
connection state
selected candidate pair
round-trip time
```

Do not send all stats to backend.

Log/debug locally.

Use them to enforce:

```text
connected UI should not remain indefinitely against dead media
```

---

# 30. Mic acceptance signal

Define native mic readiness based on evidence.

Not merely:

```text
track exists
```

Prefer:

```text
local audio track created
+
outbound RTP starts increasing
```

You already learned why.

The WebView gave you:

```text
track live
track enabled
track muted
bytesSent = 0
```

Native implementation must make this observable.

---

# 31. First proof-of-concept milestone

Do not integrate the full app first.

Build an isolated native test path.

Phase A:

```text
button / debug command
→ obtain media-config from existing backend
→ native initialize
→ connect WebSocket
→ register
```

Success:

```text
AT registered event received
```

Nothing else.

This is Gate 1.

---

# 32. Gate 2 — outbound signaling only

Without microphone initially if possible:

```text
create peer connection
create offer
send call
```

Verify:

```text
calling
progress
remote JSEP
accepted
```

If signaling diverges from JavaScript behavior, stop here and fix protocol.

---

# 33. Gate 3 — microphone + outbound RTP

Enable native audio track.

Success:

```text
microphone created
CallKit audio active
bytesSent > 0
```

This is the first key result.

If:

```text
native bytesSent > 0
```

while WebView produced:

```text
0
```

you've validated the architectural hypothesis.

---

# 34. Gate 4 — inbound audio

Success:

```text
bytesReceived > 0
audible through receiver
```

Test:

```text
receiver
speaker
wired headset if available
Bluetooth
```

Speaker can be later if Bluetooth unavailable initially.

---

# 35. Gate 5 — full outbound call

Acceptance:

```text
PSTN hears agent
agent hears PSTN
hangup works both directions
```

Minimum 10 calls.

No:

```text
silent audio
stuck connected
duplicate WebSocket registration
ghost CallKit session
```

---

# 36. Gate 6 — incoming

Only after outbound is proven.

Use real:

```text
PushKit
CallKit
backend offer
/accept
/media-config
native initialize
/media-ready
incoming AT event
native answer
```

Verify:

```text
CallKit Answer
→ active AVAudioSession
→ native WebRTC
→ two-way audio
```

---

# 37. Gate 7 — lifecycle

Test:

```text
app foreground
app background
screen locked
app suspended
cold start
incoming PushKit launch
Bluetooth connect/disconnect
speaker toggle
interruption
network switch Wi-Fi → mobile
caller hangs up
agent hangs up
```

Do not call it production-ready before these.

---

# 38. Error mapping

Native errors should become structured reasons.

Examples:

```text
socket_connect_failed
registration_failed
token_expired
peer_connection_failed
microphone_unavailable
sdp_offer_failed
sdp_answer_failed
remote_sdp_failed
ice_failed
provider_hangup
provider_declined
protocol_error
```

Flutter receives:

```text
CallMediaEvent.error
```

with a safe user-facing reason and internal diagnostic code.

---

# 39. Cleanup

One terminal path should own teardown.

```text
cancel keepalive
close WebSocket
stop audio track
remove senders
close PeerConnection
clear pending JSEP
clear candidates
release call state
```

Do not destroy the CallKit provider.

That belongs to the OS-call layer.

---

---

# 41. Do not delete WebView implementation yet

Keep:

```text
WebViewCallMediaService
```

for:

```text
Android
fallback development comparison
A/B diagnostics
```

The iOS-native implementation should initially be feature flagged.

Only retire iOS WebView after native acceptance.

---

# 42. Compare 1.0.7 vs 1.0.8

Before final protocol freeze, Codex should obtain 1.0.8 and generate a semantic protocol diff.

Focus only on:

```text
WebSocket URL
subprotocol auth
command envelope
registration
call
accept
decline
hangup
trickle ICE
JSEP
hold
DTMF
keepalive
event names
error behavior
```

Ignore:

```text
bundling
transpiler output
browser shims
formatting
```

Current npm shows 1.0.8 is active and was recently published. [npm](https://www.npmjs.com/package/africastalking-client?activeTab=readme\&utm_source=chatgpt.com)

If the wire protocol is unchanged:

```text
implement against current protocol
```

If changed:

```text
document version difference
```

Do not silently mix 1.0.7 and 1.0.8 semantics.

---

# 43. Test against both SDKs

During development, capture sanitized protocol traces from:

```text
existing JS 1.0.7
native Swift client
```

for the same operations.

Compare:

```text
register
outbound call
incoming answer
hangup
hold
DTMF
```

The native client should generate equivalent semantic messages.

Not byte-for-byte SDP.

WebRTC-generated SDP will naturally differ.

---

# 44. Unit tests

Swift tests should cover:

```text
JSON outgoing message encoding
incoming response decoding
registration event mapping
incomingcall parsing
progress JSEP parsing
accepted JSEP parsing
hangup reason parsing
trickle candidate queue
end-of-candidates
duplicate remote description handling
state transition guards
keepalive scheduling
token never appears in logs
```

No live AT server required.

---

# 45. Integration tests

Create a mock WebSocket signaling server if practical.

Simulate:

```text
registered
calling
progress
accepted
incomingcall
trickle
hangup
offline
malformed response
unexpected close
```

That lets you test state machine correctness without paying for PSTN calls.

---

# 46. Physical-device acceptance tests

Simulator is insufficient for final audio validation.

Use the actual iPhone.

Record for each call:

```text
call direction
socket registration ms
offer/answer ms
ICE connected ms
CallKit activation ms
bytesSent
bytesReceived
route
hangup reason
```

Minimum:

```text
10 outbound
10 inbound
```

before switching default implementation.

---

# 47. Rollout

Stage 1:

```text
debug flag only
```

Stage 2:

```text
internal TestFlight users
```

Stage 3:

```text
iOS native default
WebView retained behind emergency flag
```

Stage 4:

```text
remove iOS WebView-specific workarounds
```

Keep Android WebView.

---

# 48. Definition of success

The experiment succeeds if native iOS repeatedly produces:

```text
CallKit active

native microphone:
  valid audio track

WebRTC:
  ICE connected
  peer connected

RTP:
  outbound bytes increasing
  inbound bytes increasing

human test:
  iPhone hears PSTN
  PSTN hears iPhone
```

and does so across multiple calls.

The most important comparison is:

```text
CURRENT WKWebView
trackEnabled=true
trackMuted=true
outboundBytes=0

NATIVE
outboundBytes increasing
```

If native does that, you've proven the WebKit path was the problem.

---

# Codex prompt

I would give Codex this almost verbatim:

> We are going to build an experimental iOS-native Africa’s Talking WebRTC client for OmniDesk and integrate it behind the existing `CallMediaService` abstraction.
>
> This is an iOS-only media experiment. Do not change Android, backend call lifecycle APIs, Flutter call UI, PushKit or CallKit architecture.
>
> Current production:
> - Android and iOS media use `WebViewCallMediaService`.
> - Android WebView is proven working.
> - iOS WKWebView establishes signaling/ICE but has produced `trackEnabled=true`, `trackMuted=true`, `outboundAudioBytes=0` and unreliable playback.
> - `NativeCallService` is strictly the OS call-surface abstraction and must remain free of WebRTC/RTP.
>
> We have inspected the exact `africastalking-client-1.0.7.min.js` bundle.
>
> Protocol baseline:
> - WebSocket: `wss://webrtc.africastalking.com/connect`
> - subprotocols: `at-protocol`, capability token
> - normal requests:
>   - `{"command":"message","body":{"request":"register"}}`
>   - call: request `call`, `to`, plus local JSEP offer
>   - accept: request `accept`, plus local JSEP answer
>   - `decline`
>   - `hangup`
>   - `hold`
>   - `unhold`
> - ICE trickle:
>   - `{"command":"trickle","candidate":...}`
> - keepalive:
>   - `{"command":"keepalive"}`
>   - approximately every 30 seconds
> - clean destroy:
>   - `{"command":"destroy"}`
> - server response types include:
>   - `keepalive`
>   - `ack`
>   - `success`
>   - `closed`
>   - `offline`
>   - `trickle`
>   - `webrtcup`
>   - `hangup`
>   - `media`
>   - `slowlink`
>   - `error`
>   - `event`
> - AT application events under `eventdata.result.event` include:
>   - `registration_failed`
>   - `registered`
>   - `unregistered`
>   - `calling`
>   - `incomingcall`
>   - `progress`
>   - `missed_call`
>   - `accepted`
>   - `hangup`
>   - `decline`
> - the JS implementation queues remote ICE candidates received before remote SDP and drains them after `setRemoteDescription`.
> - mute toggles the local WebRTC audio track.
> - DTMF uses the WebRTC audio sender.
>
> First inspect all existing call-related files before modifying anything:
> - `CallMediaService`
> - `call_media_provider.dart`
> - `WebViewCallMediaService`
> - `CallSessionController`
> - `NativeCallService`
> - `AppDelegate.swift`
> - `Info.plist`
> - uploaded AT JS 1.0.7 bundle
> - uploaded OmniDesk JS bridge
>
> Also obtain and inspect `africastalking-client` 1.0.8 and produce a protocol-only diff against 1.0.7 before freezing the native implementation.
>
> Build:
>
> `ios/Runner/Calling/Media/`
> - `ATNativeMediaCoordinator.swift`
> - `ATSignalingClient.swift`
> - `ATSignalingModels.swift`
> - `ATWebRTCSession.swift`
> - `ATWebRTCStats.swift`
> - `ATNativeMediaChannel.swift`
> - `ATNativeMediaError.swift`
> - `ATNativeMediaLogger.swift`
>
> Flutter:
> - add `ios_native_call_media_service.dart`
> - implement the existing `CallMediaService` contract exactly
> - introduce a platform/feature-flag provider:
>   - Android → existing WebView implementation
>   - iOS native feature enabled → native implementation
>   - otherwise iOS → existing WebView implementation for comparison
>
> Use a dedicated MethodChannel such as `africa.omnidesk/media`. Do not add media responsibilities to `africa.omnidesk/calls`.
>
> Native WebRTC requirements:
> - audio only
> - RTCPeerConnection
> - microphone track
> - remote audio
> - offer/answer
> - trickle ICE
> - DTMF
> - mute
> - native RTP stats
> - deterministic teardown
>
> CallKit rules:
> - CallKit remains the sole AVAudioSession activation authority.
> - Native WebRTC must synchronize with `provider(_:didActivate:)`.
> - Do not introduce competing `setActive(true/false)` calls.
> - preserve receiver default, explicit speaker, Bluetooth HFP and route changes.
>
> Ensure only the selected native media implementation can own call audio.
>
> Do not use the deprecated `GoogleWebRTC` CocoaPod. For production, prefer a reproducibly pinned WebRTC framework built from a specific official upstream WebRTC revision. For the POC, a recent prebuilt XCFramework is acceptable only if its upstream revision, license and checksum are pinned.
>
> Implementation gates:
>
> 1. WebSocket connect + AT register only.
>    - Must receive `registered`.
>
> 2. Outbound signaling.
>    - create offer
>    - send `call`
>    - receive `calling/progress/accepted`
>    - apply remote JSEP.
>
> 3. Native mic.
>    - CallKit audio active
>    - local track created
>    - outbound RTP bytes must increase.
>
> 4. Remote audio.
>    - inbound RTP bytes increase
>    - audio is physically audible.
>
> 5. Full outbound PSTN call.
>    - two-way human-audible audio.
>
> 6. Incoming call.
>    - preserve existing PushKit → CallKit → `/accept` → `/media-ready` → AT incoming → native answer flow.
>
> 7. Lifecycle tests.
>    - foreground/background
>    - lock screen
>    - cold PushKit launch
>    - speaker/receiver
>    - Bluetooth
>    - interruptions
>    - network transitions
>    - hangup both sides.
>
> Add sanitized phase/timing logs and native WebRTC stats. Never log capability tokens, backend Authorization, full SDP, ICE credentials or full phone numbers.
>
> Do not mark media `connected` merely because AT sends `accepted`; require usable WebRTC connection state as well.
>
> Do not implement automatic active-call reconnect or cross-engine fallback in the first POC.
>
> Before coding, return:
> 1. your verified 1.0.7 → 1.0.8 protocol diff;
> 2. the exact WebRTC dependency/revision strategy;
> 3. the exact files you will add/change;
> 4. any protocol behavior from the JS client that is still unclear;
> 5. a staged implementation plan matching the gates above.
>
> Only start implementation after that review.

I would proceed with exactly this experiment. It is much more valuable now than another round of WKWebView audio tweaks, because if Gate 3 gives you **real increasing outbound RTP from the iPhone microphone**, you've answered the architecture question very quickly.
