import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_media_service.dart';
import 'call_models.dart';
import 'webview_call_media_service.dart';

/// POC switch backing the media-engine seam.
///
/// `false` (default) keeps the frozen Baresip track as the live engine;
/// flip to `true` to route media through the hidden WebView AT client.
/// Delete this flag (and the losing implementation) when Gates 1-5 decide.
class WebViewMediaSwitch extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool enabled) {
    if (state != enabled) state = enabled;
  }
}

final useWebViewMediaProvider =
    NotifierProvider<WebViewMediaSwitch, bool>(WebViewMediaSwitch.new);

/// The session controller depends only on this — never on a concrete engine.
final callMediaServiceProvider = Provider<CallMediaService>((ref) {
  final useWebView = ref.watch(useWebViewMediaProvider);
  if (useWebView) return ref.watch(webViewCallMediaServiceProvider);
  return ref.watch(baresipCallMediaServiceProvider);
});

/// Picks the media engine for one call from what the backend actually
/// returned — not from a hardcoded default.
///
/// Backend reality (Sept 2026): `media-config` may come back `transport:
/// "webrtc"` with no `sip` block at all. Sending that to the SIP stack fails
/// inside the native adapter guard with an opaque error, which is exactly
/// the "Unable to set up this call" outage. [forceWebView] is the manual
/// POC override and wins over everything.
bool useWebViewEngine({
  required bool forceWebView,
  required CallMediaConfig config,
}) {
  if (forceWebView) return true;
  if (config.transport == 'webrtc' && config.canUseWebRtc) return true;
  return false;
}
