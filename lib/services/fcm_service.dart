import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'fcm_service.g.dart';

@Riverpod(keepAlive: true)
FcmService fcmService(Ref ref) => FcmService();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  developer.log('Background FCM message: ${message.messageId}',
      name: 'FcmService');
}

class FcmService {
  FcmService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;
  final FirebaseMessaging _messaging;
  String? _token;
  bool _initialized = false;
  String? get currentToken => _token;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      _token = await _messaging.getToken();
      _messaging.onTokenRefresh.listen((token) {
        _token = token;
        developer.log('FCM token refreshed', name: 'FcmService');
      });
      FirebaseMessaging.onMessage.listen(_logMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_logMessage);
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _logMessage(initial);
      _initialized = true;
    } catch (error) {
      developer.log('FCM unavailable: $error', name: 'FcmService');
    }
  }

  void _logMessage(RemoteMessage message) =>
      developer.log('FCM message: ${message.messageId}', name: 'FcmService');
  Future<void> clearToken() async {
    _token = null;
  }
}
