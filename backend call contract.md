
# OmniDesk Android Calling — Backend Contract

## Goal

Implement the backend support required for native Android incoming and outgoing VoIP calls while keeping the existing Africa’s Talking WebRTC media path.

Android architecture will be:

```text
Africa’s Talking inbound call
        ↓
OmniDesk backend
        ↓
select eligible agent/device
        ↓
HIGH priority FCM DATA push
        ↓
Android native Telecom / ConnectionService
        ↓
user answers
        ↓
OmniDesk /accept
        ↓
mobile starts AT WebRTC media
        ↓
/media-ready
        ↓
call becomes active
```

The backend must not depend on Flutter being alive.

FCM high-priority messages are appropriate for time-sensitive voice-call alerts and can wake a sleeping Android device for limited processing. Use data messages so the app controls the native incoming-call behavior itself. ([Firebase][1])

---

# 1. Canonical IDs

Do not use Africa’s Talking IDs as the primary IDs in mobile.

Every inbound call should have:

```text
call_id
offer_id
provider_call_id
```

Semantics:

```text
call_id
    stable OmniDesk call ID
    remains the same for entire call lifecycle

offer_id
    identifies one offer of that call to one agent/device attempt
    changes when rerouting/reoffering

provider_call_id
    Africa’s Talking provider/session ID
    secondary reference only
```

Example:

```json
{
  "call_id": "call_01K5ABCDXYZ",
  "offer_id": "offer_01K5ABCDABC",
  "provider_call_id": "AT-7f8c..."
}
```

This is important for:

```text
deduplication
multi-device handling
answered-elsewhere
rerouting
stale push rejection
idempotent accept
call recovery
```

---

# 2. Recommended database structures

I would not try to store everything in the existing `call_logs` table alone.

Use at least three logical records.

## `call_logs`

The authoritative call record:

```text
id / call_id
workspace_id
direction
provider
provider_call_id
from_number
to_number
customer_id
ticket_id

status
ringing_at
answered_at
connected_at
ended_at

duration_seconds

assigned_agent_id
answered_agent_id

recording_url
recording_provider_id
cost
currency

failure_code
failure_reason

created_at
updated_at
```

Recommended statuses:

```text
initiated
offering
ringing
accepted
connecting
active
completed

declined
missed
cancelled
failed
expired
answered_elsewhere
```

Avoid collapsing everything into only:

```text
ringing
completed
failed
```

because mobile lifecycle needs more precision.

---

## `call_offers`

This should represent every delivery/routing attempt.

```text
id / offer_id
call_id
workspace_id
agent_id

status

offered_at
expires_at
delivered_at
native_presented_at
accepted_at
declined_at
cancelled_at

accepted_installation_id
decline_reason

created_at
updated_at
```

Recommended offer statuses:

```text
pending
sent
delivered
accepted
declined
expired
cancelled
answered_elsewhere
failed
```

A `call_id` may have multiple `offer_id`s over time.

Example:

```text
call_123
 ├─ offer_A → agent 12 → declined
 ├─ offer_B → agent 27 → expired
 └─ offer_C → agent 31 → accepted
```

---

## `agent_devices`

You already have the concept; harden it.

Suggested fields:

```text
id
installation_id
user_id
workspace_id

platform
device_name
app_version

fcm_token
apns_token
voip_push_token

voip_capable
notifications_enabled
last_seen_at
last_registered_at

revoked_at
created_at
updated_at
```

Important constraints:

```text
installation_id UNIQUE
fcm_token UNIQUE where practical
```

A token must never silently move between users without ownership validation.

The mobile app already models installation-specific registration, including FCM/APNs/VoIP tokens. 

---

# 3. Device registration endpoint

Keep:

```http
POST /api/v1/agent/devices
```

Request:

```json
{
  "installation_id": "4fb0a50d-dbf5-4e54-87a9-d9cf863e509a",
  "platform": "android",
  "app_version": "1.2.0+45",
  "device_name": "Samsung SM-A065F",
  "voip_capable": true,
  "fcm_token": "..."
}
```

Response:

```json
{
  "success": true,
  "device": {
    "installation_id": "4fb0...",
    "registered": true,
    "voip_capable": true
  }
}
```

Also keep:

```http
DELETE /api/v1/agent/devices/{installation_id}
```

for logout/unregister.

The backend should:

```text
authenticate user
validate active workspace
upsert only devices owned by that user
replace stale token on refresh
revoke token on logout
remove NotRegistered/invalid FCM tokens automatically
```

FCM registration tokens represent individual app instances and should be treated as device-specific routing addresses. ([Firebase][2])

---

# 4. Agent availability

Calling eligibility should not be inferred only from login.

Have explicit agent call availability:

```json
{
  "status": "available",
  "receive_calls": true
}
```

Backend selection should require something like:

```text
agent active
AND workspace valid
AND receive_calls = true
AND agent not already on another call
AND at least one routable Android/iOS device exists
```

Do not use only `last_heartbeat`.

A mobile device can receive FCM while Flutter itself is not running.

---

# 5. Incoming call routing

When Africa’s Talking sends the inbound webhook:

```text
incoming PSTN
↓
AT webhook
↓
OmniDesk
```

backend should:

1. Create or resolve canonical `call_id`.
2. Save caller/customer/ticket context.
3. Select eligible agent.
4. Create `offer_id`.
5. Set short `expires_at`.
6. Send high-priority FCM data push.
7. Record the provider message ID / delivery attempt.
8. Wait for accept/decline/expiry.
9. Reroute if necessary.

Do this transactionally where possible.

---

# 6. Incoming FCM payload

I recommend this exact logical payload.

```json
{
  "type": "incoming_call",
  "schema_version": "1",

  "call_id": "call_01K5ABCDXYZ",
  "offer_id": "offer_01K5ABCDABC",

  "workspace_id": "1",

  "provider": "africas_talking",
  "provider_call_id": "AT-call-abc123",

  "caller_number": "+254743379990",
  "caller_name": "John Kamau",

  "customer_id": "customer_392",
  "ticket_id": "ticket_541",
  "ticket_number": "TKT-541",

  "category": "support",

  "timestamp": "2026-09-19T15:25:40Z",
  "expires_at": "2026-09-19T15:26:10Z"
}
```

All values inside FCM `data` should be strings.

Actual FCM HTTP v1 message:

```json
{
  "message": {
    "token": "<DEVICE_FCM_TOKEN>",
    "data": {
      "type": "incoming_call",
      "schema_version": "1",
      "call_id": "call_01K5ABCDXYZ",
      "offer_id": "offer_01K5ABCDABC",
      "workspace_id": "1",
      "provider": "africas_talking",
      "provider_call_id": "AT-call-abc123",
      "caller_number": "+254743379990",
      "caller_name": "John Kamau",
      "customer_id": "customer_392",
      "ticket_id": "ticket_541",
      "ticket_number": "TKT-541",
      "category": "support",
      "timestamp": "2026-09-19T15:25:40Z",
      "expires_at": "2026-09-19T15:26:10Z"
    },
    "android": {
      "priority": "HIGH",
      "ttl": "30s"
    }
  }
}
```

Use **data-only**, not:

```json
"notification": {
  ...
}
```

because background notification messages may be rendered by FCM itself instead of going directly through your native call handler. Data messages are handled by application code. ([Firebase][3])

Also keep payloads small. FCM data/notification payloads are capped at 4096 bytes. ([Firebase][3])

---

# 7. FCM TTL

For calls, do not accept the default FCM lifetime.

The default can be very long, which is unacceptable for incoming-call ringing.

Firebase explicitly calls out incoming-call notifications as a use case where a short lifespan matters. ([Firebase][4])

If your offer lasts 30 seconds:

```json
"ttl": "30s"
```

or perhaps:

```text
offer expiry = 35 sec
FCM TTL      = 30 sec
```

Never let an incoming call notification arrive five minutes later.

The app must still independently reject any payload where:

```text
now >= expires_at
```

because TTL is transport behavior, not your business truth.

---

# 8. Do not use one global collapse key

Be careful with `collapse_key`.

If several pending messages share a collapse key, FCM can discard older pending messages and retain only the newest one. ([Firebase][4])

For incoming calls I would either:

```text
omit collapse_key
```

or if you deliberately use one:

```text
collapse_key = call:{call_id}
```

Never use:

```text
collapse_key = incoming_call
```

for all calls.

Otherwise an unrelated new call could replace an older pending call message.

---

# 9. Delivery acknowledgment endpoint

Keep:

```http
POST /api/v1/calls/{call_id}/delivery-ack
```

But extend it slightly.

Request:

```json
{
  "offer_id": "offer_01K5ABCDABC",
  "installation_id": "4fb0...",
  "received_at": "2026-09-19T15:25:41.184Z",
  "native_presented_at": "2026-09-19T15:25:41.390Z"
}
```

Response:

```json
{
  "success": true
}
```

This should be telemetry only.

It should **not claim the call**.

Meaning:

```text
delivery-ack != accept
```

This will later let you measure:

```text
backend push sent
→ FCM received
→ native UI displayed
→ user answered
→ WebRTC connected
```

That will be invaluable in production.

---

# 10. Atomic accept endpoint

This one is critical.

```http
POST /api/v1/calls/{call_id}/accept
```

Request:

```json
{
  "offer_id": "offer_01K5ABCDABC",
  "installation_id": "4fb0..."
}
```

The backend must atomically verify:

```text
call exists
offer exists
offer belongs to this call
offer belongs to authenticated agent
workspace matches
offer not expired
call not already accepted
device belongs to agent
agent still eligible
```

Then atomically transition:

```text
offer:
pending/sent/delivered → accepted

call:
offering/ringing → accepted

call.answered_agent_id = authenticated user
offer.accepted_installation_id = device
```

Only one device/agent should win.

Use DB transaction / compare-and-set semantics.

Response:

```json
{
  "success": true,
  "call": {
    "call_id": "call_01K5ABCDXYZ",
    "offer_id": "offer_01K5ABCDABC",
    "status": "accepted",
    "direction": "inbound",
    "caller_number": "+254743379990",
    "caller_name": "John Kamau",
    "customer_id": "customer_392",
    "ticket_id": "ticket_541",
    "provider": "africas_talking",
    "provider_call_id": "AT-call-abc123",
    "accepted_at": "2026-09-19T15:25:44Z"
  }
}
```

If another device wins:

```http
409 Conflict
```

```json
{
  "success": false,
  "code": "CALL_ALREADY_CLAIMED",
  "message": "This call has already been answered."
}
```

If expired:

```http
410 Gone
```

```json
{
  "success": false,
  "code": "CALL_OFFER_EXPIRED"
}
```

Your app already has explicit error handling for `CALL_ALREADY_CLAIMED` and `CALL_OFFER_EXPIRED`, so preserve those codes. 

---

# 11. Decline endpoint

```http
POST /api/v1/calls/{call_id}/decline
```

Request:

```json
{
  "offer_id": "offer_01K5ABCDABC",
  "installation_id": "4fb0...",
  "reason": "user_declined"
}
```

Allowed reasons could be:

```text
user_declined
busy
device_unavailable
telecom_rejected
expired
```

Backend behavior:

```text
mark current offer declined
do NOT necessarily mark entire call failed
select next eligible agent
create new offer
send new FCM
```

That distinction is very important.

A declined offer is not the same thing as a declined caller.

---

# 12. Media-ready endpoint

Keep:

```http
POST /api/v1/calls/{call_id}/media-ready
```

Request:

```json
{
  "offer_id": "offer_01K5ABCDABC",
  "installation_id": "4fb0...",
  "transport": "webrtc"
}
```

This endpoint means:

> This winning mobile device has successfully initialized its Africa’s Talking WebRTC client and is ready for media bridging.

Do **not** interpret `/accept` as media-ready.

The lifecycle should be:

```text
answer button
↓
/accept
↓
initialize WebRTC
↓
AT client ready
↓
/media-ready
↓
provider bridge / answer
↓
connected
```

This prevents the backend from bridging to a device whose WebRTC engine failed to initialize.

---

# 13. Media config endpoint

Keep:

```http
GET /api/v1/calls/media-config
```

For Android right now it should return the working WebRTC path, not guessed SIP configuration.

Example:

```json
{
  "success": true,
  "provider": "africas_talking",
  "transport": "webrtc",
  "endpoint_type": "mobile",

  "webrtc": {
    "token": "ATCAPtkn_...",
    "client_name": "aliceagent4",
    "at_username": "digiskool-crm",
    "caller_id": "+254709369917",
    "gateway_url": "wss://webrtc.africastalking.com/connect",
    "expires_in": 86400
  },

  "capabilities": {
    "hold": true,
    "dtmf": true,
    "native_incoming": true,
    "webrtc": true
  }
}
```

This matches the model your current mobile code expects: the call media configuration already supports WebRTC token/gateway/client identity separately from SIP. 

Do not return fake SIP values just to satisfy an old schema.

---

# 14. Call cancellation push

This is mandatory.

The backend must send a second push when the incoming call should stop ringing.

Examples:

```text
caller hangs up
another agent answers
another device answers
offer expires
routing moves to another agent
backend cancels call
```

Payload:

```json
{
  "type": "call_cancelled",
  "schema_version": "1",
  "call_id": "call_01K5ABCDXYZ",
  "offer_id": "offer_01K5ABCDABC",
  "reason": "caller_hangup",
  "timestamp": "2026-09-19T15:25:49Z"
}
```

FCM:

```json
{
  "message": {
    "token": "<FCM_TOKEN>",
    "data": {
      "type": "call_cancelled",
      "schema_version": "1",
      "call_id": "call_01K5ABCDXYZ",
      "offer_id": "offer_01K5ABCDABC",
      "reason": "caller_hangup",
      "timestamp": "2026-09-19T15:25:49Z"
    },
    "android": {
      "priority": "HIGH",
      "ttl": "30s"
    }
  }
}
```

Supported cancellation reasons:

```text
caller_hangup
answered_elsewhere
offer_expired
rerouted
cancelled
agent_unavailable
provider_cancelled
```

The device will immediately:

```text
stop ringtone
dismiss CallStyle notification
disconnect Telecom call
remove Flutter overlay
```

Without this endpoint/push, you will get ghost ringing.

---

# 15. Answered-elsewhere push

I would actually make this semantically distinct, even if internally it uses the same Android handling.

```json
{
  "type": "call_cancelled",
  "call_id": "call_...",
  "offer_id": "offer_...",
  "reason": "answered_elsewhere"
}
```

If one agent/device wins, notify every other offered device.

Do not rely only on Reverb/WebSocket because sleeping/terminated apps may have no active socket.

---

# 16. Offer expiry job

Backend should independently expire offers.

For example:

```text
offer created: 15:25:00
expires_at:    15:25:30
```

At expiry:

```text
if not accepted:
    mark offer expired
    send call_cancelled reason=offer_expired
    reroute if caller is still waiting
```

Do not wait for the phone to tell the backend it expired.

The backend is authoritative.

---

# 17. FCM send result handling

Store each push attempt, at least temporarily:

```text
call_id
offer_id
installation_id
fcm_message_id
sent_at
send_status
failure_code
```

Important failures:

```text
UNREGISTERED
INVALID_ARGUMENT for invalid token
authentication/config errors
temporary server errors
```

If FCM tells you the token is no longer registered:

```text
revoke/remove that token
do not keep routing calls to it
```

Receiving an FCM message ID only means FCM accepted the request, not that the device actually received the call. Firebase explicitly makes this distinction. ([Firebase][4])

That is why your `/delivery-ack` remains useful.

---

# 18. Active call recovery endpoint

Keep:

```http
GET /api/v1/calls/active
```

Response when active:

```json
{
  "success": true,
  "call": {
    "call_id": "call_01K5ABCDXYZ",
    "offer_id": "offer_01K5ABCDABC",
    "direction": "inbound",
    "status": "active",

    "caller_number": "+254743379990",
    "caller_name": "John Kamau",

    "customer_id": "customer_392",
    "ticket_id": "ticket_541",

    "provider": "africas_talking",
    "provider_call_id": "AT-call-abc123",

    "accepted_at": "2026-09-19T15:25:44Z",
    "connected_at": "2026-09-19T15:25:47Z"
  }
}
```

No call:

```json
{
  "success": true,
  "call": null
}
```

Use this when Flutter is recreated after:

```text
process recreation
activity recreation
crash/relaunch
workspace restoration
```

Your lifecycle coordinator already calls `getActiveCall()` for recovery. 

---

# 19. End call endpoint

Keep:

```http
POST /api/v1/calls/{call_id}/end
```

Request:

```json
{
  "reason": "agent_hangup"
}
```

Other reasons:

```text
agent_hangup
customer_hangup
media_failure
network_lost
provider_ended
```

This should be idempotent.

Calling it twice should not corrupt lifecycle state.

The provider webhook should remain authoritative for:

```text
final end timestamp
recording
provider duration
billing
cost
```

---

# 20. Outbound initiation

Keep:

```http
POST /api/v1/calls/initiate
```

Request:

```json
{
  "to_number": "+254743379990",
  "ticket_id": "ticket_541"
}
```

Response:

```json
{
  "success": true,
  "call_id": "call_01K5OUTBOUND123",
  "call_sid": "CA...",
  "to_number": "+254743379990",
  "normalized_to_number": "+254743379990",
  "dial_target": "+254743379990"
}
```

I would add canonical `call_id` if it isn't already returned.

Currently mobile gets a provider/application `call_sid`, but long-term the entire app should correlate with OmniDesk `call_id`, not provider IDs.

---

# 21. Outbound status pushes/realtime

For foreground outbound, WebRTC events are usually enough for UI:

```text
ringing
connected
ended
```

But backend should still broadcast authoritative state changes through your existing realtime layer:

```text
call.updated
call.connected
call.completed
```

For background or process recovery, `/calls/active` remains the fallback.

---

# 22. Provider webhooks must be idempotent

Africa’s Talking can retry callbacks.

Every provider callback should be safe to receive multiple times.

Use:

```text
provider_event_id
provider_call_id
event_type
```

or a deterministic event fingerprint.

Do not create duplicate:

```text
recordings
completed calls
tickets
billing entries
notifications
```

from retries.

---

# 23. Webhook authenticity

Before production, validate Africa’s Talking webhook authenticity using whatever verification mechanism is actually supported for your integration.

Do not trust:

```text
POST /api/voice
```

merely because it came from the public internet.

At minimum:

```text
validate configured provider secret/signature where supported
rate-limit
validate expected fields
workspace/provider mapping
log suspicious callbacks
```

---

# 24. Multi-device behavior

Assume one agent has:

```text
Samsung phone
Pixel tablet
second Android phone
```

You have to decide whether to:

```text
ring all active installations for that agent
```

or:

```text
select one preferred installation
```

I recommend ringing all recently active, call-capable installations for that selected agent.

Each receives the **same**:

```text
call_id
offer_id
```

but each has a different:

```text
installation_id
```

Whichever installation wins `/accept` becomes:

```text
accepted_installation_id
```

Then backend sends:

```text
call_cancelled / answered_elsewhere
```

to the others.

---

# 25. Idempotency requirements

These endpoints should be safe to repeat:

```text
POST /agent/devices
POST /delivery-ack
POST /accept
POST /decline
POST /media-ready
POST /end
```

Examples:

Repeated `/accept` from the already-winning installation:

```http
200
```

with current accepted state.

Same `/accept` from another installation:

```http
409 CALL_ALREADY_CLAIMED
```

Repeated `/end`:

```http
200
```

return current terminal state.

This protects you from:

```text
mobile retries
bad networks
duplicate button taps
process restoration
FCM duplicates
```

---

# 26. Server timestamps

Every relevant response should use UTC ISO-8601:

```text
2026-09-19T15:25:41.390Z
```

Do not rely on handset time for authoritative expiry.

Ideally return:

```json
{
  "server_time": "2026-09-19T15:25:41.390Z"
}
```

on call-sensitive APIs.

The app can still compare `expires_at`, but server time helps detect clock drift.

---

# 27. Suggested FCM event schema

Use a stable envelope across all call events:

```json
{
  "type": "incoming_call",
  "schema_version": "1",
  "event_id": "evt_01K...",
  "call_id": "call_01K...",
  "offer_id": "offer_01K...",
  "workspace_id": "1",
  "timestamp": "2026-09-19T15:25:40Z"
}
```

Then event-specific properties.

Supported Android call event types:

```text
incoming_call
call_cancelled
call_updated
missed_call
```

Don't make a new incompatible payload shape for every event.

---

# 28. Missed call push

When routing finally ends without anyone answering:

```json
{
  "type": "missed_call",
  "schema_version": "1",
  "event_id": "evt_...",
  "call_id": "call_...",
  "caller_name": "John Kamau",
  "caller_number": "+254743379990",
  "timestamp": "2026-09-19T15:26:11Z"
}
```

This one does not need the same immediate urgency as ringing.

You can send it as normal/high depending on product requirements, but the incoming ringing push itself is the one that must remain HIGH.

---

# 29. Recommended backend state machine

I would give the backend developer this state machine explicitly:

```text
INBOUND

provider inbound
      ↓
initiated
      ↓
offering
      ↓
offer sent
      ↓
ringing
   ┌──┴────────────┐
   │               │
accept           decline/expire
   │               │
accepted          reroute
   │               │
media ready       new offer
   │
connecting
   │
provider/WebRTC connected
   │
active
   │
provider hangup / agent hangup
   │
completed
```

Terminal alternatives:

```text
missed
cancelled
failed
expired
```

---

# 30. One very important backend rule

The backend must **not** assume:

```text
FCM send success = phone is ringing
```

FCM returning a message ID only means the FCM service accepted the message for delivery. ([Firebase][4])

You need three distinct events:

```text
push_sent_at
delivery_ack_at
accepted_at
```

That distinction will save you from a lot of debugging later.

---

# 31. Backend acceptance checklist

Before Android implementation starts, I would require the backend developer to prove all of these with API/Postman tests:

```text
☐ device can register FCM token
☐ duplicate registration is idempotent
☐ logout invalidates device
☐ inbound provider call creates call_id
☐ offer_id gets generated
☐ high-priority FCM data message sends
☐ FCM TTL is short
☐ payload contains expires_at
☐ delivery ack persists
☐ accept is atomic
☐ second device receives 409
☐ expired accept receives 410
☐ decline reroutes
☐ caller hangup sends call_cancelled
☐ answered elsewhere sends call_cancelled
☐ offer expiry sends cancellation
☐ stale FCM tokens are cleaned up
☐ media-ready is separate from accept
☐ active-call recovery works
☐ end is idempotent
☐ provider callbacks are idempotent
☐ recording/cost remain provider-authoritative
```

Once those are working, Android becomes much cleaner because the native layer only needs to implement:

```text
FCM receive
→ Telecom
→ ringtone
→ answer/decline
→ Dart handoff
→ existing WebRTC
```

I would treat this backend contract as the **freeze point** before Android implementation. The biggest things I would insist the backend developer not skip are **atomic accept, cancellation pushes, short TTL, offer IDs, installation IDs, and delivery acknowledgement**. Those are the pieces that make incoming calling reliable instead of just “working when the app happens to be open.”

[1]: https://firebase.google.com/docs/cloud-messaging/android-message-priority?authuser=8&utm_source=chatgpt.com "Set and manage Android message priority  |  Firebase Cloud Messaging"
[2]: https://firebase.google.com/docs/cloud-messaging/fcm-architecture?utm_source=chatgpt.com "FCM Architectural Overview  |  Firebase Cloud Messaging"
[3]: https://firebase.google.com/docs/cloud-messaging/customize-messages/set-message-type?authuser=2&utm_source=chatgpt.com "Firebase Cloud Messaging message types"
[4]: https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-lifespan?utm_source=chatgpt.com "Set the lifespan of a message  |  Firebase Cloud Messaging"
