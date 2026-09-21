import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'call_media_service.dart';
import 'call_models.dart';

/// Which origin serves the bridge page. Asset pages (`flutter-asset://`)
/// are not secure contexts, so WebKit may never settle getUserMedia there.
/// An https URL (e.g. backend-hosted on ngrok) restores normal permission
/// prompts and capture behavior.
enum CallBridgeOrigin { asset, remote }

/// Resolves the bridge origin from configuration. Pure and unit-tested.
/// Only https URLs are accepted as remote — anything else falls back to the
/// bundled asset rather than silently loading an insecure page.
@visibleForTesting
({CallBridgeOrigin origin, String? url}) resolveBridgeOrigin(
    String? configured) {
  final trimmed = (configured ?? '').trim();
  final uri = Uri.tryParse(trimmed);
  if (trimmed.isNotEmpty &&
      uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty) {
    return (origin: CallBridgeOrigin.remote, url: trimmed);
  }
  return (origin: CallBridgeOrigin.asset, url: null);
}

/// Delay honoring the gateway's pending-cleanup window between init
/// attempts. Pure and unit-tested.
@visibleForTesting
Duration settleDelaySince(DateTime? lastInitAt, DateTime now) {
  if (lastInitAt == null) return Duration.zero;
  const cooldown = Duration(seconds: 5);
  final elapsed = now.difference(lastInitAt);
  return elapsed >= cooldown ? Duration.zero : cooldown - elapsed;
}

/// `runJavaScriptReturningResult` returns primitive strings as JSON strings on
/// Android (for example, `"bridge_ok"`), while some WebView implementations
/// return the unquoted primitive. Normalize both representations before
/// comparing bridge probe values.
@visibleForTesting
String normalizeJavaScriptStringResult(Object? result) {
  final text = '$result';
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is String) return decoded;
    } catch (_) {
      // Fall through to the raw result for malformed/non-JSON implementations.
    }
  }
  return text;
}

/// JS-channel name the bridge page posts to. Must match
/// `assets/html/at_call_bridge.html`.
const String atBridgeChannel = 'OmniDeskBridge';

/// Default remote bridge URL hosted on HTTPS.
/// Loading over HTTPS provides a secure context (`window.isSecureContext === true`)
/// required by WebKit for `navigator.mediaDevices.getUserMedia()`.
const String defaultBridgeRemoteUrl =
    'https://unvisual-nedra-depressively.ngrok-free.dev/at_call_bridge.html';

/// Parses one bridge-protocol JSON message into a [CallMediaEvent].
/// Unknown shapes and versions return null (treated as noise, never crash).
CallMediaEvent? parseBridgeEvent(Object? raw, {required String? callSid}) {
  if (raw is! Map) return null;
  final map = raw.map((key, value) => MapEntry('$key', value));
  if (map['v'] != 1) return null;
  final reason = map['reason']?.toString();
  final mediaSessionId = map['sessionId']?.toString();
  final eventCallSid = map['callSid']?.toString() ?? callSid;
  return switch (map['event']) {
    'ready' => CallMediaEvent(
        type: CallMediaEventType.ready,
        mediaSessionId: mediaSessionId,
        callSid: eventCallSid,
      ),
    'incoming' => CallMediaEvent(
        type: CallMediaEventType.incoming,
        mediaSessionId: mediaSessionId,
        callSid: eventCallSid,
      ),
    'ringing' => CallMediaEvent(
        type: CallMediaEventType.ringing,
        mediaSessionId: mediaSessionId,
        callSid: eventCallSid,
      ),
    'connected' || 'callaccepted' => CallMediaEvent(
        type: CallMediaEventType.connected,
        mediaSessionId: mediaSessionId,
        callSid: eventCallSid,
      ),
    'ended' || 'hangup' => CallMediaEvent(
        type: CallMediaEventType.ended,
        reason: reason,
        mediaSessionId: mediaSessionId,
        callSid: eventCallSid,
      ),
    'mic' => CallMediaEvent(
        type: CallMediaEventType.micStatus,
        reason: '${map['mic'] ?? 'unknown'}'
            '${map['detail'] == null ? '' : ' (${map['detail']})'}',
        mediaSessionId: mediaSessionId,
        callSid: eventCallSid,
      ),
    'error' => CallMediaEvent(
        type: CallMediaEventType.error,
        reason: reason,
        mediaSessionId: mediaSessionId,
        callSid: eventCallSid,
      ),
    'heartbeat' || 'page_ready' => null,
    _ => null,
  };
}

/// Experimental media engine: Africa's Talking WebRTC inside a hidden
/// WebView. POC-gated — see Gates 1-5 in the plan. The page is UI-less; all
/// visible call UI remains Flutter, and CallKit/Telecom stay native.
class WebViewCallMediaService implements CallMediaService {
  WebViewCallMediaService({WebViewController? controller})
      : _controller = controller;

  WebViewController? _controller;
  final _events = StreamController<CallMediaEvent>.broadcast();
  StreamSubscription<DateTime>? _watchdog;
  DateTime? _lastHeartbeat;
  Completer<void>? _ready;
  String? _sessionId;
  String? _callSid;
  bool _disposed = false;
  DateTime? _lastInitAt;
  // Last-known bridge state for failure messages. Updated at every step so
  // a timeout names the actual stall point instead of a generic string.
  String _bridgeNote = 'engine never started';
  bool _pageLoaded = false;
  Completer<void>? _pageReady;
  Completer<void>? _attached;
  // Tail of the page's own console (AT client internals, resource errors).
  // Bounded; the latest line is attached to timeout failures.
  final List<String> _consoleTail = <String>[];

  void _log(String message) => developer.log(message, name: 'WebViewMedia');

  bool get hasController => _controller != null;

  /// The host widget calls this exactly once with the live controller.
  void attachController(WebViewController controller) {
    if (_controller != null) return;
    _controller = controller;
    final attached = _attached;
    if (attached != null && !attached.isCompleted) attached.complete();
    controller.addJavaScriptChannel(
      atBridgeChannel,
      onMessageReceived: _onBridgeMessage,
    );
    // Forwards the AT client's internal logs (handshake steps, gateway
    // rejections, token errors) to Dart. Without this, a silent client is
    // indistinguishable from a dead page.
    controller.setOnConsoleMessage(
      (message) => noteConsoleMessage(message.level.name, message.message),
    );
    _log('hidden engine mounted; loading bridge page');
    unawaited(_loadBridgePage(controller));
  }

  /// Mounting the platform WebView is deferred until the first call so it
  /// cannot block Android's initial splash frame.
  Future<void> waitForController() async {
    if (_controller != null) return;
    _attached ??= Completer<void>();
    await _attached!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw const MediaUnavailable(
        'The call engine could not be mounted.',
      ),
    );
  }

  Future<void> _loadBridgePage(WebViewController controller) async {
    final configured = dotenv.env['AT_BRIDGE_URL'] ?? defaultBridgeRemoteUrl;
    final bridgeTarget = resolveBridgeOrigin(configured);
    if (bridgeTarget.origin == CallBridgeOrigin.remote &&
        bridgeTarget.url != null) {
      _log('loading bridge from remote HTTPS: ${bridgeTarget.url}');
      try {
        await controller.loadRequest(
          Uri.parse(bridgeTarget.url!),
          headers: const <String, String>{
            'ngrok-skip-browser-warning': 'true',
          },
        );
        return;
      } catch (error) {
        _log('remote bridge load failed ($error), falling back to asset');
      }
    }
    _log('loading bridge from bundled Flutter asset');
    await controller.loadFlutterAsset('assets/html/at_call_bridge.html');
  }

  /// Called by the host widget for every console line the bridge page emits
  /// (AT client internals, JS exceptions, failed subresources). This is how
  /// gateway/token rejections with no bridge event still reach Dart logs.
  void noteConsoleMessage(String level, String text) {
    final line = text.trim();
    if (line.isEmpty) return;
    _log('page console [$level]: $line');
    _consoleTail.add(line);
    while (_consoleTail.length > 3) {
      _consoleTail.removeAt(0);
    }
  }

  String get _consoleTailNote => _consoleTail.isEmpty
      ? 'no page console output'
      : _consoleTail.join(' | ');

  @visibleForTesting
  List<String> get consoleTailForTest => List.unmodifiable(_consoleTail);

  /// Called by the host widget's navigation delegate.
  void notePageFinished() {
    _pageLoaded = true;
    _bridgeNote = 'bridge page loaded, no client initialized yet';
    final ready = _pageReady;
    if (ready != null && !ready.isCompleted) ready.complete();
    _log('bridge page loaded');
  }

  /// Called by the host widget's navigation delegate.
  void notePageError(String description) {
    _pageLoaded = false;
    _bridgeNote = 'bridge page failed to load: $description';
    _log('bridge page load FAILED: $description');
  }

  @override
  Stream<CallMediaEvent> get events => _events.stream;

  @override
  Future<String> initialize(CallMediaConfig config,
      {CallId? incomingCallId}) async {
    await waitForController();
    final token = config.webrtcToken;
    if (token == null || token.isEmpty) {
      throw const MediaUnavailable(
        'The call service did not provide a WebRTC capability token.',
      );
    }
    final microphone = await Permission.microphone.request();
    if (!microphone.isGranted) {
      throw const MediaUnavailable(
        'Microphone access is required to place calls.',
      );
    }
    final controller = _controller;
    if (controller == null) {
      throw const MediaUnavailable(
        'The hidden call engine is not mounted yet.',
      );
    }
    _callSid = null;
    _ready = Completer<void>();
    _consoleTail.clear();
    _sessionId = 'webview-media-${DateTime.now().microsecondsSinceEpoch}';
    _bridgeNote = 'starting client init';
    // Fingerprint (not the secret) so runs can be correlated if the backend
    // rotates tokens between attempts. Capability tokens live up to 24h
    // (`lifeTimeSec: "86400"` per AT docs and the backend's `expires_in`),
    // so a missing `ready` is never a TTL race against setup latency.
    _log('init token len=${token.length} '
        'prefix=${token.length <= 6 ? token : token.substring(0, 6)} '
        'gateway=${config.webrtcGatewayUrl}');
    // NOTE on gateway URL: africastalking-client@1.0.5 hardcodes
    // wss://webrtc.africastalking.com/connect internally. A backend-provided
    // URL (e.g. wss://webrtc.africastalking.com:4443) cannot be forwarded to
    // the JS SDK — it is only used by the probe below for diagnostics.
    // If the backend returns a non-standard gateway, the probe will stall
    // (open, no frame) while the JS client connects to the correct default.
    // Fix: ensure the backend returns the standard /connect URL, or bundle
    // a patched SDK that accepts a 'server' constructor option.
    //
    // Diagnostic only — fire-and-forget so probing never delays init().
    // Resume-stale sockets can also raise outside the probe's own guards
    // (seen as SocketException ETIMEDOUT after app resume).
    // The JavaScript SDK is the sole owner of its provider WebSocket. A
    // second diagnostic socket using the same capability can race the
    // provider's registration or consume a one-client session slot.
    try {
      // Pristine module state per init (field-verified failure mode):
      // re-`new Client()` on one long-lived page inherits tainted gateway
      // state and can never emit `ready` again, so every setup starts from
      // a freshly reloaded page. Plus 5s settle: the gateway can hold the
      // previous clientName in pending-cleanup and reject an immediate
      // re-register.
      final settle = settleDelaySince(_lastInitAt, DateTime.now());
      if (settle > Duration.zero) {
        _log('settling ${settle.inMilliseconds}ms since last init attempt');
        await Future<void>.delayed(settle);
      }
      _lastInitAt = DateTime.now();
      _pageLoaded = false;
      _pageReady = Completer<void>();
      try {
        await _loadBridgePage(controller);
      } catch (error) {
        _log('bridge reload failed: $error');
      }
      // The hidden view may not have finished its (re)load (cold start,
      // slow asset read). Wait briefly for it instead of probing a blank
      // page and misreporting `bridge_missing`.
      if (!_pageLoaded) {
        _log('waiting for bridge page load');
        _pageReady ??= Completer<void>();
        try {
          await _pageReady!.future.timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw const MediaUnavailable(
              'The hidden call engine page did not finish loading.',
            ),
          );
        } finally {
          _pageReady = null;
        }
        _log('bridge page load confirmed');
      }
      // Fail fast when the page itself never loaded: otherwise the init call
      // vanishes into a blank WebView and the 20s ready-timeout is the only
      // (generic) signal.
      final probe = await controller
          .runJavaScriptReturningResult(
            '(typeof window.OmniDesk !== "undefined" && '
            'typeof window.OmniDesk.call !== "undefined") ? '
            '"bridge_ok" : "bridge_missing"',
          )
          .timeout(const Duration(seconds: 10));
      _log('bridge probe: $probe (pageLoaded=$_pageLoaded)');
      final probeValue = normalizeJavaScriptStringResult(probe);
      if (probeValue != 'bridge_ok') {
        _bridgeNote = 'bridge page not loaded (probe=$probe)';
        throw MediaUnavailable(
          'The hidden call engine page did not load ($probe). '
          'Check the app bundle assets and WebView storage.',
        );
      }
      await controller.runJavaScript('''
        window.OmniDesk.call.init({
          token: ${jsonEncode(token)},
          gatewayUrl: ${jsonEncode(config.webrtcGatewayUrl)},
          clientName: ${jsonEncode(config.webrtcClientName)},
          sessionId: ${jsonEncode(_sessionId)},
        });
      ''').timeout(const Duration(seconds: 10));
      _bridgeNote = 'client init sent, waiting for AT ready event';
      _log('client init sent; awaiting AT ready');
      await _logBridgeStatus('post-init');
      await _ready!.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () async {
          // One last snapshot so the failure names the stall point instead
          // of just saying "timed out".
          await _logBridgeStatus('timeout');
          throw MediaUnavailable(
            'The WebRTC engine timed out ($_bridgeNote; '
            'page console: $_consoleTailNote).',
          );
        },
      );
      _log('engine ready; SDK owns the first microphone request during dial');
    } finally {
      _ready = null;
    }
    return _sessionId!;
  }

  /// Queries the bridge's self-reported state and logs it. This is the
  /// discriminator when the client goes silent: it tells CDN-load failure
  /// (`atLib` undefined) apart from a constructed-but-stalled client
  /// (gateway handshake or media-capture stall).
  Future<void> _logBridgeStatus(String tag) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final status = await controller
          .runJavaScriptReturningResult(
            'JSON.stringify(window.OmniDesk.call.status())',
          )
          .timeout(const Duration(seconds: 5));
      _log('bridge status [$tag]: $status');
    } catch (error) {
      _log('bridge status [$tag] unreadable: $error');
    }
  }

  @override
  Future<String> dial({
    required String callSid,
    required String phoneNumber,
    String? sipTargetUri,
  }) async {
    final controller = _requireController();
    _callSid = callSid;
    _sessionId ??= 'webview-media-${DateTime.now().microsecondsSinceEpoch}';
    _log('dial $phoneNumber (callSid=$callSid)');
    _watchDial(callSid);
    await controller.runJavaScript(
      'window.OmniDesk.call.dial(${jsonEncode(phoneNumber)}, ${jsonEncode(callSid)})',
    );
    return _sessionId!;
  }

  /// Dial watchdog: the AT client's offer path logs to no-ops, so a dial
  /// that never produces ringing/connected/ended would otherwise sit on
  /// "calling" forever. Any terminal event for this call cancels the watch.
  Timer? _dialWatchdog;
  String? _dialWatchCallSid;

  void _watchDial(String callSid) {
    _dialWatchdog?.cancel();
    _dialWatchCallSid = callSid;
    _dialWatchdog = Timer(const Duration(seconds: 20), () {
      _dialWatchdog = null;
      _dialWatchCallSid = null;
      _log('dial watchdog fired with no provider progress for $callSid');
      _events.add(CallMediaEvent(
        type: CallMediaEventType.error,
        reason: 'The provider did not answer the dial request for $callSid '
            '(no ringing or refusal within 20s).',
        mediaSessionId: _sessionId,
        callSid: callSid,
      ));
    });
  }

  void _cancelDialWatch(String? callSid) {
    if (callSid != null &&
        _dialWatchCallSid != null &&
        callSid != _dialWatchCallSid) {
      return;
    }
    _dialWatchdog?.cancel();
    _dialWatchdog = null;
    _dialWatchCallSid = null;
  }

  @override
  Future<void> answerIncoming({required String callSid}) async {
    final controller = _requireController();
    _callSid = callSid;
    _log('answer incoming (callSid=$callSid)');
    await controller.runJavaScript(
      'window.OmniDesk.call.answer(${jsonEncode(callSid)})',
    );
  }

  @override
  Future<void> endMedia(String mediaSessionId) async {
    _stopWatchdog();
    _cancelDialWatch(null);
    try {
      await _controller?.runJavaScript('window.OmniDesk.call.hangup()');
    } catch (_) {
      // Hangup is best-effort; the page may already be gone.
    }
  }

  @override
  Future<void> setMuted(bool enabled) async {
    await _controller?.runJavaScript(
        'window.OmniDesk.call.mute(${enabled ? 'true' : 'false'})');
  }

  @override
  Future<void> setHeld(bool enabled) async {
    await _controller?.runJavaScript(
        'window.OmniDesk.call.hold(${enabled ? 'true' : 'false'})');
  }

  @override
  Future<void> sendDtmf(String digit) async {
    await _controller
        ?.runJavaScript('window.OmniDesk.call.dtmf(${jsonEncode(digit)})');
  }

  WebViewController _requireController() {
    final controller = _controller;
    if (controller == null) {
      throw const MediaUnavailable(
        'The hidden call engine is not mounted yet.',
      );
    }
    return controller;
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    if (_disposed) return;
    Object? decoded;
    try {
      decoded = jsonDecode(message.message);
    } catch (_) {
      return;
    }
    if (decoded is Map &&
        (decoded['event'] == 'heartbeat' || decoded['event'] == 'page_ready')) {
      if (decoded['event'] == 'heartbeat') {
        _lastHeartbeat = DateTime.now();
      }
      return;
    }
    if (decoded is Map && decoded['event'] == 'ws_log') {
      _log('[bridge ws] ${decoded['data']}');
      return;
    }
    final event = parseBridgeEvent(decoded, callSid: _callSid);
    if (event == null) {
      _log('bridge: unrecognized message ${message.message}');
      return;
    }
    // A deployed pre-v2 bridge has no sessionId. Accept it temporarily so
    // rollout does not brick existing installations, but v2+ events must
    // always match this page generation.
    if (event.mediaSessionId != null && event.mediaSessionId != _sessionId) {
      _log('ignored stale bridge event for session ${event.mediaSessionId}');
      return;
    }
    if (_callSid != null &&
        event.callSid != null &&
        event.callSid != _callSid) {
      _log('ignored bridge event for another call');
      return;
    }
    _bridgeNote = 'last bridge event: ${event.type}'
        '${event.reason == null ? '' : ' (${event.reason})'}';
    _log('bridge event: ${event.type}'
        '${event.reason == null ? '' : ' reason=${event.reason}'}');
    if (event.type == CallMediaEventType.ready) {
      final ready = _ready;
      if (ready != null && !ready.isCompleted) ready.complete();
    }
    if (event.type == CallMediaEventType.error) {
      final ready = _ready;
      if (ready != null && !ready.isCompleted) {
        ready.completeError(MediaUnavailable(
          event.reason ?? 'The WebRTC engine reported an error.',
        ));
      }
    }
    if (event.type == CallMediaEventType.connected) _startWatchdog();
    if (event.type == CallMediaEventType.ended) _stopWatchdog();
    if (event.type == CallMediaEventType.ringing ||
        event.type == CallMediaEventType.connected ||
        event.type == CallMediaEventType.ended ||
        event.type == CallMediaEventType.error) {
      _cancelDialWatch(_callSid);
    }
    _events.add(event);
  }

  /// Gate 5 enforcement: webview_flutter exposes no WebKit process-death
  /// callback, so liveness is proven by JS heartbeats instead. Silence past
  /// the deadline is surfaced as fatal — never silent-ACTIVE.
  void _startWatchdog() {
    _stopWatchdog();
    _lastHeartbeat = DateTime.now();
    _watchdog =
        Stream.periodic(const Duration(seconds: 5), (_) => DateTime.now())
            .listen((now) {
      final last = _lastHeartbeat;
      if (last != null && now.difference(last) > const Duration(seconds: 20)) {
        _stopWatchdog();
        _events.add(const CallMediaEvent(
          type: CallMediaEventType.processTerminated,
          reason: 'The hidden call engine stopped responding.',
        ));
      }
    });
  }

  void _stopWatchdog() {
    unawaited(_watchdog?.cancel());
    _watchdog = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _stopWatchdog();
    _cancelDialWatch(null);
    await _events.close();
  }
}

/// Offscreen host for the POC media engine. Mount once near the app root.
/// Full-screen and transparent, layered BEHIND the Flutter UI: visually
/// hidden and untouchable, but layout-visible to WebKit. A 1px hidden view
/// was tried first and WebKit never settled getUserMedia in it (no prompt,
/// no rejection — the exact public failure mode for hidden WKWebViews).
/// If capture still hangs here, the next step is an https-hosted page.
class HiddenCallWebView extends ConsumerStatefulWidget {
  const HiddenCallWebView({super.key});

  @override
  ConsumerState<HiddenCallWebView> createState() => _HiddenCallWebViewState();
}

class _HiddenCallWebViewState extends ConsumerState<HiddenCallWebView> {
  late final WebViewController _controller = _createController();

  static WebViewController _createController() {
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      // Headless audio must never wait for a tap that never comes.
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const {},
      );
    }
    final controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (WebViewPermissionRequest request) async {
        developer.log(
          'WebView permission request: ${request.types}',
          name: 'WebViewMedia',
        );
        if (request.types.contains(WebViewPermissionResourceType.microphone)) {
          final micStatus = await Permission.microphone.status;
          if (micStatus.isGranted) {
            await request.grant();
            developer.log(
              'WebView microphone capture granted',
              name: 'WebViewMedia',
            );
          } else {
            await request.deny();
            developer.log(
              'WebView microphone capture denied (OS permission not granted)',
              name: 'WebViewMedia',
            );
          }
          return;
        }
        await request.deny();
      },
    );
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..enableZoom(false);
    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }
    return controller;
  }

  @override
  void initState() {
    super.initState();
    // Channel + bridge page belong to the service; the widget only owns the
    // platform view lifetime (routes, lock screen, app foreground/background).
    final service = ref.read(webViewCallMediaServiceProvider);
    _controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) {
        final url = request.url;
        if (url == 'about:blank' ||
            url.contains('at_call_bridge.html') ||
            url.contains('ngrok-free.dev')) {
          return NavigationDecision.navigate;
        }
        return NavigationDecision.prevent;
      },
      onPageFinished: (_) => service.notePageFinished(),
      onWebResourceError: (error) => service.notePageError(
        '${error.errorType} ${error.description}'.trim(),
      ),
    ));
    // Install navigation observation before starting the initial load;
    // otherwise a fast cached bridge can finish before page readiness is
    // observed and falsely time out during the first call.
    service.attachController(_controller);
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.01,
            child: SizedBox.expand(
              child: WebViewWidget(controller: _controller),
            ),
          ),
        ),
      );
}

final webViewCallMediaServiceProvider =
    Provider<WebViewCallMediaService>((ref) {
  final service = WebViewCallMediaService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
