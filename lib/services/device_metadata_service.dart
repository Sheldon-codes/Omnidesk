import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_metadata_service.g.dart';

@Riverpod(keepAlive: true)
DeviceMetadataService deviceMetadataService(Ref ref) => DeviceMetadataService();

class DeviceMetadataService {
  DeviceMetadataService({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();
  final DeviceInfoPlugin _deviceInfo;
  Future<Map<String, String>> buildHeaders() async {
    final package = await PackageInfo.fromPlatform();
    return {
      'X-Device-Name': await _deviceName(),
      'X-Device-OS': _platformName,
      'X-App-Version': package.version,
      'X-App-Build': package.buildNumber
    };
  }

  String get _platformName => kIsWeb ? 'web' : Platform.operatingSystem;
  Future<String> _deviceName() async {
    try {
      if (kIsWeb) return 'Web';
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return '${info.brand} ${info.model}';
      }
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return '${info.name} ${info.model}';
      }
    } catch (_) {}
    return 'Unknown';
  }
}
