import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../firebase_options.dart';
import 'calls/call_models.dart';
part 'fcm_service.g.dart';

@Riverpod(keepAlive: true)
FcmService fcmService(Ref ref) => FcmService();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final offer = _incomingCallOffer(message.data);
  if (offer == null || offer.isExpired) return;
  // A background isolate cannot touch Riverpod. Preserve the offer so the
  // application coordinator can reconcile it on the next foreground frame.
  await PendingCallOfferStore().save(offer);
}

class FcmService {
  FcmService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;
  final FirebaseMessaging _messaging;
  String? _token;
  String? _apnsToken;
  String? _voipPushToken;
  bool _initialized = false;
  final _offers = StreamController<CallOffer>.broadcast();
  final _tokenChanges = StreamController<String?>.broadcast();
  String? get currentToken => _token;
  String? get apnsToken => _apnsToken;
  String? get voipPushToken => _voipPushToken;
  Stream<CallOffer> get incomingCallOffers => _offers.stream;
  Stream<String?> get tokenChanges => _tokenChanges.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      _token = await _messaging.getToken();
      _apnsToken = await _messaging.getAPNSToken();
      _tokenChanges.add(_token);
      _messaging.onTokenRefresh.listen((token) {
        _token = token;
        _tokenChanges.add(token);
        developer.log('FCM token refreshed', name: 'FcmService');
      });
      FirebaseMessaging.onMessage.listen(_handleMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleMessage(initial);
      final pending = await PendingCallOfferStore().take();
      if (pending != null && !pending.isExpired) _offers.add(pending);
      _initialized = true;
    } catch (error) {
      developer.log('FCM unavailable: $error', name: 'FcmService');
    }
  }

  void _handleMessage(RemoteMessage message) {
    final offer = _incomingCallOffer(message.data);
    if (offer != null && !offer.isExpired) {
      _offers.add(offer);
      return;
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
  }

  Future<void> dispose() async {
    await _offers.close();
    await _tokenChanges.close();
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
}
