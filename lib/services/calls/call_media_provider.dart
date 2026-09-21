import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_media_service.dart';
import 'call_models.dart';
import 'webview_call_media_service.dart';

/// Production media selection. Tests can override this with a deterministic
/// transport-neutral fake without coupling the session state machine to a
/// hidden WebView implementation.
final callMediaServiceProvider = Provider<CallMediaService>(
  (ref) => ref.watch(webViewCallMediaServiceProvider),
);

/// Picks the media engine for one call from what the backend actually
/// returned — not from a hardcoded default.
///
/// Africa's Talking's supported mobile media contract is WebRTC. The legacy
/// SIP experiment is intentionally not a selectable fallback: attempting it
/// after a WebRTC config has been issued creates orphan backend calls.
bool usesSupportedWebViewMedia(CallMediaConfig config) =>
    config.transport == 'webrtc' && config.canUseWebRtc;
