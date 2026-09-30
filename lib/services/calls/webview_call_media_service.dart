import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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

// A WebView process can be cold-started while Android is restoring the app
// after a Telecom action. Twenty seconds proved too short on slower devices
// and congested networks, but this must remain bounded: a permanently stuck
// navigation must never leave an outgoing call "Connecting" forever.
// An incoming provider offer has a bounded lifetime. On Android a stalled
// HTTPS navigation must fall back to the bundled shell before that offer
// expires. Android WebView reports the bundled page as a secure context and
// has already been validated with the AT engine. iOS retains its longer HTTPS
// window because WebKit's local-asset microphone semantics differ.
Duration get _remoteBridgeLoadTimeout =>
    defaultTargetPlatform == TargetPlatform.android
        ? const Duration(seconds: 8)
        : const Duration(seconds: 35);
const Duration _assetBridgeLoadTimeout = Duration(seconds: 20);
const Duration _sdkInjectionTimeout = Duration(seconds: 12);
const Duration _bridgeHandshakeTimeout = Duration(seconds: 8);
const String _expectedBridgeVersion = '2.0.0';
const String _expectedSdkVersion = '1.0.7';

/// Android's bundled Flutter asset is a secure WebView context on supported
/// Android System WebView builds, as verified by the bridge diagnostics. Keep
/// the complete Android document/SDK/adapter triplet in the APK so a call is
/// never coupled to the availability or deployment state of the hosted shell.
/// iOS deliberately retains HTTPS until WebKit local-asset capture has been
/// validated independently.
bool get _usesBundledBridgeShell =>
    defaultTargetPlatform == TargetPlatform.android;

/// Sanitized bridge lifecycle information. This is intentionally separate
/// from [CallMediaEvent]: diagnostics must not drive call state or rebuild the
/// call UI, but they are useful for timing and provider failure analysis.
class CallBridgeDiagnostic {
  const CallBridgeDiagnostic({
    required this.phase,
    required this.level,
    required this.timestamp,
    this.details = const <String, Object?>{},
  });

  final String phase;
  final String level;
  final DateTime timestamp;
  final Map<String, Object?> details;
}

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
  final _diagnostics = StreamController<CallBridgeDiagnostic>.broadcast();
  StreamSubscription<DateTime>? _watchdog;
  DateTime? _lastHeartbeat;
  Completer<void>? _ready;
  String? _sessionId;
  String? _callSid;
  bool _disposed = false;
  DateTime? _lastInitAt;
  bool _engineReady = false;
  bool _clientInUse = false;
  // A prewarm may share initialization with a real call.  This monotonic
  // reservation prevents the prewarm completion from returning that client
  // to standby after a caller has already claimed it.
  int _clientReservation = 0;
  String? _readyConfigKey;
  DateTime? _standbyCredentialExpiresAt;
  String? _lastInitializationPath;
  Future<String>? _initialization;
  // Auth/workspace refreshes may invalidate standby while the provider is
  // still emitting its first `ready`. Clearing _sessionId mid-initialization
  // falsely reports that a healthy engine was replaced.
  bool _invalidateAfterInitialization = false;
  // Last-known bridge state for failure messages. Updated at every step so
  // a timeout names the actual stall point instead of a generic string.
  String _bridgeNote = 'engine never started';
  bool _pageLoaded = false;
  Completer<void>? _pageReady;
  Future<void>? _bridgeLoad;
  int _bridgeGeneration = 0;
  int _injectedGeneration = -1;
  bool _bridgePrimed = false;
  bool _bridgeIsBeingConsumed = false;
  Completer<void>? _attached;
  // Tail of the page's own console (AT client internals, resource errors).
  // Bounded; the latest line is attached to timeout failures.
  final List<String> _consoleTail = <String>[];
  final List<String> _diagnosticTail = <String>[];

  static Future<String>? _sdkSource;
  static Future<String>? _bridgeSource;

  void _log(String message) => developer.log(message, name: 'WebViewMedia');

  String _maskedPhone(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 4) return '[REDACTED]';
    return '***${compact.substring(compact.length - 4)}';
  }

  bool get hasController => _controller != null;

  bool get isStandbyReady => _engineReady && !_clientInUse;

  /// Reads only the bridge's boolean attachment state. An unreadable bridge is
  /// unknown rather than idle: a new call must not tear down a possible
  /// background call merely to recover a leaked local reservation.
  Future<bool?> _bridgeHasAttachedCall() async {
    final controller = _controller;
    if (controller == null || !_pageLoaded) return null;
    try {
      final raw = await controller
          .runJavaScriptReturningResult(
            'window.OmniDesk && window.OmniDesk.call '
            '? JSON.stringify(window.OmniDesk.call.status()) : ""',
          )
          .timeout(const Duration(milliseconds: 750));
      final decoded = jsonDecode(normalizeJavaScriptStringResult(raw));
      if (decoded is! Map || decoded['bridge'] != true) return null;
      if (!decoded.containsKey('callAttached')) return null;
      return decoded['callAttached'] == true;
    } catch (error) {
      _log('outbound admission bridge status unreadable: '
          '${error.runtimeType}');
      return null;
    }
  }

  Future<void> _releaseMediaLease({required String reason}) async {
    _stopWatchdog();
    _cancelDialWatch(null);
    try {
      final controller = _controller;
      if (controller != null) {
        await controller
            .runJavaScript('window.OmniDesk.call.hangup()')
            .timeout(const Duration(milliseconds: 500));
      }
    } catch (_) {
      // A reclaimed/navigated WebView must not poison subsequent calls.
    }
    _clientInUse = false;
    _callSid = null;
    _sessionId = null;
    _log('media lease released reason=$reason');
  }

  @override
  Future<void> prepareForNewOutboundCall() async {
    final initialization = _initialization;
    if (initialization != null) {
      // An immediate second call commonly arrives while the previous call's
      // post-terminal standby warmup is still connecting. Join that one
      // generation rather than creating a second page navigation.
      _log('outbound admission joining in-flight standby initialization');
      try {
        await initialization.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        throw const MediaUnavailable(
          'The call service is still preparing. Please try again in a moment.',
        );
      }
    }
    if (!_clientInUse) return;

    final attached = await _bridgeHasAttachedCall();
    if (attached == true) {
      throw const MediaUnavailable(
        'Another OmniDesk call is still active. End it before starting a new call.',
      );
    }
    if (attached == null) {
      throw const MediaUnavailable(
        'The previous call is still closing. Please try again in a moment.',
      );
    }

    // The bridge explicitly reports no attached call. Preserve the healthy
    // standby client; initialize() will still run its normal health probe.
    await _releaseMediaLease(reason: 'verified_idle_stale_reservation');
  }

  @override
  Future<void> abandonMediaPreparation() =>
      _releaseMediaLease(reason: 'setup_terminated_before_session_id');

  /// Connection path used by the most recent initialization. It is consumed
  /// by call telemetry, never by the UI state machine.
  String? get lastInitializationPath => _lastInitializationPath;

  Stream<CallBridgeDiagnostic> get diagnostics => _diagnostics.stream;

  /// Invalidates an idle client after auth/workspace/network changes. Active
  /// calls are deliberately untouched; terminal teardown owns those.
  Future<void> invalidateStandby() async {
    if (_clientInUse) return;
    if (_initialization != null) {
      _invalidateAfterInitialization = true;
      _log('standby invalidation deferred until initialization is idle');
      return;
    }
    await _clearIdleStandby(reason: 'auth/workspace/network invalidation');
  }

  Future<void> _clearIdleStandby({required String reason}) async {
    if (_clientInUse) return;
    _engineReady = false;
    _readyConfigKey = null;
    _standbyCredentialExpiresAt = null;
    _lastInitializationPath = null;
    _bridgePrimed = false;
    _lastHeartbeat = null;
    _sessionId = null;
    _callSid = null;
    try {
      await _controller?.runJavaScript('window.OmniDesk.call.hangup()');
    } catch (_) {
      // The page may already have been reclaimed by the platform.
    }
    _log('standby invalidated reason=$reason');
  }

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
    // Navigation is deliberately deferred to initialize(). Starting a load
    // here and another during initialize used to create two concurrent
    // navigations on a cold WebView, making page-finished nondeterministic.
    _log('hidden engine mounted; bridge load deferred until call setup');
  }

  /// The platform WebView is mounted only after the authenticated first frame
  /// (or during an urgent call setup), so it cannot block Android's splash.
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

  /// Starts loading the HTML/JS shell before Answer without creating an AT
  /// client or asking for microphone access. It removes the cold WebView/CDN
  /// hop from the post-accept critical path while keeping the actual media
  /// lifecycle exactly where it belongs: after backend acceptance.
  Future<void> prewarmBridge() async {
    try {
      await waitForController();
      final controller = _requireController();
      // Page navigation destroys the JavaScript heap. A rebuilt hidden host
      // must never replace a client which is currently initializing or in a
      // real call; warmup is optional while that work is authoritative.
      if (_initialization != null || _clientInUse) {
        _log(
            'bridge prewarm deferred: initialization=${_initialization != null} '
            'clientInUse=$_clientInUse');
        return;
      }
      if (_bridgePrimed && _pageLoaded) return;
      // A document navigation destroys an otherwise reusable registered AT
      // client. Do not reload merely because a lifecycle callback asked for
      // prewarm again; the normal initialize path will perform its own health
      // check before claiming this standby client for a call.
      if (_engineReady && _pageLoaded && await _isHealthyStandby(controller)) {
        _log('bridge prewarm skipped; healthy standby owns '
            'generation=$_bridgeGeneration');
        return;
      }
      final generation = _bridgeGeneration + 1;
      await _reloadBridgePage(controller);
      if (!_bridgeIsBeingConsumed && _bridgeGeneration == generation) {
        _bridgePrimed = true;
        _log('bridge prewarmed generation=$generation');
      }
    } catch (error) {
      // Prewarming is an optimization only. initialize() retries with a
      // fresh navigation and will surface a typed error if that also fails.
      _log('bridge prewarm failed; setup will retry: $error');
    }
  }

  Future<void> _loadBridgePage(
    WebViewController controller, {
    bool forceAsset = false,
  }) async {
    if (_usesBundledBridgeShell) {
      _log('loading bridge from bundled Flutter assets (Android primary)');
      await controller.loadFlutterAsset('assets/html/at_call_bridge.html');
      return;
    }
    final configured = dotenv.env['AT_BRIDGE_URL'] ?? defaultBridgeRemoteUrl;
    final bridgeTarget = resolveBridgeOrigin(configured);
    if (!forceAsset &&
        bridgeTarget.origin == CallBridgeOrigin.remote &&
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
    _log('loading bridge from bundled Flutter asset fallback');
    await controller.loadFlutterAsset('assets/html/at_call_bridge.html');
  }

  /// Reloads the bridge exactly once for a media setup generation.
  ///
  /// The AT client requires a clean page per call attempt, but concurrent
  /// WebView navigation is not safe: an older page-finished callback can
  /// otherwise complete the wrong attempt or leave the current one waiting.
  Future<void> _reloadBridgePage(
    WebViewController controller, {
    bool forceAsset = false,
  }) {
    final active = _bridgeLoad;
    if (active != null) return active;
    final generation = ++_bridgeGeneration;
    // A document navigation destroys the JavaScript heap.  Never retain a
    // ready/configured standby claim across that boundary: doing so makes the
    // Dart side believe it can reuse a client that only existed in the
    // previous WebView generation, then silently falls back to a full init
    // during the next call.
    if (!_clientInUse) {
      _engineReady = false;
      _readyConfigKey = null;
      _standbyCredentialExpiresAt = null;
      _lastHeartbeat = null;
      _sessionId = null;
      _callSid = null;
    }
    final ready = Completer<void>();
    _pageLoaded = false;
    _pageReady = ready;
    _log('bridge navigation started generation=$generation');
    final load = () async {
      try {
        final usesAssetShell = forceAsset || _usesBundledBridgeShell;
        await _loadBridgePage(controller, forceAsset: forceAsset);
        await ready.future.timeout(
          usesAssetShell ? _assetBridgeLoadTimeout : _remoteBridgeLoadTimeout,
          onTimeout: () => throw const MediaUnavailable(
            'The hidden call engine page did not finish loading.',
          ),
        );
        await _injectBundledEngine(controller, generation);
        _log('bridge navigation finished generation=$generation');
      } finally {
        if (identical(_pageReady, ready)) _pageReady = null;
      }
    }();
    late final Future<void> tracked;
    tracked = load.whenComplete(() {
      if (identical(_bridgeLoad, tracked)) _bridgeLoad = null;
    });
    _bridgeLoad = tracked;
    return tracked;
  }

  Future<void> _injectBundledEngine(
      WebViewController controller, int generation) async {
    if (_injectedGeneration == generation) return;
    _bridgeNote = 'injecting bundled AT SDK';
    final stopwatch = Stopwatch()..start();
    final sdk = await (_sdkSource ??=
        rootBundle.loadString('assets/js/africastalking-client-1.0.7.min.js'));
    final bridge = await (_bridgeSource ??=
        rootBundle.loadString('assets/js/omnidesk-call-bridge.js'));
    await controller.runJavaScript(sdk).timeout(_sdkInjectionTimeout);
    final sdkProbe = normalizeJavaScriptStringResult(
      await controller
          .runJavaScriptReturningResult(
            '(typeof window.Africastalking === "object") ? '
            '"sdk_ok" : "sdk_missing"',
          )
          .timeout(_bridgeHandshakeTimeout),
    );
    if (sdkProbe != 'sdk_ok') {
      throw const MediaUnavailable(
        'The bundled call SDK could not be initialized.',
      );
    }
    _bridgeNote = 'injecting bundled OmniDesk bridge';
    await controller.runJavaScript(bridge).timeout(_sdkInjectionTimeout);
    final handshake = normalizeJavaScriptStringResult(
      await controller.runJavaScriptReturningResult('''
            (function () {
              if (!window.OmniDesk || !window.OmniDesk.call) {
                return "bridge_missing";
              }
              var status = window.OmniDesk.call.status();
              return status.bridgeVersion === "$_expectedBridgeVersion" &&
                     status.sdkVersion === "$_expectedSdkVersion"
                ? "bridge_ok" : "bridge_version_mismatch";
            })()
          ''').timeout(_bridgeHandshakeTimeout),
    );
    if (handshake != 'bridge_ok') {
      throw MediaUnavailable(
        'The bundled call bridge is incompatible ($handshake).',
      );
    }
    _injectedGeneration = generation;
    _bridgeNote = 'bundled SDK and bridge ready';
    _log('bundled bridge injected generation=$generation '
        'elapsedMs=${stopwatch.elapsedMilliseconds} sdk=$_expectedSdkVersion');
  }

  /// Loads a fresh page for a media attempt. The remote bridge is preferred
  /// for a secure WebView origin, but an ngrok/CDN navigation can occasionally
  /// stall without producing an error callback. Retrying once from the
  /// bundled asset replaces that navigation and gives the app a deterministic
  /// local recovery path. We intentionally do not retry forever.
  Future<void> _reloadBridgeForCall(WebViewController controller) async {
    if (_usesBundledBridgeShell) {
      await _reloadBridgePage(controller, forceAsset: true);
      return;
    }
    try {
      await _reloadBridgePage(controller);
    } on MediaUnavailable catch (error) {
      if (!error.message.contains('did not finish loading')) rethrow;
      _log('remote bridge navigation timed out; retrying bundled asset once');
      _bridgeNote = 'remote bridge navigation timed out; retrying asset';
      await _reloadBridgePage(controller, forceAsset: true);
    }
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

  String get _diagnosticTailNote => _diagnosticTail.isEmpty
      ? 'no bridge diagnostics'
      : _diagnosticTail.join(' | ');

  @visibleForTesting
  List<String> get consoleTailForTest => List.unmodifiable(_consoleTail);

  /// Called by the host widget's navigation delegate.
  void notePageStarted(String url) {
    _injectedGeneration = -1;
    final uri = Uri.tryParse(url);
    final safeUrl =
        uri == null ? '[unparseable]' : uri.replace(query: '').toString();
    _log('bridge page started generation=$_bridgeGeneration url=$safeUrl');
  }

  /// Called by the host widget's navigation delegate.
  void notePageFinished() {
    _pageLoaded = true;
    _bridgeNote = 'bridge page loaded, no client initialized yet';
    final ready = _pageReady;
    if (ready != null && !ready.isCompleted) ready.complete();
    _log('bridge page loaded generation=$_bridgeGeneration');
  }

  /// Called by the host widget's navigation delegate.
  void notePageError(String description) {
    _pageLoaded = false;
    _bridgeNote = 'bridge page failed to load: $description';
    _log('bridge page load FAILED: $description');
    final ready = _pageReady;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(MediaUnavailable(_bridgeNote));
    }
  }

  void noteAppLifecycle(AppLifecycleState state) {
    _log('app lifecycle=${state.name} bridgeGeneration=$_bridgeGeneration '
        'engineReady=$_engineReady clientInUse=$_clientInUse');
  }

  @override
  Stream<CallMediaEvent> get events => _events.stream;

  /// Warms signaling only. Microphone permission and capture remain deferred
  /// until the agent actually dials or answers.
  Future<void> prewarmClient(CallMediaConfig config) async {
    if (_disposed || _clientInUse || !config.canUseWebRtc) return;
    final reservationAtStart = _clientReservation;
    try {
      await _initializeRequest(config, reserveClient: false);
      if (_clientReservation == reservationAtStart) {
        _clientInUse = false;
        _callSid = null;
        if (_invalidateAfterInitialization) {
          _invalidateAfterInitialization = false;
          await _clearIdleStandby(
            reason: 'deferred auth/workspace invalidation after prewarm',
          );
        } else {
          _log('AT client entered standby-ready state');
        }
      } else {
        _log('AT standby prewarm was claimed by an active call');
      }
    } catch (error) {
      _engineReady = false;
      _readyConfigKey = null;
      _standbyCredentialExpiresAt = null;
      _log('AT client standby prewarm failed: ${error.runtimeType}');
    }
  }

  @override
  Future<String> initialize(CallMediaConfig config, {CallId? incomingCallId}) =>
      _initializeRequest(config, incomingCallId: incomingCallId);

  Future<String> _initializeRequest(
    CallMediaConfig config, {
    CallId? incomingCallId,
    bool reserveClient = true,
  }) async {
    if (reserveClient) _clientReservation++;
    final activeInitialization = _initialization;
    if (activeInitialization != null) {
      final session = await activeInitialization;
      if (reserveClient) _clientInUse = true;
      return session;
    }
    late final Future<String> operation;
    operation = _initializeWithFallback(config, incomingCallId: incomingCallId)
        .whenComplete(() {
      if (identical(_initialization, operation)) _initialization = null;
    });
    _initialization = operation;
    final session = await operation;
    if (reserveClient) _clientInUse = true;
    return session;
  }

  Future<String> _initializeWithFallback(CallMediaConfig config,
      {CallId? incomingCallId}) async {
    try {
      return await _initialize(config, incomingCallId: incomingCallId);
    } on MediaUnavailable catch (firstError) {
      if (firstError.message.contains('already in progress')) rethrow;
      _log('initialization failed; rebuilding once: ${firstError.message}');
      _engineReady = false;
      _clientInUse = false;
      _readyConfigKey = null;
      _standbyCredentialExpiresAt = null;
      _bridgePrimed = false;
      final session = await _initialize(
        config,
        incomingCallId: incomingCallId,
        forceFresh: true,
      );
      _lastInitializationPath = 'fresh_fallback';
      return session;
    }
  }

  Future<String> _initialize(CallMediaConfig config,
      {CallId? incomingCallId, bool forceFresh = false}) async {
    await waitForController();
    final token = config.webrtcToken;
    if (token == null || token.isEmpty) {
      throw const MediaUnavailable(
        'The call service did not provide a WebRTC capability token.',
      );
    }
    final controller = _controller;
    if (controller == null) {
      throw const MediaUnavailable(
        'The hidden call engine is not mounted yet.',
      );
    }
    if (_clientInUse) {
      throw const MediaUnavailable(
          'Another media call is already in progress.');
    }
    final configKey = _standbyConfigKey(config);
    final newSessionId =
        'webview-media-${DateTime.now().microsecondsSinceEpoch}';
    final sameClientIdentity = _readyConfigKey == configKey;
    final standbyCredentialFresh = _standbyCredentialIsFresh;
    final mayReuseStandby = !forceFresh &&
        _engineReady &&
        config.isWebRtcCredentialFresh &&
        standbyCredentialFresh &&
        sameClientIdentity;
    _log('standby eligibility forceFresh=$forceFresh '
        'engineReady=$_engineReady requestCredentialFresh='
        '${config.isWebRtcCredentialFresh} '
        'standbyCredentialFresh=$standbyCredentialFresh '
        'sameClientIdentity=$sameClientIdentity');
    if (mayReuseStandby && await _isHealthyStandby(controller)) {
      _lastInitializationPath = 'standby_reused';
      _sessionId = newSessionId;
      _callSid = null;
      final prepared = normalizeJavaScriptStringResult(
        await controller.runJavaScriptReturningResult(
          'window.OmniDesk.call.prepareSession('
          '${jsonEncode(newSessionId)}, null)',
        ),
      );
      if (prepared == 'ready') {
        _clientInUse = true;
        _bridgeNote = 'healthy standby client reused';
        _log('standby AT client reused session=$newSessionId');
        return newSessionId;
      }
      _engineReady = false;
      _readyConfigKey = null;
      _standbyCredentialExpiresAt = null;
    }
    _callSid = null;
    _lastInitializationPath = 'fresh_connection';
    _ready = Completer<void>();
    _consoleTail.clear();
    _diagnosticTail.clear();
    _sessionId = newSessionId;
    _bridgeNote = 'starting client init';
    // Fingerprint (not the secret) so runs can be correlated if the backend
    // rotates tokens between attempts. Capability tokens live up to 24h
    // (`lifeTimeSec: "86400"` per AT docs and the backend's `expires_in`),
    // so a missing `ready` is never a TTL race against setup latency.
    _log('client init started tokenAvailable=${token.isNotEmpty} '
        'gatewayConfigured=${config.webrtcGatewayUrl?.isNotEmpty == true}');
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
      _bridgeIsBeingConsumed = true;
      try {
        if (!forceFresh && _bridgePrimed && _pageLoaded) {
          _log('using prewarmed bridge generation=$_bridgeGeneration');
        } else {
          await _reloadBridgeForCall(controller);
        }
      } catch (error) {
        _log('bridge reload failed: $error');
        rethrow;
      } finally {
        _bridgePrimed = false;
        _bridgeIsBeingConsumed = false;
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
            'diagnostics: $_diagnosticTailNote; '
            'page console: $_consoleTailNote).',
          );
        },
      );
      // If this value changed, another owner navigated/recreated the hidden
      // WebView while this init awaited the provider. Fail into the existing
      // one-fresh-client fallback instead of returning a null/stale session.
      if (_sessionId != newSessionId) {
        throw const MediaUnavailable(
          'The hidden call engine was replaced while preparing media.',
        );
      }
      _engineReady = true;
      _clientInUse = true;
      _readyConfigKey = configKey;
      _standbyCredentialExpiresAt = config.webrtcExpiresAt;
      _log('engine ready; SDK owns the first microphone request during dial');
    } catch (_) {
      _engineReady = false;
      _clientInUse = false;
      _readyConfigKey = null;
      _standbyCredentialExpiresAt = null;
      rethrow;
    } finally {
      _ready = null;
    }
    final completedSessionId = _sessionId;
    if (completedSessionId == null || completedSessionId != newSessionId) {
      throw const MediaUnavailable(
        'The hidden call engine lost its media session during setup.',
      );
    }
    return completedSessionId;
  }

  /// The provider can rotate capability tokens on each read of media-config.
  /// A token value is therefore not a client identity: recreating a healthy
  /// AT client solely because it changed defeats standby and can leave a
  /// second hidden WebView client waiting for a gateway slot.  The first
  /// client's expiry is retained separately and remains the reuse authority.
  String _standbyConfigKey(CallMediaConfig config) => [
        config.provider,
        config.webrtcClientName ?? '',
        config.webrtcGatewayUrl ?? '',
      ].join('|');

  bool get _standbyCredentialIsFresh {
    final expiry = _standbyCredentialExpiresAt;
    return expiry == null ||
        expiry.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 2)));
  }

  Future<bool> _isHealthyStandby(WebViewController controller) async {
    try {
      // This status call is intentionally the liveness probe.  The bridge
      // stops its periodic heartbeat when a call is torn down, so heartbeat
      // age alone cannot distinguish a healthy idle AT registration from a
      // reclaimed WebView.  In particular, rejecting a client after 15s of
      // idle time made every later inbound call rebuild the document and lose
      // the very standby connection it was meant to reuse.
      final result = await controller
          .runJavaScriptReturningResult(
            'window.OmniDesk && window.OmniDesk.call '
            '? JSON.stringify(window.OmniDesk.call.status()) : "{}"',
          )
          .timeout(const Duration(seconds: 3));
      final decoded = jsonDecode(normalizeJavaScriptStringResult(result));
      if (decoded is! Map || decoded['clientReady'] != true) {
        _log(
            'standby health check failed: clientReady=${decoded is Map ? decoded['clientReady'] : 'unavailable'}');
        return false;
      }
      final lastEvent = '${decoded['lastEvent'] ?? ''}'.toLowerCase();
      if (const {'offline', 'error', 'notready', 'closed'}
          .contains(lastEvent)) {
        _log('standby health check failed: lastEvent=$lastEvent');
        return false;
      }
      final heartbeat = _lastHeartbeat;
      if (heartbeat != null) {
        final heartbeatAge = DateTime.now().difference(heartbeat);
        if (heartbeatAge >= const Duration(seconds: 15)) {
          // Soft signal only. A successful status probe above proves the
          // current WebView generation is still responsive. Keep the warm AT
          // client and make the age observable for later performance work.
          _log('standby heartbeat stale but status probe passed '
              'heartbeatAgeMs=${heartbeatAge.inMilliseconds}');
        }
      }
      return true;
    } catch (error) {
      _log('standby health check failed: ${error.runtimeType}');
      return false;
    }
  }

  /// Requests the OS permission without opening a WebRTC capture stream.
  /// Call this from an explicit calling-availability action, not idle
  /// prewarming. The bridge still receives a platform permission grant during
  /// the real capture request.
  Future<bool> requestMicrophonePermission() async {
    final microphone = await Permission.microphone.request();
    return microphone.isGranted;
  }

  /// Bluetooth route discovery on Android 12+ is guarded by a runtime
  /// permission even though the app can still call through earpiece/speaker.
  /// This remains best-effort: declining it must never block call setup.
  Future<void> requestBluetoothRoutePermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final permission = Permission.bluetoothConnect;
    final status = await permission.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      await permission.request();
    }
  }

  Future<void> _ensureMicrophonePermission() async {
    if (!await requestMicrophonePermission()) {
      throw const MediaUnavailable(
        'Microphone access is required to place calls.',
      );
    }
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
    await _ensureMicrophonePermission();
    final controller = _requireController();
    _callSid = callSid;
    _sessionId ??= 'webview-media-${DateTime.now().microsecondsSinceEpoch}';
    _log('dial ${_maskedPhone(phoneNumber)} (callSid=$callSid)');
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
    await _ensureMicrophonePermission();
    final controller = _requireController();
    _callSid = callSid;
    _log('answer incoming (callSid=$callSid)');
    await controller.runJavaScript(
      'window.OmniDesk.call.answer(${jsonEncode(callSid)})',
    );
  }

  @override
  Future<void> endMedia(String mediaSessionId) async {
    await _releaseMediaLease(reason: 'terminal_media_end');
  }

  @override
  Future<void> setMuted(bool enabled) async {
    await _runControl(
      'mute',
      'window.OmniDesk.call.mute(${enabled ? 'true' : 'false'})',
    );
  }

  @override
  Future<void> setHeld(bool enabled) async {
    await _runControl(
      'hold',
      'window.OmniDesk.call.hold(${enabled ? 'true' : 'false'})',
    );
  }

  @override
  Future<void> sendDtmf(String digit) async {
    await _runControl(
        'DTMF', 'window.OmniDesk.call.dtmf(${jsonEncode(digit)})');
  }

  Future<void> _runControl(String label, String expression) async {
    final result = await _requireController()
        .runJavaScriptReturningResult(expression)
        .timeout(const Duration(seconds: 5));
    if (normalizeJavaScriptStringResult(result) != 'ok') {
      throw MediaUnavailable('$label is not supported by the call provider.');
    }
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
      if (decoded['event'] == 'page_ready') {
        // The bridge emits this from its own script after it installs
        // `window.OmniDesk`. It is an independent completion signal for
        // Android WebView builds where navigation callbacks can arrive late
        // (or be lost while the app is being restored from an answer action).
        // Navigation is serialized, so it cannot complete a competing load.
        notePageFinished();
      } else {
        _lastHeartbeat = DateTime.now();
      }
      return;
    }
    if (decoded is Map && decoded['event'] == 'ws_log') {
      _log('[bridge ws] ${decoded['data']}');
      return;
    }
    if (decoded is Map && decoded['event'] == 'diagnostic') {
      final phase = decoded['phase']?.toString() ?? 'unknown';
      final level = decoded['level']?.toString() ?? 'info';
      final details = decoded['details'];
      final line = 'phase=$phase level=$level details=${jsonEncode(details)}';
      _diagnosticTail.add(line);
      while (_diagnosticTail.length > 12) {
        _diagnosticTail.removeAt(0);
      }
      _bridgeNote = 'bridge phase: $phase';
      _log('bridge diagnostic $line');
      final safeDetails = <String, Object?>{};
      if (details is Map) {
        for (final entry in details.entries) {
          final key = entry.key.toString();
          if (const {
            'eventName',
            'providerEventCount',
            'secureContext',
            'visibility',
            'hidden',
            'focused',
            'hasMediaDevices',
            'hasGetUserMedia',
            'hasPeerConnection',
            'audioTrackCount',
            'trackState',
            'trackEnabled',
            'trackMuted',
            'errorName',
            'required',
          }.contains(key)) {
            final value = entry.value;
            if (value is String ||
                value is num ||
                value is bool ||
                value == null) {
              safeDetails[key] = value;
            }
          }
        }
      }
      _diagnostics.add(CallBridgeDiagnostic(
        phase: phase,
        level: level,
        timestamp: DateTime.now().toUtc(),
        details: safeDetails,
      ));
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
      _engineReady = true;
      final ready = _ready;
      if (ready != null && !ready.isCompleted) ready.complete();
    }
    if (event.type == CallMediaEventType.error) {
      _engineReady = false;
      _readyConfigKey = null;
      _standbyCredentialExpiresAt = null;
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
    await _diagnostics.close();
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

class _HiddenCallWebViewState extends ConsumerState<HiddenCallWebView>
    with WidgetsBindingObserver {
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
      if (kDebugMode || kProfileMode) {
        AndroidWebViewController.enableDebugging(true);
      }
    }
    if (controller.platform is WebKitWebViewController &&
        (kDebugMode || kProfileMode)) {
      unawaited(
        (controller.platform as WebKitWebViewController).setInspectable(true),
      );
    }
    return controller;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      onPageStarted: service.notePageStarted,
      onPageFinished: (_) => service.notePageFinished(),
      onWebResourceError: (error) => service.notePageError(
        '${error.errorType} ${error.description}'.trim(),
      ),
    ));
    // Install navigation observation before starting the initial load;
    // otherwise a fast cached bridge can finish before page readiness is
    // observed and falsely time out during the first call.
    service.attachController(_controller);
    unawaited(service.prewarmBridge());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(webViewCallMediaServiceProvider).noteAppLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
