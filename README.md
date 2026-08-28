# Omnidesk Agent

The mobile agent workspace for Omnidesk: a focused place for support and sales
agents to triage omnichannel conversations, resolve work, and view customer
context.

## What is ready

- Android and iOS platform projects with the `com.bigbrainzsolutions.omnidesk` application ID.
- Backend-only bearer-token authentication with secure Keychain/Keystore storage.
- Login, forgot password, manual-token reset password, change password, logout, and logout-everywhere flows.
- Dio-backed API client with authenticated request injection, safe header redaction, and typed API failures.
- Firebase Cloud Messaging only; server-side FCM token registration is intentionally deferred.

## Architecture

New product code is split by responsibility:

```
lib/models/auth/       # Auth session, agent, workspace, and failure models
lib/services/          # Dio, secure storage, repository, session, and FCM
lib/navigation/        # Auth-aware GoRouter configuration
lib/pages/             # Authentication and authenticated workspace screens
```

The app starts in `lib/main.dart`. Firebase is initialized only for FCM.

## Connect a backend

1. Copy `.env.example` to `.env` and set `API_BASE_URL` to the backend API root
   that contains `/auth/*` endpoints.
2. Implement feature repositories using `ApiService`; keep JSON/DTO mapping at
   the repository boundary and never expose transport maps to widgets.
3. Generate real Firebase configuration with FlutterFire for the current bundle
   identifier before enabling FCM on a device.

When the realtime inbox is added, model updates as an idempotent stream keyed
by conversation ID. Merge websocket events with paginated REST snapshots in a
repository/controller rather than in widget state to avoid ordering and retry
bugs.

## Run and verify

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

The workspace placeholder is intentionally small. API configuration is required
for authentication, and Firebase configuration is required for FCM.
