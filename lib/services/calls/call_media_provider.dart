import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import 'call_media_service.dart';
import 'call_models.dart';
import 'ios_native_call_media_service.dart';
import 'android_native_call_media_service.dart';
import 'webview_call_media_service.dart';

/// Build-time iOS media selector. Native AT media is the current iOS default;
/// pass `--dart-define=USE_IOS_NATIVE_AT_MEDIA=false` for WebView fallback.
/// Android always keeps its existing WebView implementation.
const bool useIosNativeAtMedia = bool.fromEnvironment(
  'USE_IOS_NATIVE_AT_MEDIA',
  defaultValue: true,
);

/// Android native AT transport is the current default. Pass
/// `--dart-define=USE_ANDROID_NATIVE_AT_MEDIA=false` to select the existing
/// WebView implementation while debugging or validating a rollback.
const bool useAndroidNativeAtMedia = bool.fromEnvironment(
  'USE_ANDROID_NATIVE_AT_MEDIA',
  defaultValue: true,
);

bool shouldUseAndroidNativeAtMedia({
  required TargetPlatform platform,
  required bool enabled,
}) =>
    platform == TargetPlatform.android && enabled;

/// Production media selection. Tests can override this with a deterministic
/// transport-neutral fake without coupling the session state machine to a
/// hidden WebView implementation.
final callMediaServiceProvider = Provider<CallMediaService>(
  (ref) {
    if (defaultTargetPlatform == TargetPlatform.iOS && useIosNativeAtMedia) {
      debugPrint('[CallMedia] selected=ios_native_at');
      final service = IOSNativeCallMediaService();
      ref.onDispose(service.dispose);
      return service;
    }
    if (shouldUseAndroidNativeAtMedia(
      platform: defaultTargetPlatform,
      enabled: useAndroidNativeAtMedia,
    )) {
      debugPrint('[CallMedia] selected=android_native_at');
      final service = AndroidNativeCallMediaService();
      ref.onDispose(service.dispose);
      return service;
    }
    return ref.watch(webViewCallMediaServiceProvider);
  },
);

/// Picks the media engine for one call from what the backend actually
/// returned — not from a hardcoded default.
///
/// Africa's Talking's supported mobile media contract is WebRTC. The legacy
/// SIP experiment is intentionally not a selectable fallback: attempting it
/// after a WebRTC config has been issued creates orphan backend calls.
bool usesSupportedWebViewMedia(CallMediaConfig config) =>
    config.transport == 'webrtc' && config.canUseWebRtc;
