import 'dart:math';
import 'dart:developer' as developer;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../fcm_service.dart';
import 'call_api.dart';
import 'native_call_service.dart';

/// Owns a random, app-scoped installation identity. It is intentionally not a
/// device identifier (IMEI/IDFV/Android ID) so an uninstall creates a new
/// installation and the backend can revoke it independently.
class DeviceInstallationService {
  DeviceInstallationService({
    FlutterSecureStorage? storage,
    DeviceInfoPlugin? deviceInfo,
    Future<PackageInfo> Function()? packageInfo,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
        _packageInfo = packageInfo ?? PackageInfo.fromPlatform;

  static const _installationIdKey = 'omnidesk_call_installation_id';
  final FlutterSecureStorage _storage;
  final DeviceInfoPlugin _deviceInfo;
  final Future<PackageInfo> Function() _packageInfo;

  Future<String> getOrCreateInstallationId() async {
    final existing = await _storage.read(key: _installationIdKey);
    if (existing != null && _isUuid(existing)) return existing;
    final created = _newUuid();
    await _storage.write(key: _installationIdKey, value: created);
    return created;
  }

  Future<DeviceRegistration> registration({
    required String installationId,
    required String? fcmToken,
    String? apnsToken,
    String? voipPushToken,
  }) async {
    final package = await _packageInfo();
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'unsupported',
    };
    return DeviceRegistration(
      installationId: installationId,
      platform: platform,
      appVersion: '${package.version}+${package.buildNumber}',
      deviceName: await _deviceName(),
      voipCapable: platform == 'ios' || platform == 'android',
      fcmToken: fcmToken,
      apnsToken: apnsToken,
      voipPushToken: voipPushToken,
    );
  }

  Future<String> _deviceName() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await _deviceInfo.iosInfo;
        return '${info.utsname.machine} (${info.systemName} ${info.systemVersion})';
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await _deviceInfo.androidInfo;
        return '${info.manufacturer} ${info.model}'.trim();
      }
    } catch (_) {
      // Device presentation is metadata only and must never block call setup.
    }
    return defaultTargetPlatform.name;
  }

  static bool _isUuid(String value) => RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(value);

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final text = bytes.map(hex).join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
        '${text.substring(12, 16)}-${text.substring(16, 20)}-'
        '${text.substring(20)}';
  }
}

final deviceInstallationServiceProvider =
    Provider<DeviceInstallationService>((ref) => DeviceInstallationService());

/// Auth lifecycle-facing registry. Registration is idempotent at the server
/// and repeated only when the token/version changes or a fresh login occurs.
class DeviceRegistry {
  DeviceRegistry({
    required CallApi api,
    required DeviceInstallationService installation,
    required FcmService fcm,
    required NativeCallService native,
  })  : _api = api,
        _installation = installation,
        _fcm = fcm,
        _native = native;

  final CallApi _api;
  final DeviceInstallationService _installation;
  final FcmService _fcm;
  final NativeCallService _native;
  String? _registeredFingerprint;

  Future<String> installationId() => _installation.getOrCreateInstallationId();

  Future<void> register() async {
    final id = await installationId();
    // Android owns `MESSAGING_EVENT` natively so Firebase's Flutter plugin
    // is not guaranteed to receive every token callback. The native service
    // persists the same FCM token, which is the authoritative fallback here.
    // It is deliberately sent as `fcm_token` on Android, never as an iOS
    // VoIP token.
    final nativePushToken = await _native.readNativePushToken();
    final nativeFcmToken = defaultTargetPlatform == TargetPlatform.android
        ? nativePushToken
        : null;
    final fcmToken = _fcm.currentToken ?? nativeFcmToken;
    final registration = await _installation.registration(
      installationId: id,
      fcmToken: fcmToken,
      apnsToken: _fcm.apnsToken,
      voipPushToken: _fcm.voipPushToken ??
          (defaultTargetPlatform == TargetPlatform.iOS
              ? nativePushToken
              : null),
    );
    // The server can only route a mobile offer after it has a platform-native
    // wake token. Avoid registering a misleading, non-routable installation.
    if (registration.platform == 'unsupported' ||
        (registration.platform == 'android' &&
            (registration.fcmToken == null ||
                registration.fcmToken!.isEmpty)) ||
        (registration.platform == 'ios' &&
            (registration.voipPushToken == null ||
                registration.voipPushToken!.isEmpty))) {
      developer.log(
        'Device registration skipped: platform=${registration.platform}, '
        'fcmTokenAvailable=${registration.fcmToken?.isNotEmpty == true}, '
        'voipTokenAvailable=${registration.voipPushToken?.isNotEmpty == true}.',
        name: 'PushRegistration',
      );
      return;
    }
    final fingerprint = '${registration.platform}|${registration.appVersion}|'
        '${registration.fcmToken}|${registration.apnsToken}|${registration.voipPushToken}';
    if (fingerprint == _registeredFingerprint) {
      developer.log(
        'Device registration already current for ${registration.platform}.',
        name: 'PushRegistration',
      );
      return;
    }
    developer.log(
      'Registering device with backend: platform=${registration.platform}, '
      'fcmTokenAvailable=${registration.fcmToken?.isNotEmpty == true}, '
      'voipTokenAvailable=${registration.voipPushToken?.isNotEmpty == true}.',
      name: 'PushRegistration',
    );
    try {
      await _api.registerDevice(registration);
      _registeredFingerprint = fingerprint;
      developer.log(
        'Device registration completed for ${registration.platform}.',
        name: 'PushRegistration',
      );
    } catch (error) {
      developer.log(
        'Device registration failed: ${error.runtimeType}.',
        name: 'PushRegistration',
      );
      rethrow;
    }
  }

  Future<void> unregister() async {
    final id = await installationId();
    try {
      await _api.unregisterDevice(id);
    } finally {
      _registeredFingerprint = null;
    }
  }

  void invalidateRegistration() => _registeredFingerprint = null;
}

final deviceRegistryProvider = Provider<DeviceRegistry>((ref) => DeviceRegistry(
      api: ref.read(callApiProvider),
      installation: ref.read(deviceInstallationServiceProvider),
      fcm: ref.read(fcmServiceProvider),
      native: ref.read(nativeCallServiceProvider),
    ));

/// Small dependency used by the session controller; keeping this separate
/// makes lifecycle operations testable without a platform secure-storage mock.
final callInstallationIdProvider = Provider<Future<String> Function()>(
  (ref) => ref.read(deviceRegistryProvider).installationId,
);
