Yes — the new file still has the same core architectural problem: **incoming calls are discovered by polling `GET /calls/waiting`**, and the heartbeat is still tied to the app being active. The document literally says the app should ping every 30–60 seconds while active, and that `/calls/waiting` polls for waiting callers.  

For a production mobile VoIP app, I would **not use polling as the primary incoming-call mechanism at all**. Keep `/calls/waiting` only as a recovery/fallback endpoint or for the foreground queue screen.

The correct architecture is push-driven:

```text
Caller reaches OmniDesk number
        ↓
Africa's Talking / Twilio notifies backend
        ↓
Backend creates incoming call session
        ↓
Backend selects eligible agent
        ↓
Backend PUSHES incoming call to agent device
        ↓
iOS: PushKit → CallKit
Android: high-priority FCM → Android Telecom
        ↓
OS wakes/presents incoming call
        ↓
Agent answers
        ↓
Backend atomically claims call
        ↓
WebRTC media connects
```

Apple explicitly designed PushKit so a VoIP app does **not need to remain running** to receive an incoming call: the server sends a VoIP push, iOS wakes or launches the app, and CallKit presents the call UI. ([Apple Developer][1]) Android's equivalent is an urgent high-priority FCM message, which can wake a sleeping device, followed by integration with Android Telecom for the actual call lifecycle. ([Firebase][2])

## What is currently approached wrongly

The biggest problem is this conceptual dependency:

```text
Available agent
   ↓
heartbeat every 30–60 sec
   ↓
app repeatedly calls /calls/waiting
   ↓
eventually notices an incoming call
```

That model is appropriate for a browser dashboard. It is wrong as the reliability mechanism for a native mobile softphone.

It creates several problems.

First, it assumes Flutter is alive. iOS will suspend a backgrounded app; Android may put it into Doze or kill it. You should not try to defeat the OS by keeping Flutter alive indefinitely.

Second, call latency becomes tied to polling frequency. If you poll every 5 seconds, a call can already be 5 seconds old before the phone even knows about it. Poll every 30 seconds and the approach becomes unusable.

Third, increasing the polling rate creates unnecessary server load:

```text
500 agents × request every 2 seconds
= 250 requests/sec

even when nobody is calling
```

Push reverses this:

```text
no calls → no incoming-call traffic
call arrives → one event is pushed immediately
```

Fourth, the heartbeat currently mixes two different concepts. `/agent/heartbeat` is described as maintaining routing priority while the app is active.  But an iPhone can be perfectly capable of receiving VoIP calls while Flutter is suspended. Therefore:

```text
No recent foreground heartbeat
```

must **not automatically mean**

```text
Agent cannot receive calls
```

Those should be separated.

---

# What should replace polling

Use three complementary mechanisms, each for a different job.

### 1. Push notifications: wake-up mechanism

This is the critical one.

For iOS:

```text
APNs VoIP Push / PushKit
       ↓
CallKit
```

Apple says PushKit can wake or launch the app for incoming VoIP calls, and the app should report the incoming call to CallKit promptly. The push payload should include a unique call identifier and enough caller information to present the call without first doing several API lookups. ([Apple Developer][1])

For Android:

```text
FCM high-priority data message
       ↓
native receiver/service
       ↓
Android Telecom
```

FCM high priority is intended for urgent, user-visible events and can wake a device in Doze for limited processing. ([Firebase][2]) Android's Telecom APIs then model the incoming call itself and provide answer/reject/hold/disconnect integration. ([Android Developers][3])

### 2. WebSocket: foreground real-time synchronization

While OmniDesk is open:

```text
WebSocket
    ↓
call.incoming
call.ringing
call.answered
call.ended
agent.status_changed
```

This gives you very fast UI updates and avoids repeated REST polling.

But a WebSocket is **not** your wake-up mechanism. If the OS suspends the app, assume the socket disappears.

### 3. REST: state recovery and commands

Your existing REST APIs remain useful for:

```text
fetch call history
initiate outbound call
change availability
fetch current active call
accept/reject/end calls
recover after app restart
```

So the production architecture is:

```text
Push      = wake me
WebSocket = update me while awake
REST      = command/query/recover
```

That distinction is very important.

---

# What is missing from this backend

The document still lacks an entire **mobile-device and incoming-call delivery layer**.

## Device registration

The backend currently has no documented way for an agent's phone to register its push destination.

You need something like:

```http
POST /agent/devices
```

For iOS:

```json
{
  "installation_id": "uuid-of-this-installation",
  "platform": "ios",
  "voip_push_token": "...",
  "notification_token": "...",
  "app_version": "1.0.0"
}
```

Android:

```json
{
  "installation_id": "uuid-of-this-installation",
  "platform": "android",
  "fcm_token": "...",
  "app_version": "1.0.0"
}
```

And:

```http
DELETE /agent/devices/{installation_id}
```

on logout/device removal.

The server should store something like:

```text
AgentDevice
├── id
├── agentId
├── workspaceId
├── installationId
├── platform
├── fcmToken
├── apnsToken
├── voipPushToken
├── enabled
├── lastSeenAt
├── lastPushAckAt
└── appVersion
```

For iOS specifically, the PushKit VoIP token should be treated separately from a standard notification token.

---

# Incoming call assignment needs to be server-owned

Right now `/calls/waiting` returns the queue and leaves discovery to the client. 

Instead, when a caller arrives, the backend should do:

```text
incoming provider webhook
        ↓
create call
        ↓
determine eligible agents
        ↓
select/offer call
        ↓
send push
```

The mobile should not decide:

> "I see caller #306 in `/calls/waiting`, therefore I guess this call is mine."

The server needs to explicitly assign/offer the call.

I would introduce an internal state machine:

```text
queued
  ↓
offered
  ↓
ringing
  ↓
accepted
  ↓
connecting
  ↓
active
  ↓
completed
```

With terminal alternatives:

```text
declined
missed
cancelled
failed
busy
expired
```

---

# Add a stable internal `call_id`

You already return `call_sid` and `session_id` from outbound initiation.  Those provider identifiers are useful, but I would also have an OmniDesk-owned UUID:

```json
{
  "call_id": "01JQXYZ...",
  "provider_call_sid": "CA...",
  "session_id": "AT-call-sess-..."
}
```

Use `call_id` everywhere in the mobile lifecycle.

That gives you a provider-independent identifier if you switch from Africa's Talking to Twilio, or support both.

The incoming push might contain:

```json
{
  "type": "incoming_call",
  "call_id": "01JQXYZ...",
  "caller_number": "+254722000111",
  "customer_id": 85,
  "customer_name": "David Mwangi",
  "ticket_id": 14,
  "workspace_id": 1,
  "expires_at": "2026-09-04T11:35:25Z"
}
```

This payload should contain enough data to display your incoming call screen immediately.

Don't require:

```text
Push arrives
→ GET customer
→ GET ticket
→ GET call
→ GET token
→ finally ring
```

The OS call UI needs to appear immediately.

---

# Add an atomic call-accept endpoint

I would consider this mandatory:

```http
POST /calls/{call_id}/accept
```

Example:

```json
{
  "installation_id": "device-123"
}
```

The backend then atomically changes:

```text
offered/ringing → accepted
```

for that exact agent/device.

This matters enormously if multiple agents or multiple devices ring simultaneously.

Imagine:

```text
Hillary's iPhone     → Answer
Hillary's Android    → Answer
John's phone         → Answer
```

Without an atomic claim, you can create a race condition.

The server must guarantee:

```text
first valid answer wins
```

and subsequent requests get:

```http
409 Conflict
```

with something like:

```json
{
  "code": "CALL_ALREADY_CLAIMED"
}
```

This is a backend responsibility, not Flutter logic.

---

# Add decline/reject

You also need:

```http
POST /calls/{call_id}/decline
```

For example:

```json
{
  "installation_id": "device-123",
  "reason": "agent_declined"
}
```

Then the backend can immediately offer the call to another agent instead of waiting for a polling timeout.

---

# Add cancellation from the server

This is another major missing lifecycle event.

Suppose:

```text
Caller hangs up
```

while Hillary's phone is ringing.

The server needs to tell Hillary:

```text
call.cancelled
```

immediately.

Otherwise CallKit/Android can continue presenting a dead call.

Similarly, if Hillary answers on another device:

```text
call.answered_elsewhere
```

must dismiss the incoming screen on her other devices.

You therefore need server-to-device events such as:

```text
incoming_call
call_cancelled
call_answered_elsewhere
call_ended
call_failed
```

Push is needed when backgrounded; WebSocket can deliver these quickly while foregrounded.

---

# Add ring expiry

Every call offer must have a backend-controlled expiry.

Example:

```text
offered_at    = 14:32:05
expires_at    = 14:32:30
```

If the call hasn't been accepted by then:

```text
ringing → expired
```

and the router can try another agent or mark it missed.

This matters because push delivery isn't mathematically instantaneous. If a device finally receives an old push after the call has already been rerouted, `/accept` must reject it.

The backend should check:

```text
call.state == ringing
AND offer.agent_id == currentAgent
AND offer.expires_at > now
```

before accepting.

---

# Add push acknowledgement

This isn't required merely to make calls work, but I would absolutely include it in a serious CRM.

Something like:

```http
POST /calls/{call_id}/delivery-ack
```

Request:

```json
{
  "installation_id": "device-123",
  "received_at": "2026-09-04T11:35:05.521Z",
  "native_ui_presented": true
}
```

Then OmniDesk can distinguish:

```text
backend created call ✓
APNs/FCM accepted push ✓
device received push ✓
CallKit/Telecom displayed call ✓
agent didn't answer
```

from:

```text
backend created call ✓
push sent ✓
device never acknowledged ✕
```

Without this, when someone says "I never received that call," you'll have very little observability.

---

# Add delivery telemetry

Store timestamps like:

```text
provider_received_at
call_created_at
agent_selected_at
push_sent_at
push_provider_accepted_at
push_received_at
native_presented_at
accepted_at
media_connect_started_at
media_connected_at
ended_at
```

Then you can actually measure:

```text
Provider → backend        80 ms
Backend → push provider   40 ms
Push → device            350 ms
Device → CallKit          80 ms
Answer → audio           900 ms
```

That will become invaluable in production.

---

# `/agent/heartbeat` needs to be redefined

Currently it says:

> ping every 30–60 seconds while the mobile app is active to maintain agent routing priority. 

That's fine as **foreground presence telemetry**.

But don't use it as proof that the device can receive calls.

Instead maintain three separate concepts:

```text
Agent availability
    Available / Busy / Break / Away

Call routing preference
    receive_calls = true/false

Device reachability
    valid push token / last delivery info
```

Your profile UI already separates:

```text
Available

Receive incoming calls [ON]
```

so the backend should support that distinction too.

For example:

```http
POST /agent/availability
```

```json
{
  "state": "available",
  "receive_calls": true
}
```

The current contract only models `is_available` and state together. 

That means your current mobile UI is slightly richer than the backend data model.

---

# Add `GET /calls/active`

This is another important missing endpoint.

Imagine:

```text
Agent answers call
→ Flutter process later gets recreated
→ call is still active through native/media layer
```

The app needs to reconstruct:

* who's on the call,
* elapsed time,
* ticket,
* mute/hold state if relevant,
* call identifier,
* current server state.

Something like:

```http
GET /calls/active
```

Response:

```json
{
  "active": true,
  "call": {
    "call_id": "01JQXYZ...",
    "direction": "inbound",
    "state": "active",
    "caller_number": "+254722000111",
    "customer_name": "David Mwangi",
    "ticket_id": 14,
    "connected_at": "2026-09-04T11:36:14Z"
  }
}
```

That endpoint also lets your app reconcile after network interruptions.

---

# Don't make the mobile authoritative for call completion

This part of the current API concerns me more than polling:

```http
POST /calls/outbound/complete
```

where Flutter sends:

```json
{
  "duration": 145,
  "recording_url": "..."
}
```

The document says the mobile app calls it when the softphone disconnects. 

That should not be the authoritative source of final call state.

What happens if:

```text
call active
→ app crashes
→ phone loses battery
→ internet switches networks
→ Flutter process dies
```

Then `/calls/outbound/complete` may never execute.

Your telephony provider should send **server-to-server lifecycle webhooks** to OmniDesk.

The backend should own:

```text
ringing
answered_at
completed_at
duration
failure reason
recording URL
```

based primarily on Africa's Talking/Twilio callbacks.

Flutter can still call:

```text
POST /calls/:id/end
```

to express:

> The agent pressed End Call.

But provider callbacks should determine the authoritative completed state.

So I'd replace this philosophy:

```text
Mobile finishes call
→ tells backend final duration/recording
```

with:

```text
Mobile requests hangup
       +
Provider sends lifecycle callback
       ↓
Backend finalizes CallLog
```

This is much more production-safe.

---

# `/calls/waiting` should remain — but for a different purpose

I would **not delete** this endpoint.

It is useful for:

```text
foreground queue view
supervisor dashboards
manual queue recovery
diagnostics
fallback sync
```

But its description should stop saying mobile discovers incoming calls by polling.

Instead:

```text
GET /calls/waiting

Returns the current queue snapshot.
Not used as the primary mobile incoming-call delivery mechanism.
```

That is the key change.

---

# WebSocket endpoint/events

I would add a realtime channel.

It doesn't necessarily need to be REST documented as an endpoint, but your backend contract should document events.

For example:

```text
connection:
wss://api.omnidesk.africa/realtime
```

Events:

```json
{
  "event": "call.state_changed",
  "call_id": "01JQXYZ...",
  "state": "active"
}
```

and:

```text
call.offered
call.cancelled
call.accepted
call.connected
call.held
call.resumed
call.ended
call.recording_ready
```

When Flutter is foregrounded:

```text
WebSocket event
```

can update the UI almost immediately.

When Flutter isn't alive:

```text
PushKit / FCM
```

handles the important wake-up events.

---

# iOS backend requirements specifically

Your server needs APNs VoIP support.

That means storing PushKit tokens and sending a **VoIP APNs push**, not just ordinary notification pushes.

Apple specifically recommends including the unique call identifier and caller information in the payload, using very short/zero expiration to avoid stale calls being delivered later, and reporting the incoming call to CallKit from the PushKit handler. ([Apple Developer][1])

Conceptually:

```text
Backend
   ↓
APNs
push-type: voip
topic: <bundle-id>.voip
short expiration
   ↓
PushKit
   ↓
CallKit
```

This is missing from the current backend document entirely.

---

# Android backend requirements specifically

For Android:

```text
Backend
   ↓
FCM
priority = high
data payload = incoming call
   ↓
device wakes briefly
   ↓
Android Telecom/native call handling
```

Firebase notes that high-priority messages are intended for time-sensitive user-visible events and can wake a sleeping device. ([Firebase][2])

Then Android Telecom should own the operating-system call representation. Its `ConnectionService`/Telecom flow supports incoming calls plus answer, reject, hold, and disconnect commands. ([Android Developers][3])

Again, that requires backend FCM token registration and push dispatch, neither of which appears in this API document.

---

# The backend API I would ultimately want

You don't need to overcomplicate it. Something approximately like this is enough:

```text
DEVICE
POST   /agent/devices
DELETE /agent/devices/:installationId

PRESENCE
GET    /agent/profile
POST   /agent/availability
POST   /agent/heartbeat

MEDIA
POST   /calls/token

CURRENT CALL
GET    /calls/active
GET    /calls/:callId

INCOMING
POST   /calls/:callId/delivery-ack
POST   /calls/:callId/accept
POST   /calls/:callId/decline

CALL CONTROL
POST   /calls/:callId/end
POST   /calls/:callId/hold
POST   /calls/:callId/resume

OUTBOUND
POST   /calls/initiate

HISTORY
GET    /calls/logs

QUEUE / FALLBACK
GET    /calls/waiting
```

And behind these APIs:

```text
Africa's Talking/Twilio webhooks
Push dispatcher
APNs PushKit sender
FCM sender
Call routing service
Atomic offer/claim service
Realtime WebSocket broadcaster
```

---

# The routing architecture should look like this

```text
                  INCOMING PSTN CALL
                          │
                          ▼
                  Africa's Talking
                          │
                    provider webhook
                          │
                          ▼
               ┌────────────────────┐
               │ OmniDesk Backend   │
               │                    │
               │ Create call        │
               │ Find agents        │
               │ Select/offer agent │
               └─────────┬──────────┘
                         │
                ┌────────┴────────┐
                │                 │
               iOS              Android
                │                 │
          APNs VoIP Push     FCM High Priority
                │                 │
            PushKit          Native Receiver
                │                 │
            CallKit        Android Telecom
                │                 │
                └────────┬────────┘
                         │
                    Agent answers
                         │
                         ▼
                POST /calls/:id/accept
                         │
                  atomic claim
                         │
                         ▼
                   WebRTC media
                         │
                         ▼
                      ACTIVE
                         │
                 provider callbacks
                         │
                         ▼
               OmniDesk finalizes call
```

There is **zero requirement for Flutter to poll continuously** in that architecture.

---

## What I would tell your backend agent to change

The short version is:

> Stop treating `GET /calls/waiting` and `/agent/heartbeat` as the mechanism by which the mobile app discovers incoming calls. Keep them for queue snapshots, foreground presence and recovery only.
>
> Implement server-driven mobile call delivery. Register each mobile installation and its FCM token / iOS PushKit VoIP token. When the telephony provider reports an incoming call, create an OmniDesk-owned call session, select an eligible agent server-side, persist a time-limited call offer, and immediately send an incoming-call push to that agent's registered devices. On iOS use APNs VoIP PushKit and CallKit; on Android use high-priority FCM and Android Telecom.
>
> Add atomic call lifecycle endpoints for `accept`, `decline`, `end`, active-call recovery, and delivery acknowledgment. Use a stable internal `call_id`. Prevent multiple agents/devices from accepting the same call through an atomic state transition. Add expiry and cancellation semantics so stale incoming calls cannot be answered and so devices are told immediately when the caller hangs up or another device answers.
>
> Use WebSockets for realtime foreground synchronization but never depend on the socket staying alive in the background. Push wakes the device; WebSocket updates a running app; REST performs commands and state recovery.
>
> Make provider webhooks authoritative for ringing, answer, completion, duration, failure and recording metadata. Do not depend on Flutter calling `/calls/outbound/complete` to finalize a call.
>
> Separate agent availability, `receive_calls`, and device reachability instead of using foreground heartbeat as proof that a device can receive calls.

That would move the backend from a **web softphone API adapted for mobile** to an actual **mobile VoIP architecture**.

[1]: https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit?utm_source=chatgpt.com "Responding to VoIP Notifications from PushKit | Apple Developer Documentation"
[2]: https://firebase.google.com/docs/cloud-messaging/android-message-priority?utm_source=chatgpt.com "Set and manage Android message priority  |  Firebase Cloud Messaging"
[3]: https://developer.android.com/reference/android/telecom/ConnectionService?utm_source=chatgpt.com "ConnectionService  |  API reference  |  Android Developers"






Yes — for a proper mobile VoIP setup, you absolutely need a **device registration layer**.

Your current call API has agent availability, heartbeat, queue polling, token generation, outbound calls, logs, etc., but it has no documented way to say:

> “Agent Hillary currently has this iPhone with this PushKit token and this Android phone with this FCM token.”

That is the missing link between your backend and the OS push systems. The current endpoint document contains no device-registration API or push-token model.  

The important distinction is that **the mobile app registers device tokens with your backend**, while **the secret credentials used to send through APNs/FCM stay only on your backend**.

## 1. What the mobile app needs to send to your backend

Each app installation should have its own persistent installation/device ID.

Something like:

```text
installation_id
platform
FCM token
APNs token
PushKit VoIP token
app version
device metadata
```

Not all fields apply to both platforms.

For Android:

```json
{
  "installation_id": "c5f4a7a2-...",
  "platform": "android",
  "fcm_token": "fcm-registration-token",
  "app_version": "1.0.0",
  "device_name": "Samsung SM-S928B"
}
```

For iOS:

```json
{
  "installation_id": "c912ad65-...",
  "platform": "ios",
  "apns_token": "normal-notification-token",
  "voip_push_token": "pushkit-voip-token",
  "app_version": "1.0.0",
  "device_name": "iPhone"
}
```

For VoIP calls, the important iOS token is the **PushKit VoIP token**, not just the normal notification token.

---

# 2. The backend endpoint I would add

I would use:

```http
POST /agent/devices
```

The endpoint should work as an **upsert**.

Meaning if this installation already exists:

```text
update its tokens
```

rather than creating duplicates.

Example:

```json
{
  "installation_id": "device-installation-uuid",
  "platform": "ios",
  "push": {
    "apns_token": "...",
    "voip_token": "..."
  },
  "app_version": "1.0.0"
}
```

Android:

```json
{
  "installation_id": "device-installation-uuid",
  "platform": "android",
  "push": {
    "fcm_token": "..."
  },
  "app_version": "1.0.0"
}
```

Response:

```json
{
  "success": true,
  "device_id": "dev_82...",
  "registered": true
}
```

---

# 3. You need to update tokens, because they can change

Push tokens are **not permanent identifiers**.

So your Flutter/native layer should listen for token changes.

When FCM gives you a new token:

```text
FirebaseMessaging.onTokenRefresh
```

send it back to:

```http
POST /agent/devices
```

Likewise, if PushKit gives iOS a new VoIP token, update the backend immediately.

This is why I recommend an `installation_id`.

Your backend identifies:

```text
this same app installation
```

even though:

```text
its FCM/APNs token changed
```

---

# 4. You also need unregister/deactivate

When the agent logs out:

```http
DELETE /agent/devices/{installation_id}
```

or:

```http
POST /agent/devices/{installation_id}/deactivate
```

You generally want to stop routing calls to that installation.

Example:

```json
{
  "success": true
}
```

This is important because otherwise an old phone may keep receiving calls after Hillary logs out of OmniDesk.

---

# 5. I would not actually delete the database record immediately

Internally I prefer:

```text
enabled = false
```

rather than hard deletion.

So:

```text
AgentDevice
```

could look like:

```text
id
user_id
workspace_id

installation_id

platform
    ios
    android

fcm_token
apns_token
voip_push_token

enabled

app_version
device_name

last_registered_at
last_seen_at
last_push_at
last_push_ack_at

created_at
updated_at
```

That also helps debugging.

---

# 6. Do NOT send APNs/FCM credentials from the mobile app

This distinction is critical.

You have two kinds of things:

### Device token

Safe/expected to come from the phone:

```text
FCM token
APNs device token
PushKit VoIP token
```

These tell your backend:

> send a notification to this installation.

### Provider credential

These must stay on your server:

```text
Firebase service-account credentials
APNs signing key
Apple Team ID
Apple Key ID
APNs topic / bundle configuration
```

These let your server actually send notifications.

The Flutter app must **never contain** your APNs `.p8` private key or Firebase service-account private key.

---

# 7. iOS backend credentials

For PushKit/APNs your server normally needs Apple credentials such as:

```text
APPLE_TEAM_ID
APNS_KEY_ID
APNS_PRIVATE_KEY
APP_BUNDLE_ID
```

Conceptually:

```env
APPLE_TEAM_ID=XXXXXXXXXX
APNS_KEY_ID=ABC123XYZ
APNS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----..."
IOS_BUNDLE_ID=africa.omnidesk.mobile
```

And for VoIP:

```text
APNs topic:
africa.omnidesk.mobile.voip
```

depending on your exact bundle identifier.

Those settings belong in your backend infrastructure / secret manager, not in Mongo and definitely not in Flutter.

---

# 8. Android backend credentials

For Android FCM, your backend needs Firebase Admin credentials.

For example your NestJS service may use Firebase Admin SDK with:

```text
project_id
client_email
private_key
```

Usually from a Google service-account credential or workload identity.

Again:

```text
backend only
```

The Flutter application only knows its own FCM registration token.

---

# 9. There is another device property I would add: call capability

Not every registered installation should necessarily be eligible to receive calls.

For example:

```json
{
  "capabilities": {
    "push_notifications": true,
    "voip_calls": true
  }
}
```

This could be server-derived instead of client-controlled.

You might eventually have:

```text
web browser
mobile Android
mobile iPhone
tablet
```

registered to one agent.

You want the routing service to know which are valid call endpoints.

---

# 10. Call receiving preference is separate

Remember the Profile screen you built:

```text
Availability
Available

Receive incoming calls [ ON ]
```

I would model that separately from the individual device.

For example:

### Agent

```text
availability = available
receive_calls = true
```

### Device

```text
enabled = true
voip_capable = true
valid_push_token = true
```

Then the router asks:

```text
Is Hillary available?
AND
Does Hillary allow calls?
AND
Does Hillary have at least one reachable call-capable device?
```

Only then offer the call.

---

# 11. Recommended registration lifecycle

When the app starts after login:

```text
Login
 ↓
Generate/load installation UUID
 ↓
Initialize Firebase Messaging / PushKit
 ↓
Get current push token(s)
 ↓
POST /agent/devices
 ↓
Backend associates device with authenticated agent
```

Then later:

```text
FCM / PushKit token changes
 ↓
POST /agent/devices again
 ↓
Backend updates that installation
```

Logout:

```text
Logout
 ↓
DELETE /agent/devices/{installationId}
or deactivate it
 ↓
clear local authentication
```

---

# 12. Device registration should happen independently of availability

Don't do:

```text
Agent becomes Available
↓
register push token
```

Instead:

```text
Logged in
↓
register device
```

Then:

```text
Agent available/offline
```

is a completely separate setting.

That way the backend always knows the device exists.

---

# 13. You'll also want an acknowledgement endpoint

Once you have device registration, I'd add:

```http
POST /calls/{callId}/delivery-ack
```

Example:

```json
{
  "installation_id": "install-123",
  "received_at": "2026-09-04T14:42:18.156+03:00",
  "native_ui_presented": true
}
```

This lets the backend know:

```text
FCM/APNs was sent
AND
the actual device woke up
AND
incoming call UI was presented
```

That's important for reliability monitoring.

---

# 14. Multiple phones for one agent

Don't structure the DB like:

```text
Agent
fcmToken
```

because one agent may eventually have:

```text
Hillary
├── work iPhone
├── Android phone
└── tablet
```

Use:

```text
Agent
    ↓ one-to-many
AgentDevice
```

Then your routing service can ring all active eligible devices.

For example:

```text
Incoming call
   ↓
assigned to Hillary
   ↓
┌──────────────┬──────────────┐
│              │              │
iPhone       Android        tablet
rings         rings         ignored
                         (not VoIP capable)
```

Hillary answers iPhone:

```text
POST /calls/:id/accept
```

Backend atomically claims it.

Then sends:

```text
call_answered_elsewhere
```

to Android.

Android dismisses its incoming call.

---

# 15. Push registration endpoint should not accept `agent_id`

One security detail I strongly recommend.

Don't do:

```json
{
  "agent_id": 5,
  "fcm_token": "..."
}
```

because the client could claim:

> Register this phone for agent 7.

Instead:

```http
POST /agent/devices
Authorization: Bearer <Hillary token>
```

The backend gets Hillary's user ID from authentication.

Then:

```text
device.user_id = authenticated user
```

The mobile should never choose the owner.

---

# 16. Suggested API set

For the device side, I'd start with just three:

```text
POST   /agent/devices
GET    /agent/devices
DELETE /agent/devices/:installationId
```

`GET` is optional for the mobile app but useful for account/device management and debugging.

Then calling lifecycle:

```text
POST /calls/:callId/delivery-ack
POST /calls/:callId/accept
POST /calls/:callId/decline
POST /calls/:callId/end
GET  /calls/active
```

That's enough without creating an enormous API surface.

---

## So the complete picture becomes

```text
                         LOGIN
                           │
                           ▼
                   Register device
                           │
         ┌─────────────────┴─────────────────┐
         │                                   │
        iOS                               Android
         │                                   │
 PushKit VoIP token                      FCM token
 APNs normal token                           │
         │                                   │
         └──────────▶ OmniDesk ◀─────────────┘
                       Backend
                          │
                  AgentDevice records
                          │
                          │
                     incoming call
                          │
                  select available agent
                          │
                    find their devices
                          │
         ┌────────────────┴───────────────┐
         │                                │
     APNs VoIP                     FCM high priority
         │                                │
      CallKit                       Android Telecom
         │                                │
         └──────────────┬─────────────────┘
                        │
                     Answer
                        │
             POST /calls/:id/accept
                        │
                  WebRTC connects
```

So yes: **device registration is one of the first backend additions I would make before you start wiring the real mobile incoming-call lifecycle.** Right now the API knows about agents, availability and waiting calls, but it doesn't yet know **where to push a call to that agent's mobile device**.
