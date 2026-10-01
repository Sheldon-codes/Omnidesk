import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/calls/call_api.dart';
import '../../services/calls/call_media_provider.dart';
import '../../services/calls/call_media_service.dart';
import '../../services/calls/call_models.dart';
import '../../services/calls/device_installation_service.dart';
import '../../services/calls/native_call_service.dart';
import '../../services/calls/webview_call_media_service.dart';
import '../../services/auth_session_controller.dart';

part 'call_session_controller.g.dart';

/// Presentation-oriented lifecycle retained for the existing call UI.
/// [phase] carries the richer transport lifecycle used by the controller.
enum CallLifecycle {
  idle,
  incomingRinging,
  outgoingRinging,
  connecting,
  active,

  /// A short, non-interactive acknowledgement after a remote terminal event.
  /// Keeping the party visible avoids the abrupt disappearance of the call UI.
  terminalNotice,
  failed
}

enum CallPresentation { fullscreen, collapsed }

class CallParty {
  const CallParty({
    required this.displayName,
    required this.phoneNumber,
    this.customerId,
    this.avatar,
  });

  final String? customerId;
  final String displayName;
  final String phoneNumber;
  final String? avatar;

  String get initial {
    final value = displayName.trim().isEmpty ? phoneNumber : displayName.trim();
    return value.runes.isEmpty
        ? '?'
        : String.fromCharCode(value.runes.first).toUpperCase();
  }
}

class CallSessionState {
  const CallSessionState({
    this.lifecycle = CallLifecycle.idle,
    this.phase = CallPhase.idle,
    this.presentation = CallPresentation.fullscreen,
    this.party,
    this.callId,
    this.callSid,
    this.mediaSessionId,
    this.offerId,
    this.ticketId,
    this.ticketNumber,
    this.category,
    this.startedAt,
    this.elapsed = Duration.zero,
    this.muted = false,
    this.speakerEnabled = false,
    this.onHold = false,
    this.keypadVisible = false,
    this.dtmfDigits = '',
    this.nativeIncomingSurfaceActive = false,
    this.failureMessage,
  });

  final CallLifecycle lifecycle;
  final CallPhase phase;
  final CallPresentation presentation;
  final CallParty? party;
  final CallId? callId;

  /// Provider-owned identifier for outbound completion. It is never used as a
  /// canonical incoming lifecycle ID.
  final String? callSid;

  /// Opaque native-only correlation ID. It never leaves the device.
  final String? mediaSessionId;
  final CallOfferId? offerId;
  final String? ticketId;
  final String? ticketNumber;
  final String? category;
  final DateTime? startedAt;
  final Duration elapsed;
  final bool muted;
  final bool speakerEnabled;
  final bool onHold;
  final bool keypadVisible;
  final String dtmfDigits;

  /// While true, Android Telecom/native Activity exclusively owns ringing.
  /// Flutter takes over once the agent accepts and media setup begins.
  final bool nativeIncomingSurfaceActive;
  final String? failureMessage;

  bool get hasCall => lifecycle != CallLifecycle.idle && party != null;
  bool get isIncoming => phase == CallPhase.incomingRinging;
  bool get isActive => lifecycle == CallLifecycle.active;
  bool get isTerminalNotice => lifecycle == CallLifecycle.terminalNotice;
  bool get isBackendCall => callId != null && callId!.isNotEmpty;

  String get statusLabel => switch (lifecycle) {
        CallLifecycle.idle => '',
        CallLifecycle.incomingRinging => 'Incoming call',
        CallLifecycle.outgoingRinging => 'Calling…',
        CallLifecycle.connecting => 'Connecting…',
        CallLifecycle.active => formatCallDuration(elapsed),
        CallLifecycle.terminalNotice => failureMessage ?? 'Call ended',
        CallLifecycle.failed => failureMessage ?? 'Call unavailable',
      };

  CallSessionState copyWith({
    CallLifecycle? lifecycle,
    CallPhase? phase,
    CallPresentation? presentation,
    Object? party = _keep,
    Object? callId = _keep,
    Object? callSid = _keep,
    Object? mediaSessionId = _keep,
    Object? offerId = _keep,
    Object? ticketId = _keep,
    Object? ticketNumber = _keep,
    Object? category = _keep,
    Object? startedAt = _keep,
    Duration? elapsed,
    bool? muted,
    bool? speakerEnabled,
    bool? onHold,
    bool? keypadVisible,
    String? dtmfDigits,
    bool? nativeIncomingSurfaceActive,
    Object? failureMessage = _keep,
  }) =>
      CallSessionState(
        lifecycle: lifecycle ?? this.lifecycle,
        phase: phase ?? this.phase,
        presentation: presentation ?? this.presentation,
        party: identical(party, _keep) ? this.party : party as CallParty?,
        callId: identical(callId, _keep) ? this.callId : callId as String?,
        callSid: identical(callSid, _keep) ? this.callSid : callSid as String?,
        mediaSessionId: identical(mediaSessionId, _keep)
            ? this.mediaSessionId
            : mediaSessionId as String?,
        offerId: identical(offerId, _keep) ? this.offerId : offerId as String?,
        ticketId:
            identical(ticketId, _keep) ? this.ticketId : ticketId as String?,
        ticketNumber: identical(ticketNumber, _keep)
            ? this.ticketNumber
            : ticketNumber as String?,
        category:
            identical(category, _keep) ? this.category : category as String?,
        startedAt: identical(startedAt, _keep)
            ? this.startedAt
            : startedAt as DateTime?,
        elapsed: elapsed ?? this.elapsed,
        muted: muted ?? this.muted,
        speakerEnabled: speakerEnabled ?? this.speakerEnabled,
        onHold: onHold ?? this.onHold,
        keypadVisible: keypadVisible ?? this.keypadVisible,
        dtmfDigits: dtmfDigits ?? this.dtmfDigits,
        nativeIncomingSurfaceActive:
            nativeIncomingSurfaceActive ?? this.nativeIncomingSurfaceActive,
        failureMessage: identical(failureMessage, _keep)
            ? this.failureMessage
            : failureMessage as String?,
      );

  static const _keep = Object();
}

String formatCallDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

@Riverpod(keepAlive: true)
class CallSessionController extends _$CallSessionController {
  Timer? _durationTimer;
  Timer? _terminalTimer;
  StreamSubscription<NativeCallEvent>? _nativeEvents;
  StreamSubscription<CallMediaEvent>? _webViewEvents;
  StreamSubscription<CallBridgeDiagnostic>? _bridgeDiagnostics;
  StreamSubscription<NativeAudioSessionDiagnostic>? _nativeAudioDiagnostics;
  CallMediaService? _activeMedia;
  Completer<void>? _incomingMedia;
  bool _isFinishing = false;
  bool _backendAccepted = false;
  CallMediaConfig? _warmMediaConfig;
  DateTime? _warmMediaConfigAt;
  String? _warmMediaScope;
  Future<CallMediaConfig>? _mediaConfigRequest;
  String? _mediaConfigRequestScope;
  int _mediaConfigGeneration = 0;
  Future<void>? _prewarmRequest;
  String? _prewarmRequestScope;
  String? _acceptedInstallationId;
  final Set<String> _reportedClientEvents = <String>{};
  Stopwatch? _attemptClock;
  final Map<String, int> _attemptMetrics = <String, int>{};
  final Set<CallId> _ownershipDeniedCallIds = <CallId>{};

  CallApi get _api => ref.read(callApiProvider);
  Future<String> Function() get _installationId =>
      ref.read(callInstallationIdProvider);
  NativeCallService get _native => ref.read(nativeCallServiceProvider);
  CallMediaService get _webView => ref.read(callMediaServiceProvider);

  /// WebRTC is the only supported production media implementation.
  CallMediaService get _media => _activeMedia ?? _webView;

  /// Read-only lifecycle projection for non-widget coordinators. Keeping this
  /// behind the controller avoids exposing Riverpod notifier state outside
  /// its supported API surface.
  bool get hasActiveSession => state.hasCall;

  /// Lets lifecycle orchestration safely correlate a durable native action
  /// without reaching into Riverpod notifier state from outside this class.
  /// A delayed CallKit transaction must never act on a newer call surface.
  bool matchesNativeIdentity({String? callId, String? callSid}) =>
      (callId != null && callId.isNotEmpty && state.callId == callId) ||
      (callSid != null && callSid.isNotEmpty && state.callSid == callSid);

  String _authScopeKey() {
    final session = ref.read(authSessionControllerProvider).session;
    final workspace = session?.user.activeWorkspace?.id ?? '';
    return '${session?.user.id ?? ''}:$workspace';
  }

  /// Backend-driven engine choice: only a supported `transport: "webrtc"`
  /// configuration is allowed to reach the hidden WebView engine.
  CallMediaService _selectMedia(CallMediaConfig config) {
    if (!usesSupportedWebViewMedia(config)) {
      throw const MediaUnavailable(
        'The call service returned an unsupported media transport.',
      );
    }
    _activeMedia = _webView;
    return _webView;
  }

  Future<void> prewarmMedia() async {
    final scope = _authScopeKey();
    final existing = _prewarmRequest;
    if (existing != null && _prewarmRequestScope == scope) return existing;
    if (existing != null && _prewarmRequestScope != scope) {
      // Do not let a previous user's/workspace's prewarm claim the new
      // standby generation. Its network request may finish, but it cannot
      // publish or reuse its result after the scope check below.
      final media = _webView;
      if (media is WebViewCallMediaService) {
        unawaited(media.invalidateStandby());
      }
    }
    if (state.hasCall) return;
    late final Future<void> request;
    request = () async {
      try {
        final config = await _getMediaConfig();
        if (!usesSupportedWebViewMedia(config) ||
            state.hasCall ||
            _authScopeKey() != scope) {
          return;
        }
        // Keep the controller dependent on the selected media implementation.
        // Tests and future platform implementations can supply another
        // CallMediaService without accidentally constructing a real hidden
        // WebView purely to prewarm it.
        final media = _webView;
        if (media is WebViewCallMediaService) {
          await media.prewarmClient(config);
        }
      } catch (error) {
        developer.log(
          'Media standby prewarm unavailable: ${error.runtimeType}.',
          name: 'CallSession',
        );
      }
    }();
    _prewarmRequest = request;
    _prewarmRequestScope = scope;
    try {
      await request;
    } finally {
      if (identical(_prewarmRequest, request)) {
        _prewarmRequest = null;
        _prewarmRequestScope = null;
      }
    }
  }

  Future<CallMediaConfig> _getMediaConfig() async {
    final scope = _authScopeKey();
    if (_warmMediaScope != null && _warmMediaScope != scope) {
      _mediaConfigGeneration++;
      _warmMediaConfig = null;
      _warmMediaConfigAt = null;
      if (!state.hasCall) {
        final media = _webView;
        if (media is WebViewCallMediaService) {
          unawaited(media.invalidateStandby());
        }
      }
    }
    final cached = _warmMediaConfig;
    final cachedAt = _warmMediaConfigAt;
    if (cached != null &&
        cachedAt != null &&
        _warmMediaScope == scope &&
        cached.isWebRtcCredentialFresh &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 10)) {
      return cached;
    }
    final active = _mediaConfigRequest;
    if (active != null && _mediaConfigRequestScope == scope) return active;
    late final Future<CallMediaConfig> request;
    final generation = _mediaConfigGeneration;
    request = _api.getMediaConfig().then((config) {
      if (_mediaConfigGeneration == generation && _authScopeKey() == scope) {
        _warmMediaConfig = config;
        _warmMediaConfigAt = DateTime.now();
        _warmMediaScope = scope;
      }
      return config;
    }).whenComplete(() {
      if (identical(_mediaConfigRequest, request)) {
        _mediaConfigRequest = null;
        _mediaConfigRequestScope = null;
      }
    });
    _mediaConfigRequest = request;
    _mediaConfigRequestScope = scope;
    return request;
  }

  @override
  CallSessionState build() {
    _nativeEvents = _native.events.listen(_onNativeEvent);
    _nativeAudioDiagnostics = _native.audioSessionDiagnostics.listen(
      _onNativeAudioDiagnostic,
    );
    final webView = _webView;
    _webViewEvents = webView.events.listen(
      (event) => _onMediaEvent(_webView, event),
    );
    if (webView is WebViewCallMediaService) {
      _bridgeDiagnostics = webView.diagnostics.listen(_onBridgeDiagnostic);
    }
    ref.onDispose(() {
      _durationTimer?.cancel();
      _terminalTimer?.cancel();
      unawaited(_nativeEvents?.cancel() ?? Future<void>.value());
      unawaited(_nativeAudioDiagnostics?.cancel() ?? Future<void>.value());
      unawaited(_webViewEvents?.cancel() ?? Future<void>.value());
      unawaited(_bridgeDiagnostics?.cancel() ?? Future<void>.value());
    });
    return const CallSessionState();
  }

  void _onNativeAudioDiagnostic(NativeAudioSessionDiagnostic diagnostic) {
    final media = _webView;
    if (media is WebViewCallMediaService) {
      unawaited(media.updateNativeAudioDiagnostic(diagnostic));
    }
  }

  void _onBridgeDiagnostic(CallBridgeDiagnostic diagnostic) {
    if (!state.hasCall || !_backendAccepted) return;
    final event = switch (diagnostic.phase) {
      'incoming_received' => CallClientEvent.incoming,
      'get_user_media_started' => CallClientEvent.microphoneCaptureStarted,
      'get_user_media_resolved' => CallClientEvent.microphoneCaptureReady,
      'connected' => CallClientEvent.connected,
      'get_user_media_rejected' ||
      'at_error' ||
      'at_offline' ||
      'at_disconnect' ||
      'at_closed' ||
      'at_notready' =>
        CallClientEvent.bridgeError,
      _ => null,
    };
    if (event != null) unawaited(_reportClientEvent(event));
  }

  Future<void> _reportClientEvent(CallClientEvent event) async {
    final callId = state.callId;
    final offerId = state.offerId;
    final installationId = _acceptedInstallationId;
    if (callId == null ||
        callId.isEmpty ||
        offerId == null ||
        offerId.isEmpty ||
        installationId == null ||
        installationId.isEmpty) {
      return;
    }
    final key = '$callId|$offerId|${event.value}';
    if (!_reportedClientEvents.add(key)) return;
    try {
      await _api
          .reportClientEvent(
            callId: callId,
            offerId: offerId,
            installationId: installationId,
            event: event,
          )
          .timeout(const Duration(seconds: 4));
    } catch (error) {
      // Telemetry is deliberately non-blocking. The bridge and call state
      // must continue even when the endpoint is offline or unavailable.
      developer.log(
        'Client-event telemetry failed event=${event.value} '
        'error=${error.runtimeType}.',
        name: 'CallSession',
      );
    }
  }

  void _startAttemptClock() {
    _attemptClock?.stop();
    _attemptClock = Stopwatch()..start();
    _attemptMetrics.clear();
  }

  void _markAttemptPhase(String phase) {
    final clock = _attemptClock;
    if (clock == null || _attemptMetrics.containsKey(phase)) return;
    final elapsed = clock.elapsedMilliseconds;
    _attemptMetrics[phase] = elapsed;
    developer.log('Call timing phase=$phase elapsedMs=$elapsed',
        name: 'CallSession');
  }

  /// Receives a canonical offer from FCM/PushKit after workspace validation.
  Future<bool> handleIncomingOffer(CallOffer offer) async {
    developer.log(
      'Session received incoming offer callId=${offer.callId} '
      'offerId=${offer.offerId} hasExistingCall=${state.hasCall} '
      'expired=${offer.isExpired}.',
      name: 'CallSession',
    );
    if (offer.isExpired ||
        state.hasCall ||
        _ownershipDeniedCallIds.contains(offer.callId)) {
      return false;
    }
    _terminalTimer?.cancel();
    final party = CallParty(
      customerId: offer.customerId,
      displayName: offer.callerName?.trim().isNotEmpty == true
          ? offer.callerName!.trim()
          : offer.callerNumber,
      phoneNumber: offer.callerNumber,
    );
    state = CallSessionState(
      lifecycle: CallLifecycle.incomingRinging,
      phase: CallPhase.incomingRinging,
      party: party,
      callId: offer.callId,
      offerId: offer.offerId,
      ticketId: offer.ticketId,
      ticketNumber: offer.ticketNumber,
      category: offer.category,
    );
    _reportedClientEvents.clear();
    _acceptedInstallationId = null;
    _startAttemptClock();
    try {
      developer.log(
        'Presenting incoming call callId=${offer.callId}.',
        name: 'CallSession',
      );
      final presentation = await _native.presentIncoming(offer);
      if (state.callId == offer.callId &&
          state.lifecycle == CallLifecycle.incomingRinging) {
        state = state.copyWith(nativeIncomingSurfaceActive: true);
      }
      _markAttemptPhase('native_presented');
      developer.log(
        'Incoming call presentation returned callId=${offer.callId}; '
        'sending delivery acknowledgement.',
        name: 'CallSession',
      );
      final installationId = await _installationId();
      unawaited(_api
          .acknowledgeDelivery(
        callId: offer.callId,
        offerId: offer.offerId,
        installationId: installationId,
        receivedAt: presentation.receivedAt,
        nativePresentedAt: presentation.nativePresentedAt,
      )
          .then((_) {
        developer.log(
          'Delivery acknowledgement confirmed callId=${offer.callId}.',
          name: 'CallSession',
        );
      }).catchError((error) {
        developer.log(
          'Delivery acknowledgement failed callId=${offer.callId} '
          'error=${error.runtimeType}.',
          name: 'CallSession',
        );
      }));
      return true;
    } catch (error) {
      developer.log(
        'Incoming presentation failed callId=${offer.callId} '
        'error=${error.runtimeType}.',
        name: 'CallSession',
      );
      _fail(_messageFor(error));
      return false;
    }
  }

  /// The system notification has opened Flutter while the native Telecom call
  /// remains ringing.  Reveal the existing Flutter incoming UI as a mirror;
  /// this must never answer, dismiss, or otherwise mutate the native call.
  void revealIncomingCallSurface(CallId callId, CallOfferId offerId) {
    if (state.lifecycle != CallLifecycle.incomingRinging ||
        state.callId != callId ||
        state.offerId != offerId) {
      return;
    }
    state = state.copyWith(nativeIncomingSurfaceActive: false);
    developer.log(
      'Flutter incoming surface revealed for notification launch callId=$callId.',
      name: 'CallSession',
    );
  }

  /// Starts the documented outbound signal, registration, then SIP INVITE
  /// flow. The native `connected` event, not the originate response, starts
  /// the displayed duration clock.
  bool startOutgoing(CallParty party, {String? ticketId}) {
    if (state.hasCall || _isFinishing) return false;
    state = CallSessionState(
      lifecycle: CallLifecycle.connecting,
      phase: CallPhase.outgoingPreparing,
      party: party,
      ticketId: ticketId,
    );
    _startAttemptClock();
    unawaited(_initiateOutgoing(party, ticketId: ticketId));
    return true;
  }

  Future<void> _initiateOutgoing(
    CallParty party, {
    String? ticketId,
  }) async {
    OutboundCallResult? created;
    try {
      // Admit the local media engine before creating a backend call. The
      // WebView implementation can release a verified idle stale reservation
      // here, but refuses to touch an attached/unknown background call.
      await _webView.prepareForNewOutboundCall();
      if (state.party != party || state.phase != CallPhase.outgoingPreparing) {
        return;
      }
      final configFuture = _getMediaConfig();
      final initiateFuture = _api.initiateOutbound(
        toNumber: party.phoneNumber,
        ticketId: ticketId,
      );
      created = await initiateFuture;
      _markAttemptPhase('initiate_completed');
      final result = created;
      // Ignore a late response after the agent has ended the local surface.
      if (state.party != party || state.phase != CallPhase.outgoingPreparing) {
        return;
      }
      state = state.copyWith(
        callId: result.callId,
        callSid: result.callSid,
        failureMessage: null,
      );
      await _native.beginOutgoing(_identityFor(state));
      // On iOS, CallKit—not Flutter or the hidden WKWebView—owns audio
      // activation. Starting AT capture before `didActivate` can yield a
      // live-but-muted track with no outgoing RTP frames.
      await _native.waitForSystemAudioReady();
      _markAttemptPhase('system_audio_active');
      final config = await configFuture;
      if (!config.canAuthenticate && !config.canUseWebRtc) {
        throw const CallApiException(
          CallApiErrorKind.unavailable,
          'The call service did not provide a usable media credential.',
        );
      }
      final media = _selectMedia(config);
      final registrationSessionId = await media.initialize(config);
      _markAttemptPhase('client_ready');
      if (state.party != party || state.lifecycle == CallLifecycle.failed) {
        await media.endMedia(registrationSessionId);
        return;
      }
      // Retain the provider identifier before dialing: a fast native connect
      // event is allowed to arrive before `dial` returns.
      state = state.copyWith(
        mediaSessionId: registrationSessionId,
        failureMessage: null,
      );
      final mediaSessionId = await media.dial(
        callSid: result.callSid,
        phoneNumber: result.normalizedToNumber ?? party.phoneNumber,
        sipTargetUri: result.sipUri,
      );
      _markAttemptPhase('dial_requested');
      if (state.party != party || state.callSid != result.callSid) {
        // The user ended the surface while native registration completed.
        await media.endMedia(mediaSessionId);
        return;
      }
      state = state.copyWith(
        lifecycle: state.isActive
            ? CallLifecycle.active
            : CallLifecycle.outgoingRinging,
        phase: state.isActive ? CallPhase.active : CallPhase.outgoingRinging,
        mediaSessionId:
            mediaSessionId.isNotEmpty ? mediaSessionId : registrationSessionId,
        failureMessage: null,
      );
    } catch (error) {
      // The backend row exists but media never started: cancel it now so no
      // orphan `ringing` row lingers until the stale-call sweeper reaps it.
      final orphanCallId = created?.callId;
      if (orphanCallId != null &&
          orphanCallId.isNotEmpty &&
          state.party == party) {
        unawaited(_api
            .end(callId: orphanCallId, reason: 'media_setup_failed')
            .then((_) {})
            .catchError((_) {}));
      }
      if (state.party == party) _fail(_messageFor(error));
    }
  }

  Future<void> answer() async {
    if (state.lifecycle != CallLifecycle.incomingRinging) return;
    if (!state.isBackendCall || state.offerId == null) return;
    final callId = state.callId!;
    final offerId = state.offerId!;
    try {
      developer.log(
        'Incoming call flow phase=answer_started callId=$callId '
        'offerId=$offerId.',
        name: 'CallSession',
      );
      state = state.copyWith(
        lifecycle: CallLifecycle.connecting,
        phase: CallPhase.accepted,
        nativeIncomingSurfaceActive: false,
        failureMessage: null,
      );
      // The Flutter incoming page is only a mirror of the native Telecom
      // ringing call.  Unlike a native CallStyle Answer action, tapping
      // Answer here did not previously leave Telecom's RINGING state until
      // WebRTC connected.  That kept the notification ringtone alive through
      // the whole backend/media handshake.  Move the system call to its
      // non-ringing preparation state now; this does not claim the backend
      // offer or mark the media call active.
      try {
        await _native.markAnswering(_identityFor(state));
      } catch (error) {
        // System UI cleanup must be best-effort. A transient MethodChannel or
        // OEM Telecom failure must not prevent this already-visible incoming
        // call from attempting the authoritative backend accept.
        developer.log(
          'Unable to stop native ringing before answer callId=$callId '
          'error=${error.runtimeType}.',
          name: 'CallSession',
        );
      }
      final installationId = await _installationId();
      _acceptedInstallationId = installationId;
      final configFuture = _getMediaConfig();
      developer.log(
        'Incoming call flow phase=accept_requested callId=$callId '
        'offerId=$offerId.',
        name: 'CallSession',
      );
      final acceptFuture = _api.accept(
        callId: callId,
        offerId: offerId,
        installationId: installationId,
      );
      final accepted = await acceptFuture;
      _markAttemptPhase('accept_completed');
      developer.log('Incoming call flow phase=accept_confirmed callId=$callId.',
          name: 'CallSession');
      _backendAccepted = true;
      state = state.copyWith(
        phase: CallPhase.mediaPreparing,
        startedAt: accepted.answeredAt,
      );
      // Backend acceptance remains authoritative and is intentionally not
      // delayed by this local CallKit readiness gate. Only WebRTC capture is.
      await _native.waitForSystemAudioReady();
      _markAttemptPhase('system_audio_active');
      final config = await configFuture;
      if (!config.canAuthenticate && !config.canUseWebRtc) {
        throw const CallApiException(
          CallApiErrorKind.unavailable,
          'The call service did not provide a usable media credential.',
        );
      }
      final mediaSessionId =
          await _selectMedia(config).initialize(config, incomingCallId: callId);
      _markAttemptPhase('client_ready');
      developer.log(
        'Incoming call flow phase=media_client_ready callId=$callId '
        'mediaSession=$mediaSessionId.',
        name: 'CallSession',
      );
      final media = _media;
      final path = media is WebViewCallMediaService
          ? media.lastInitializationPath
          : null;
      final pathEvent = switch (path) {
        'standby_reused' => CallClientEvent.standbyReused,
        'fresh_fallback' => CallClientEvent.freshFallback,
        _ => CallClientEvent.freshConnection,
      };
      unawaited(_reportClientEvent(pathEvent));
      developer.log(
        'Incoming media initialized callId=$callId mediaSession=$mediaSessionId.',
        name: 'CallSession',
      );
      if (state.callId != callId || state.lifecycle == CallLifecycle.failed) {
        await _media.endMedia(mediaSessionId);
        return;
      }
      // Install the waiter before notifying the backend. The provider can
      // create the WebRTC leg immediately after media-ready returns.
      _incomingMedia = Completer<void>();
      developer.log(
        'Incoming call flow phase=media_ready_requested callId=$callId '
        'mediaSession=$mediaSessionId.',
        name: 'CallSession',
      );
      await _api.mediaReady(
        callId: callId,
        offerId: offerId,
        installationId: installationId,
      );
      _markAttemptPhase('media_ready_completed');
      developer.log(
          'Incoming call flow phase=media_ready_confirmed callId=$callId; '
          'waiting_for_provider_incoming=true.',
          name: 'CallSession');
      state = state.copyWith(
        phase: CallPhase.connecting,
        mediaSessionId: mediaSessionId,
      );
      // Africa's Talking delivers the media leg only after media-ready. Do
      // not answer merely because the backend handshake completed: wait for
      // the bridge's canonical incoming event, then accept that pending leg.
      await _waitForIncomingMedia(callId);
      _markAttemptPhase('incoming_received');
      developer.log(
        'Incoming call flow phase=provider_incoming_received callId=$callId; '
        'answering_media=true.',
        name: 'CallSession',
      );
      await _media.answerIncoming(callSid: callId);
      developer.log(
        'Incoming call flow phase=media_answer_requested callId=$callId; '
        'waiting_for_connected=true.',
        name: 'CallSession',
      );
      // Native media emits `connected`; only that starts the duration clock.
    } catch (error) {
      if (error is CallApiException &&
          error.kind == CallApiErrorKind.alreadyClaimed) {
        _ownershipDeniedCallIds.add(callId);
      }
      developer.log(
        'Answer flow failed callId=$callId error=${error.runtimeType}.',
        name: 'CallSession',
      );
      _fail(_messageFor(error));
    }
  }

  Future<void> decline() => _finish(reason: 'agent_declined', decline: true);

  Future<void> end() => _finish(reason: 'agent_hangup');

  Future<void> _finish({required String reason, bool decline = false}) async {
    // The CallKit/Telecom end action and the in-app end button may arrive
    // together. Only one request is allowed to reach the authoritative end
    // endpoint for a given local call surface.
    if (_isFinishing) return;
    _isFinishing = true;
    _incomingMedia = null;
    _terminalTimer?.cancel();
    final finishingState = state;
    final callId = finishingState.callId;
    final offerId = state.offerId;
    final callSid = finishingState.callSid;
    final mediaSessionId = finishingState.mediaSessionId;
    final isOutbound = callSid != null && callSid.isNotEmpty;
    final wasBackendCall = callId != null && callId.isNotEmpty;
    final hasNativeCall = wasBackendCall || isOutbound;
    _durationTimer?.cancel();
    final finishingMedia = _activeMedia;
    _activeMedia = null;
    _backendAccepted = false;
    final oldState = finishingState;
    try {
      // Local media always closes first. This avoids billing an outbound media
      // leg after its UI is gone even if the completion request is offline.
      if (mediaSessionId != null && mediaSessionId.isNotEmpty) {
        await (finishingMedia ?? _webView).endMedia(mediaSessionId);
      } else if (finishingMedia != null) {
        await finishingMedia.abandonMediaPreparation();
      }
      if (hasNativeCall) {
        try {
          await _native.dismiss(_identityFor(oldState));
        } catch (_) {
          // Backend completion must not resurrect a locally-ended system call.
        }
      }
      state = const CallSessionState();
      if (isOutbound) {
        await _api.completeOutbound(
          callSid: callSid,
          connectedDuration: oldState.elapsed,
        );
      } else if (wasBackendCall) {
        if (decline && offerId != null) {
          await _api.decline(
            callId: callId,
            offerId: offerId,
            installationId: await _installationId(),
            reason: reason,
          );
        } else {
          await _api.end(callId: callId, reason: reason);
        }
      }
    } catch (error) {
      // Local media and the OS call surface are authoritative for teardown.
      // A late/offline completion request must never resurrect the call UI or
      // leave Telecom believing another call is still active.
      developer.log(
        'Backend call completion pending identity='
        '${callId ?? callSid ?? "unknown"} error=${error.runtimeType}.',
        name: 'CallSession',
      );
      if (state.hasCall) state = const CallSessionState();
    } finally {
      _isFinishing = false;
      // Keep the next user-initiated call off the cold path. The media
      // service validates bridge/client health before reusing anything, so a
      // failed or reclaimed WebView still takes the one-fresh-client path.
      if (!state.hasCall) unawaited(prewarmMedia());
    }
  }

  Future<void> recover(ActiveCallSnapshot? snapshot) async {
    if (snapshot == null || state.hasCall) return;
    // `/calls/active` does not currently expose the installation that owns
    // the call. A snapshot without an offer cannot be proven to belong to
    // this handset, so restoring it could resurrect a call that was answered
    // on another device. Fail closed until the backend returns ownership.
    if (snapshot.offerId == null ||
        _ownershipDeniedCallIds.contains(snapshot.callId)) {
      developer.log(
        'Ignored active-call recovery callId=${snapshot.callId}; '
        'ownership cannot be proven locally.',
        name: 'CallSession',
      );
      return;
    }
    // A server-side accepted/active row is not sufficient to resurrect media
    // on a fresh Flutter process. The prior implementation displayed a
    // permanent Connecting screen after Android had already rejected or
    // cancelled the corresponding Telecom call. Until the backend includes
    // installation ownership and recoverable media-session state, require a
    // matching durable native offer as local proof.
    final nativeOffer = await _native.peekPendingOffer();
    if (nativeOffer == null ||
        nativeOffer.callId != snapshot.callId ||
        nativeOffer.offerId != snapshot.offerId) {
      developer.log(
        'Ignored active-call recovery callId=${snapshot.callId}; '
        'no matching local native offer/media ownership.',
        name: 'CallSession',
      );
      return;
    }
    final party = CallParty(
      customerId: snapshot.customerId,
      displayName: snapshot.customerName?.trim().isNotEmpty == true
          ? snapshot.customerName!.trim()
          : snapshot.remoteNumber,
      phoneNumber: snapshot.remoteNumber,
    );
    state = CallSessionState(
      lifecycle: snapshot.phase == CallPhase.incomingRinging
          ? CallLifecycle.incomingRinging
          : CallLifecycle.connecting,
      phase: snapshot.phase,
      party: party,
      callId: snapshot.callId,
      offerId: snapshot.offerId,
      ticketId: snapshot.ticketId,
      ticketNumber: snapshot.ticketNumber,
      category: snapshot.category,
      startedAt: snapshot.answeredAt,
    );
  }

  void minimize() {
    if (!state.hasCall) return;
    state = state.copyWith(
      presentation: CallPresentation.collapsed,
      keypadVisible: false,
    );
  }

  void restore() {
    if (!state.hasCall) return;
    state = state.copyWith(presentation: CallPresentation.fullscreen);
  }

  Future<void> toggleMute() async {
    if (!state.hasCall) return;
    final enabled = !state.muted;
    state = state.copyWith(muted: enabled);
    try {
      await _media.setMuted(enabled);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        muted: !enabled,
        failureMessage: _messageFor(error),
      );
    }
  }

  Future<void> toggleSpeaker() async {
    if (!state.hasCall) return;
    final enabled = !state.speakerEnabled;
    state = state.copyWith(speakerEnabled: enabled);
    try {
      await _native.setSystemSpeaker(enabled);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        speakerEnabled: !enabled,
        failureMessage: _messageFor(error),
      );
    }
  }

  Future<void> toggleHold() async {
    if (!state.isActive) return;
    final enabled = !state.onHold;
    state = state.copyWith(
      onHold: enabled,
      phase: enabled ? CallPhase.held : CallPhase.active,
    );
    try {
      await _media.setHeld(enabled);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        onHold: !enabled,
        phase: !enabled ? CallPhase.held : CallPhase.active,
        failureMessage: _messageFor(error),
      );
    }
  }

  void openKeypad() {
    if (!state.hasCall) return;
    state = state.copyWith(keypadVisible: true);
  }

  void closeKeypad() => state = state.copyWith(keypadVisible: false);

  Future<void> appendDtmfDigit(String digit) async {
    if (!state.keypadVisible || !RegExp(r'^[0-9*#]$').hasMatch(digit)) return;
    if (!state.isActive) return;
    try {
      await _media.sendDtmf(digit);
      if (!ref.mounted) return;
      state = state.copyWith(dtmfDigits: '${state.dtmfDigits}$digit');
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(failureMessage: _messageFor(error));
    }
  }

  void deleteLastDtmfDigit() {
    if (!state.keypadVisible || state.dtmfDigits.isEmpty) return;
    state = state.copyWith(
      dtmfDigits: state.dtmfDigits.substring(0, state.dtmfDigits.length - 1),
    );
  }

  void clearDtmfDigits() {
    if (!state.keypadVisible || state.dtmfDigits.isEmpty) return;
    state = state.copyWith(dtmfDigits: '');
  }

  void _onNativeEvent(NativeCallEvent event) {
    // Media lifecycle now flows through CallMediaService; this listener only
    // handles CallKit/Telecom user actions, which arrive on the native
    // channel regardless of the active media engine. `end` additionally
    // matches by provider/session IDs because outbound surfaces may not
    // carry a canonical call ID yet.
    final matches = (event.callId != null && event.callId == state.callId) ||
        (event.callSid != null && event.callSid == state.callSid) ||
        (event.mediaSessionId != null &&
            event.mediaSessionId == state.mediaSessionId);
    if (!matches) return;
    switch (event.type) {
      case NativeCallEventType.offerAvailable:
      case NativeCallEventType.nativePushTokenChanged:
      case NativeCallEventType.answer:
        unawaited(answer());
      case NativeCallEventType.decline:
        unawaited(decline());
      case NativeCallEventType.end:
        unawaited(end());
      case NativeCallEventType.incomingPresented:
      case NativeCallEventType.incomingOpened:
        if (event.type == NativeCallEventType.incomingOpened &&
            state.lifecycle == CallLifecycle.incomingRinging) {
          state = state.copyWith(nativeIncomingSurfaceActive: false);
        }
        break;
      case NativeCallEventType.outgoingDialing:
      case NativeCallEventType.active:
      case NativeCallEventType.failed:
        break;
      case NativeCallEventType.disconnected:
        _handleRemoteDisconnect(event.reason);
    }
  }

  /// Media-engine events from the hidden WebView client.
  void _onMediaEvent(CallMediaService source, CallMediaEvent event) {
    if (!state.hasCall || !identical(source, _activeMedia)) return;
    developer.log(
      'Media event type=${event.type.name} callSid=${event.callSid ?? "none"} '
      'mediaSession=${event.mediaSessionId ?? "none"} reason=${event.reason ?? "none"}.',
      name: 'CallSession',
    );
    final expectedSessionId = state.mediaSessionId;
    if (event.mediaSessionId != null &&
        expectedSessionId != null &&
        event.mediaSessionId != expectedSessionId) {
      return;
    }
    final expectedCallSid = state.callSid;
    if (event.callSid != null &&
        expectedCallSid != null &&
        event.callSid != expectedCallSid &&
        event.type != CallMediaEventType.incoming) {
      return;
    }
    switch (event.type) {
      case CallMediaEventType.ready:
      case CallMediaEventType.ringing:
        break;
      case CallMediaEventType.micStatus:
        if ((event.reason ?? '').toLowerCase().contains('granted')) {
          unawaited(
            _reportClientEvent(CallClientEvent.microphoneCaptureReady),
          );
        }
        break;
      case CallMediaEventType.incoming:
        unawaited(_reportClientEvent(CallClientEvent.incoming));
        final incoming = _incomingMedia;
        if (incoming != null && !incoming.isCompleted) incoming.complete();
      case CallMediaEventType.connected:
        _markAttemptPhase('connected');
        unawaited(_reportClientEvent(CallClientEvent.connected));
        if (!state.isActive) _activate(DateTime.now().toUtc());
      case CallMediaEventType.held:
        state = state.copyWith(onHold: true, phase: CallPhase.held);
      case CallMediaEventType.ended:
        _handleRemoteMediaEnded(event.reason);
      case CallMediaEventType.error:
        unawaited(_reportClientEvent(CallClientEvent.bridgeError));
        _fail(event.reason ?? 'The call connection failed.');
      case CallMediaEventType.processTerminated:
        _fail(event.reason ??
            'The call engine stopped unexpectedly. Please redial.');
    }
  }

  void _activate(DateTime connectedAt) {
    developer.log('Call media connected; starting duration timer.',
        name: 'CallSession');
    _durationTimer?.cancel();
    state = state.copyWith(
      lifecycle: CallLifecycle.active,
      phase: CallPhase.active,
      startedAt: connectedAt,
      elapsed: DateTime.now().toUtc().difference(connectedAt),
      failureMessage: null,
    );
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isActive || state.startedAt == null) return;
      state = state.copyWith(
        elapsed: DateTime.now().toUtc().difference(state.startedAt!),
      );
    });
    unawaited(_native.markActive(_identityFor(state)).catchError((_) {}));
  }

  /// A backend cancellation reaches Android as a native event. It is not a
  /// local hang-up and must not issue a duplicate /end call to the server.
  ///
  /// FCM-delivered cancellations (APNs background pushes on iOS) arrive
  /// through the lifecycle coordinator instead of the native channel; this
  /// entry point applies the same identity-strict teardown for them.
  void handleRemoteCancellation({String? callId, String? reason}) {
    if (!matchesNativeIdentity(callId: callId)) return;
    _handleRemoteDisconnect(reason ?? 'call_cancelled');
  }

  void _handleRemoteDisconnect(String? reason) {
    if (!state.hasCall) return;
    if ((reason ?? '').toLowerCase().contains('answered_elsewhere')) {
      final callId = state.callId;
      if (callId != null && callId.isNotEmpty) {
        _ownershipDeniedCallIds.add(callId);
      }
    }
    _showTerminalNotice(
      reason: reason,
      phase: _phaseForRemoteReason(reason),
      message: _messageForRemoteReason(reason),
    );
    developer.log(
      'Remote/native call terminal notice shown reason=${reason ?? "none"}.',
      name: 'CallSession',
    );
  }

  void _handleRemoteMediaEnded(String? reason) {
    if (!state.hasCall || state.isTerminalNotice) return;
    _showTerminalNotice(
      reason: reason,
      phase: _phaseForRemoteReason(reason),
      message: _messageForRemoteReason(reason),
    );
  }

  void _showTerminalNotice({
    required String? reason,
    required CallPhase phase,
    required String message,
  }) {
    final terminal = state;
    final callId = terminal.callId;
    _durationTimer?.cancel();
    _terminalTimer?.cancel();
    _incomingMedia = null;
    final media = _activeMedia;
    final mediaSessionId = terminal.mediaSessionId;
    _activeMedia = null;
    _backendAccepted = false;
    _acceptedInstallationId = null;
    _reportedClientEvents.clear();
    _attemptClock?.stop();
    _attemptClock = null;
    state = terminal.copyWith(
      lifecycle: CallLifecycle.terminalNotice,
      phase: phase,
      keypadVisible: false,
      nativeIncomingSurfaceActive: false,
      failureMessage: message,
    );
    if (media != null && mediaSessionId != null && mediaSessionId.isNotEmpty) {
      unawaited(media.endMedia(mediaSessionId).catchError((_) {}));
    } else if (media != null) {
      unawaited(media.abandonMediaPreparation().catchError((_) {}));
    }
    if (terminal.callId != null || terminal.callSid != null) {
      unawaited(_native.dismiss(_identityFor(terminal)).catchError((_) {}));
    }
    _terminalTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!ref.mounted ||
          state.callId != callId ||
          state.lifecycle != CallLifecycle.terminalNotice) {
        return;
      }
      state = const CallSessionState();
      unawaited(prewarmMedia());
    });
  }

  CallPhase _phaseForRemoteReason(String? reason) {
    final normalized = (reason ?? '').toLowerCase();
    if (normalized.contains('answered_elsewhere')) {
      return CallPhase.answeredElsewhere;
    }
    if (normalized.contains('expired')) return CallPhase.expired;
    if (normalized.contains('declin') ||
        normalized.contains('reject') ||
        normalized.contains('busy')) {
      return CallPhase.declined;
    }
    if (normalized.contains('cancel')) return CallPhase.cancelled;
    return CallPhase.completed;
  }

  String _messageForRemoteReason(String? reason) {
    final normalized = (reason ?? '').toLowerCase();
    if (normalized.contains('answered_elsewhere')) {
      return 'Answered on another device';
    }
    if (normalized.contains('expired')) return 'Call offer expired';
    if (normalized.contains('declin') ||
        normalized.contains('reject') ||
        normalized.contains('busy')) {
      return 'Call declined';
    }
    return 'Call ended';
  }

  void _fail(String message) {
    developer.log('Call session failed: $message', name: 'CallSession');
    _durationTimer?.cancel();
    _incomingMedia = null;
    final media = _activeMedia;
    final mediaSessionId = state.mediaSessionId;
    _activeMedia = null;
    final acceptedCallId = _backendAccepted ? state.callId : null;
    _backendAccepted = false;
    _acceptedInstallationId = null;
    _reportedClientEvents.clear();
    _attemptClock?.stop();
    _attemptClock = null;
    if (media != null && mediaSessionId != null && mediaSessionId.isNotEmpty) {
      unawaited(media.endMedia(mediaSessionId).catchError((_) {}));
    } else if (media != null) {
      unawaited(media.abandonMediaPreparation().catchError((_) {}));
    }
    state = state.copyWith(
      lifecycle: CallLifecycle.failed,
      phase: CallPhase.failed,
      keypadVisible: false,
      failureMessage: message,
    );
    final failed = state;
    if (failed.callId != null || failed.callSid != null) {
      unawaited(_native
          .markFailed(_identityFor(failed), reason: message)
          .catchError((_) {}));
    }
    // If this handset won the backend claim but failed before media could be
    // prepared, release the backend call instead of leaving it accepted and
    // recoverable by another lifecycle pass.
    if (acceptedCallId != null &&
        acceptedCallId.isNotEmpty &&
        !failed.isActive) {
      unawaited(_api
          .end(callId: acceptedCallId, reason: 'media_setup_failed')
          .catchError((_) {}));
    }
  }

  Future<void> _waitForIncomingMedia(CallId callId) async {
    final incoming = _incomingMedia;
    if (incoming == null) {
      throw const MediaUnavailable(
        'The call media engine was not ready for an incoming call.',
      );
    }
    try {
      await incoming.future.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const MediaUnavailable(
        'The provider did not connect the incoming call in time.',
      );
    } finally {
      if (state.callId == callId) _incomingMedia = null;
    }
  }

  NativeCallIdentity _identityFor(CallSessionState session) {
    final party = session.party;
    return NativeCallIdentity(
      callId: session.callId,
      callSid: session.callSid,
      displayName: party?.displayName ?? 'Unknown caller',
      phoneNumber: party?.phoneNumber ?? '',
    );
  }

  String _messageFor(Object error) {
    if (error is CallApiException) return error.message;
    if (error is NativeCallUnavailable) return error.message;
    if (error is MediaUnavailable) return error.message;
    // Native adapter failures arrive as PlatformException (FlutterError from
    // the method channel). Surface their message: it names the failing layer
    // (engine init, SIP registration, INVITE) instead of a generic string.
    if (error is PlatformException) {
      final detail = error.message?.trim();
      if (detail != null && detail.isNotEmpty) return detail;
    }
    return 'Unable to set up this call. Please try again.';
  }
}
