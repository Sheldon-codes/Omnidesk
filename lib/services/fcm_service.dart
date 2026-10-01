import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../firebase_options.dart';
import 'calls/call_models.dart';
import '../pages/notifications_page/notifications_models.dart';
part 'fcm_service.g.dart';

@Riverpod(keepAlive: true)
FcmService fcmService(Ref ref) => FcmService();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final type = '${message.data['type'] ?? ''}'.toLowerCase();
  // A background isolate cannot touch Riverpod. Preserve offers so the
  // application coordinator can reconcile them on the next foreground frame,
  // and drop a preserved offer when its cancellation arrives first so a dead
  // call can never surface after the process resumes.
  if (type == 'call_cancelled') {
    final cancel = _incomingCallCancel(message.data);
    if (cancel != null) await PendingCallOfferStore().dropIfMatches(cancel.callId);
    return;
  }
  final offer = _incomingCallOffer(message.data);
  if (offer == null || offer.isExpired) return;
  await PendingCallOfferStore().save(offer);
}

/// Backend-driven cancellation/state update for an offered call. Routed over
/// FCM (APNs background push on iOS) alongside the PushKit VoIP wake-up path.
class CallCancellation {
  const CallCancellation({
    required this.callId,
    this.offerId,
    this.reason,
  });

  final String callId;
  final String? offerId;
  final String? reason;
}

class FcmService {
  // [_messaging] is resolved lazily: touching `FirebaseMessaging.instance`
  // with no initialized Firebase app throws `[core/no-app]` and would poison
  // every provider that (transitively) reads this service — including the
  // call coordinator on FCM-disabled builds. Resolution failure just means
  // push is unavailable; all call flows degrade to socket/REST.
  FcmService({FirebaseMessaging? messaging}) : _messaging = messaging;
  FirebaseMessaging? _messaging;
  String? _token;
  String? _apnsToken;
  String? _voipPushToken;
  bool _initialized = false;
  final _offers = StreamController<CallOffer>.broadcast();
  final _cancels = StreamController<CallCancellation>.broadcast();
  final _tokenChanges = StreamController<String?>.broadcast();
  final _notificationEvents = StreamController<AppNotification>.broadcast();
  final _notificationTaps = StreamController<AppNotification>.broadcast();
  final _notificationRefreshEvents = StreamController<void>.broadcast();
  String? get currentToken => _token;
  String? get apnsToken => _apnsToken;
  String? get voipPushToken => _voipPushToken;
  Stream<CallOffer> get incomingCallOffers => _offers.stream;
  Stream<CallCancellation> get incomingCallCancels => _cancels.stream;
  Stream<String?> get tokenChanges => _tokenChanges.stream;
  Stream<AppNotification> get notificationEvents => _notificationEvents.stream;
  Stream<AppNotification> get notificationTaps => _notificationTaps.stream;

  /// Non-call push event signal for lightweight badge refreshes.
  ///
  /// Call offers deliberately bypass this stream: their native delivery and
  /// lifecycle are latency-sensitive and must stay on the existing path.
  Stream<void> get notificationRefreshEvents =>
      _notificationRefreshEvents.stream;

  FirebaseMessaging? _resolveMessaging() {
    final existing = _messaging;
    if (existing != null) return existing;
    try {
      return _messaging = FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final messaging = _resolveMessaging();
    if (messaging == null) {
      developer.log(
        'FCM unavailable: Firebase is not initialized on this build.',
        name: 'FcmService',
      );
      return;
    }
    try {
      final permissions = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _token = await messaging.getToken();
      _apnsToken = await messaging.getAPNSToken();
      _tokenChanges.add(_token);
      developer.log(
        'FCM initialized: permission=${permissions.authorizationStatus.name}, '
        'fcmTokenAvailable=${_token?.isNotEmpty == true}, '
        'apnsTokenAvailable=${_apnsToken?.isNotEmpty == true}.',
        name: 'FcmService',
      );
      messaging.onTokenRefresh.listen((token) {
        _token = token;
        _tokenChanges.add(token);
        developer.log(
          'FCM token refreshed: fcmTokenAvailable=${token.isNotEmpty}.',
          name: 'FcmService',
        );
      });
      // Static-only in this firebase_messaging release; guarded by the
      // surrounding try/catch when no Firebase app exists.
      FirebaseMessaging.onMessage.listen(_handleMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handleMessage(message, opened: true),
      );
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleMessage(initial, opened: true);
      final pending = await PendingCallOfferStore().take();
      if (pending != null && !pending.isExpired) _offers.add(pending);
      _initialized = true;
    } catch (error) {
      developer.log('FCM unavailable: $error', name: 'FcmService');
    }
  }

  void _handleMessage(RemoteMessage message, {bool opened = false}) {
    final type = '${message.data['type'] ?? ''}'.toLowerCase();
    final offer = _incomingCallOffer(message.data);
    if (offer != null && !offer.isExpired) {
      _offers.add(offer);
      return;
    }
    // Cancellation/state updates arrive over FCM (APNs background pushes on
    // iOS) next to the PushKit wake-up path. Surface them to the call
    // coordinator; only non-call payloads fall through to notifications.
    if (type == 'call_cancelled') {
      final cancel = _incomingCallCancel(message.data);
      if (cancel != null) _cancels.add(cancel);
      return;
    }
    _notificationRefreshEvents.add(null);
    try {
      final notification = AppNotification.fromJson(message.data);
      _notificationEvents.add(notification);
      if (opened) _notificationTaps.add(notification);
      developer.log(
        'FCM notification event received type=${notification.type}',
        name: 'FcmService',
      );
    } on Object {
      // Non-notification payloads remain ignored; call handling above is
      // intentionally untouched.
    }
    developer.log('FCM message: ${message.messageId}', name: 'FcmService');
  }

  Future<void> clearToken() async {
    _token = null;
    _apnsToken = null;
    _voipPushToken = null;
    _tokenChanges.add(null);
  }

  void updateVoipPushToken(String token) {
    if (token == _voipPushToken) return;
    _voipPushToken = token;
    _tokenChanges.add(_token);
    developer.log(
      'Native push token updated: tokenAvailable=${token.isNotEmpty}.',
      name: 'FcmService',
    );
  }

  Future<void> dispose() async {
    await _offers.close();
    await _cancels.close();
    await _tokenChanges.close();
    await _notificationEvents.close();
    await _notificationTaps.close();
    await _notificationRefreshEvents.close();
  }
}

CallOffer? _incomingCallOffer(Map<String, dynamic> payload) {
  if ('${payload['type'] ?? ''}'.toLowerCase() != 'incoming_call') return null;
  final offer = CallOffer.fromJson(payload);
  if (offer.callId.isEmpty ||
      offer.offerId.isEmpty ||
      offer.callerNumber.isEmpty ||
      offer.workspaceId.isEmpty) {
    return null;
  }
  return offer;
}

CallCancellation? _incomingCallCancel(Map<String, dynamic> payload) {
  if ('${payload['type'] ?? ''}'.toLowerCase() != 'call_cancelled') {
    return null;
  }
  final callId = '${payload['call_id'] ?? ''}';
  if (callId.isEmpty) return null;
  final offerId = '${payload['offer_id'] ?? ''}';
  final reason = '${payload['reason'] ?? ''}';
  return CallCancellation(
    callId: callId,
    offerId: offerId.isEmpty ? null : offerId,
    reason: reason.isEmpty ? null : reason,
  );
}

/// Secure hand-off between an FCM background isolate and the UI isolate.
class PendingCallOfferStore {
  PendingCallOfferStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  static const _key = 'omnidesk_pending_call_offer';
  final FlutterSecureStorage _storage;

  Future<void> save(CallOffer offer) =>
      _storage.write(key: _key, value: jsonEncode(offer.toJson()));

  Future<CallOffer?> take() async {
    final raw = await _storage.read(key: _key);
    await _storage.delete(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _incomingCallOffer(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      return null;
    }
  }

  /// Drops the preserved offer when its backend cancellation arrives before
  /// the UI isolate drains it. A non-matching preserved offer is re-saved so
  /// an unrelated cancellation can never discard a live incoming call.
  Future<void> dropIfMatches(String callId) async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final storedId = '${decoded['call_id'] ?? ''}';
      if (storedId == callId) {
        await _storage.delete(key: _key);
      }
    } catch (_) {
      // A corrupt entry must not block future offers; leave it for take().
    }
  }
}
