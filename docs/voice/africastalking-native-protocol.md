# Africa's Talking native WebRTC protocol

Status: Gate 1 baseline, with Gate 2 implementation details appended

Sources:

- `assets/js/africastalking-client-1.0.7.min.js` (bundled production asset)
- `africastalking-client@1.0.8` package (`build/africastalking.js`), downloaded from npm on 2026-10-01
- package `CHANGELOG`

## 1.0.7 → 1.0.8 result

No signaling contract change was identified. Both versions use:

- `wss://webrtc.africastalking.com/connect`
- WebSocket subprotocols `at-protocol` and the capability token
- JSON command envelopes with `command` and either `body`/`jsep` or `candidate`
- `message` requests for registration and call control
- `trickle` for ICE candidates
- `keepalive` approximately every 30 seconds
- AT application events delivered in `eventdata.result.event`

The published 1.0.8 changelog reports dependency pinning, README updates for
mute/unmute, and a public `destroy()` cleanup method. Version 1.0.7 reports
STUN/TURN parameter support and WebSocket cleanup on unload. The native client
must still use the actual negotiated ICE configuration; it must not invent a
fallback STUN/TURN server.

## Authentication and connection

The browser client creates the WebSocket with:

```text
new WebSocket(server, ["at-protocol", capabilityToken])
```

The capability token is supplied by the backend media configuration. The AT
API key is never sent to or stored in the mobile client.

The native implementation must preserve TLS validation and must not log the
token, authorization headers, SDP, or ICE credentials.

## Outgoing frames

Registration:

```json
{"command":"message","body":{"request":"register"}}
```

Call setup uses a local SDP offer:

```json
{
  "command": "message",
  "body": {"request": "call", "to": "+254..."},
  "jsep": {"type": "offer", "sdp": "..."}
}
```

Incoming acceptance uses a local SDP answer:

```json
{
  "command": "message",
  "body": {"request": "accept"},
  "jsep": {"type": "answer", "sdp": "..."}
}
```

The following requests are present in the SDK:

```text
register, unregister, call, accept, decline, hangup, hold, unhold
```

ICE trickle:

```json
{"command":"trickle","candidate":{}}
```

Keepalive:

```json
{"command":"keepalive"}
```

Clean client teardown in 1.0.8 uses:

```json
{"command":"destroy"}
```

The native POC must make teardown idempotent and must not send active-call
reconnect traffic in its first implementation.

## Incoming frames and events

The SDK recognizes these top-level response values:

```text
keepalive, ack, success, closed, offline, trickle, webrtcup,
hangup, media, slowlink, error, event
```

Application events are read from:

```text
eventdata.result.event
```

Observed event names:

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

`progress` may carry remote JSEP and must be processed even when it does not
change the Flutter presentation state. Remote ICE candidates may arrive before
remote SDP; the native client must buffer them and drain the buffer after
`setRemoteDescription` succeeds.

## Native state rules

`registered` is sufficient for the registration gate only. A media call is
connected only when the AT call has been accepted and the native WebRTC
connection is usable. AT's `accepted` event alone is not a valid media-ready
signal.

All local and remote terminal paths converge on one idempotent cleanup path.
Unknown top-level responses and unknown application events are logged as
sanitized types and ignored; they must not crash the signaling loop.

## ICE-server provenance (Gate 1 question resolved)

Both the bundled 1.0.7 client and npm `africastalking-client` 1.0.8 read ICE
servers exclusively from the optional client constructor property
`options.iceServers`. The OmniDesk bridge instantiates the client as
`new Client(token, { sounds: {} })`; it supplies no ICE servers. The SDK's
default is an empty array. There is no ICE-server request in the signaling
protocol and no STUN/TURN fallback in the SDK or the OmniDesk call
configuration path. Consequently the native peer uses `iceServers = []` and
does not invent public infrastructure. If AT or OmniDesk later provisions
servers, that requires a separately specified, authenticated configuration
contract.

Accepted constructor shapes in the SDK are a STUN `urls` string, a TURN/TURNS
`urls` string plus `username` and `credential`, or an array consisting only of
TURN/TURNS URLs plus those credentials. Mixed/STUN arrays and unrelated
shapes are rejected. The helper normalizes these to WebRTC `RTCIceServer`
objects; it does not fetch them from the gateway.

## WebSocket negotiation validation

The native request uses `URLSessionWebSocketTask(with:protocols:)` with exactly
`["at-protocol", capabilityToken]`; URLSession sends these as
`Sec-WebSocket-Protocol` values. The delegate records only an allowlisted
selected protocol (`at-protocol` or `other_or_none`) and result; it never
logs, returns, or places the token in error details. On open it sends Janus
`{"command":"create"}`, waits for top-level `response: "success"`, then sends
the SDK's `message/register` request. Registration success is reported only
after AT's `eventdata.result.event == "registered"`.

Source inspection validates the request encoding and lifecycle. A real AT
gateway acceptance is **not yet evidenced**: it requires a fresh capability
token and a live authenticated app session. The implementation emits a
sanitized `diagnostic` event containing the selected-protocol allowlist value
and gateway result so an on-device run can capture the actual result without
revealing credentials. Do not treat this source/build validation as a live
gateway pass.

## WebRTC dependency pin and compatibility review

Selected distribution: [`stasel/WebRTC`](https://github.com/stasel/WebRTC),
Swift Package product `WebRTC`, exact release `153.0.0`; package repository
revision `4266157cd08f92115de885ab12d87196a8db87e1`. The binary is built from
Google's upstream WebRTC source repository
[`webrtc.googlesource.com/src`](https://webrtc.googlesource.com/src), branch
`branch-heads/8010`, exact source revision
`9ea5afcad008b940468c2a15aec339592cf5a935`. The release XCFramework archive
SHA-256 is
`3e3a8946f27510133e3feed04d05fa23505bbe366e977620503bfc7986c2b78f`.
License: BSD-3-Clause (WebRTC source license). The XCFramework provides
iOS-device arm64 and iOS-simulator arm64/x86_64 slices (also Catalyst/macOS
slices); minimum iOS is 12.0, while this app targets iOS 15.0. Integrated via
Swift Package Manager in `ios/Runner.xcodeproj/project.pbxproj`, with the
resolved package commit in `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

The 1.0.7 bundle and 1.0.8 build were inspected for SDP rewriting, codec
filtering/preferences, BUNDLE/RTCP mux, SDP semantics, candidate serialization,
DTLS/SRTP and browser-only branches. Neither version munges SDP or selects a
codec; it applies the browser-generated SDP unchanged. It serializes trickle
candidates as `candidate`, `sdpMid`, and `sdpMLineIndex`, and sends
`{"completed":true}` at gathering completion. Peer connection configuration
uses balanced BUNDLE and the browser's required RTCP mux behavior; no custom
DTLS/SRTP parameters are negotiated (standard WebRTC DTLS-SRTP). Modern
browsers use Unified Plan; the bundled adapter only accommodates legacy
browser engines, notably older Plan B implementations. Native explicitly uses
Unified Plan, balanced BUNDLE, required RTCP mux, and default DTLS-SRTP, with
the unmodified SDP. SDK browser-specific behavior is limited to adapter
compatibility and an Edge bundle-policy branch; neither is part of the AT wire
protocol.

The upstream revision is pinned rather than floating. Keep package cache
integrity and the resolved commit under review whenever updating the release;
the XCFramework binary is vendor-produced and is not rebuilt from source as
part of the app build.

## Gate 2 native outbound scope and operational limit

The native path creates an audio-only Unified Plan peer connection, adds one
local audio track, emits an unmodified offer after applying it as local SDP,
trickles ICE in the SDK's exact field shape, buffers remote candidates until
remote SDP is set, and requires both AT acceptance and WebRTC's combined
connection state before emitting `connected`. CallKit owns audio activation;
WebRTC manual-audio mode is enabled only when CallKit activates the shared
session. Local hangup closes the peer but retains the registered signaling
transport; disposal sends `destroy`.

With the verified empty ICE-server configuration, the peer has no TURN relay
or server-reflexive STUN candidates. Host-candidate connectivity is therefore
network-dependent and can fail behind restrictive NATs, carrier networks, or
firewalls. This is a deliberate fidelity choice, not a production-grade
connectivity guarantee. Do not enable the build-time iOS-native flag for
general deployment until a live AT handshake and physical-device two-way
audio/candidate-path validation pass. Incoming native answering, DTMF, and
hold are outside this outbound Gate 2 slice; the WebView implementation stays
available and remains the default.
