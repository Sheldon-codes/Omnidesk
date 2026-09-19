import 'dart:async';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/calls/call_api.dart';
import '../../services/calls/call_media_provider.dart';
import '../../services/calls/call_media_service.dart';
import '../../services/calls/call_models.dart';
import '../../services/calls/device_installation_service.dart';
import '../../services/calls/native_call_service.dart';
import '../../services/calls/webview_call_media_service.dart';

part 'call_session_controller.g.dart';

/// Presentation-oriented lifecycle retained for the existing call UI.
/// [phase] carries the richer transport lifecycle used by the controller.
enum CallLifecycle {
  idle,
  incomingRinging,
  outgoingRinging,
  connecting,
  active,
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
  final String? failureMessage;

  bool get hasCall => lifecycle != CallLifecycle.idle && party != null;
  bool get isIncoming => phase == CallPhase.incomingRinging;
  bool get isActive => lifecycle == CallLifecycle.active;
  bool get isBackendCall => callId != null && callId!.isNotEmpty;

  String get statusLabel => switch (lifecycle) {
        CallLifecycle.idle => '',
        CallLifecycle.incomingRinging => 'Incoming call',
        CallLifecycle.outgoingRinging => 'Calling…',
        CallLifecycle.connecting => 'Connecting…',
        CallLifecycle.active => formatCallDuration(elapsed),
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
  StreamSubscription<NativeCallEvent>? _nativeEvents;
  StreamSubscription<CallMediaEvent>? _baresipEvents;
  StreamSubscription<CallMediaEvent>? _webViewEvents;
  CallMediaService? _activeMedia;
  bool _isFinishing = false;

  CallApi get _api => ref.read(callApiProvider);
  Future<String> Function() get _installationId =>
      ref.read(callInstallationIdProvider);
  NativeCallService get _native => ref.read(nativeCallServiceProvider);
  CallMediaService get _baresip => ref.read(baresipCallMediaServiceProvider);
  CallMediaService get _webView => ref.read(webViewCallMediaServiceProvider);

  /// Engine that owns the current call surface, if any. Falls back to the
  /// SIP path to preserve pre-seam behavior when no call is active.
  CallMediaService get _media => _activeMedia ?? _baresip;

  /// Backend-driven engine choice: a `transport: "webrtc"` media-config
  /// (no SIP block) must go to the hidden WebView engine, never Baresip.
  CallMediaService _selectMedia(CallMediaConfig config) {
    final forceWebView = ref.read(useWebViewMediaProvider);
    final useWebView =
        useWebViewEngine(forceWebView: forceWebView, config: config);
    _activeMedia = useWebView ? _webView : _baresip;
    return _activeMedia!;
  }

  @override
  CallSessionState build() {
    _nativeEvents = _native.events.listen(_onNativeEvent);
    // Both engines feed the same handler; only the selected engine emits
    // during a call, so subscribing to both is safe.
    _baresipEvents = _baresip.events.listen(
      (event) => _onMediaEvent(_baresip, event),
    );
    _webViewEvents = _webView.events.listen(
      (event) => _onMediaEvent(_webView, event),
    );
    ref.onDispose(() {
      _durationTimer?.cancel();
      unawaited(_nativeEvents?.cancel() ?? Future<void>.value());
      unawaited(_baresipEvents?.cancel() ?? Future<void>.value());
      unawaited(_webViewEvents?.cancel() ?? Future<void>.value());
    });
    return const CallSessionState();
  }

  /// Receives a canonical offer from FCM/PushKit after workspace validation.
  Future<bool> handleIncomingOffer(CallOffer offer) async {
    if (offer.isExpired || state.hasCall) return false;
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
    try {
      await _native.presentIncoming(offer);
      final installationId = await _installationId();
      unawaited(_api.acknowledgeDelivery(
        callId: offer.callId,
        installationId: installationId,
      ));
      return true;
    } catch (error) {
      _fail(_messageFor(error));
      return false;
    }
  }

  /// Starts the documented outbound signal, registration, then SIP INVITE
  /// flow. The native `connected` event, not the originate response, starts
  /// the displayed duration clock.
  bool startOutgoing(CallParty party, {String? ticketId}) {
    if (state.hasCall) return false;
    state = CallSessionState(
      lifecycle: CallLifecycle.connecting,
      phase: CallPhase.outgoingPreparing,
      party: party,
      ticketId: ticketId,
    );
    unawaited(_initiateOutgoing(party, ticketId: ticketId));
    return true;
  }

  Future<void> _initiateOutgoing(
    CallParty party, {
    String? ticketId,
  }) async {
    OutboundCallResult? created;
    try {
      created = await _api.initiateOutbound(
        toNumber: party.phoneNumber,
        ticketId: ticketId,
      );
      final result = created;
      // Ignore a late response after the agent has ended the local surface.
      if (state.party != party || state.phase != CallPhase.outgoingPreparing) {
        return;
      }
      final config = await _api.getMediaConfig();
      if (!config.canAuthenticate && !config.canUseWebRtc) {
        throw const CallApiException(
          CallApiErrorKind.unavailable,
          'The call service did not provide a usable media credential.',
        );
      }
      final media = _selectMedia(config);
      final registrationSessionId = await media.initialize(config);
      if (state.party != party || state.lifecycle == CallLifecycle.failed) {
        await media.endMedia(registrationSessionId);
        return;
      }
      // Retain the provider identifier before dialing: a fast native connect
      // event is allowed to arrive before `dial` returns.
      state = state.copyWith(
        callId: result.callId,
        callSid: result.callSid,
        mediaSessionId: registrationSessionId,
        failureMessage: null,
      );
      final mediaSessionId = await media.dial(
        callSid: result.callSid,
        phoneNumber: result.normalizedToNumber ?? party.phoneNumber,
        sipTargetUri: result.sipUri,
      );
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
      state = state.copyWith(
        lifecycle: CallLifecycle.connecting,
        phase: CallPhase.accepted,
        failureMessage: null,
      );
      final installationId = await _installationId();
      final accepted = await _api.accept(
        callId: callId,
        offerId: offerId,
        installationId: installationId,
      );
      state = state.copyWith(
        phase: CallPhase.mediaPreparing,
        startedAt: accepted.answeredAt,
      );
      final config = await _api.getMediaConfig();
      if (!config.canAuthenticate && !config.canUseWebRtc) {
        throw const CallApiException(
          CallApiErrorKind.unavailable,
          'The call service did not provide a usable media credential.',
        );
      }
      final mediaSessionId =
          await _selectMedia(config).initialize(config, incomingCallId: callId);
      if (state.callId != callId || state.lifecycle == CallLifecycle.failed) {
        await _media.endMedia(mediaSessionId);
        return;
      }
      await _api.mediaReady(
        callId: callId,
        offerId: offerId,
        installationId: installationId,
      );
      state = state.copyWith(
        phase: CallPhase.connecting,
        mediaSessionId: mediaSessionId,
      );
      // Unlike SIP, the WebRTC bridge owns an actual pending browser-side
      // call. The backend claim/media-ready handshake alone does not answer
      // that session.
      await _media.answerIncoming(callSid: callId);
      // Native media emits `connected`; only that starts the duration clock.
    } catch (error) {
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
    final finishingState = state;
    final callId = finishingState.callId;
    final offerId = state.offerId;
    final callSid = finishingState.callSid;
    final mediaSessionId = finishingState.mediaSessionId;
    final isOutbound = callSid != null && callSid.isNotEmpty;
    final wasBackendCall = callId != null && callId.isNotEmpty;
    _durationTimer?.cancel();
    final finishingMedia = _activeMedia;
    _activeMedia = null;
    final oldState = finishingState;
    state = const CallSessionState();
    try {
      // Local media always closes first. This avoids billing an outbound media
      // leg after its UI is gone even if the completion request is offline.
      if (mediaSessionId != null && mediaSessionId.isNotEmpty) {
        await (finishingMedia ?? _baresip).endMedia(mediaSessionId);
      }
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
      // The backend did not confirm termination. Preserve a retryable failed
      // surface; successful termination is never undone by local cleanup.
      if (!state.hasCall) {
        state = oldState.copyWith(
          lifecycle: CallLifecycle.failed,
          phase: CallPhase.failed,
          failureMessage: _messageFor(error),
        );
      }
    } finally {
      // CallKit cleanup remains best-effort after native media has closed.
      if (wasBackendCall) {
        try {
          await _native.dismiss(callId);
        } catch (_) {
          // The next native-media implementation will reconcile its own state.
        }
      }
      _isFinishing = false;
    }
  }

  Future<void> recover(ActiveCallSnapshot? snapshot) async {
    if (snapshot == null || state.hasCall) return;
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
      state = state.copyWith(failureMessage: _messageFor(error));
    }
  }

  Future<void> toggleSpeaker() async {
    if (!state.hasCall) return;
    final enabled = !state.speakerEnabled;
    state = state.copyWith(speakerEnabled: enabled);
    try {
      await _native.setSpeaker(enabled);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(failureMessage: _messageFor(error));
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
      state = state.copyWith(failureMessage: _messageFor(error));
    }
  }

  void openKeypad() {
    if (!state.hasCall) return;
    state = state.copyWith(keypadVisible: true);
  }

  void closeKeypad() => state = state.copyWith(keypadVisible: false);

  Future<void> appendDtmfDigit(String digit) async {
    if (!state.keypadVisible || !RegExp(r'^[0-9*#]$').hasMatch(digit)) return;
    state = state.copyWith(dtmfDigits: '${state.dtmfDigits}$digit');
    if (!state.isActive) return;
    try {
      await _media.sendDtmf(digit);
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
        (event.type == NativeCallEventType.end &&
            ((event.callSid != null && event.callSid == state.callSid) ||
                (event.mediaSessionId != null &&
                    event.mediaSessionId == state.mediaSessionId)));
    if (!matches) return;
    switch (event.type) {
      case NativeCallEventType.answer:
        unawaited(answer());
      case NativeCallEventType.decline:
        unawaited(decline());
      case NativeCallEventType.end:
        unawaited(end());
      case NativeCallEventType.connected:
      case NativeCallEventType.held:
      case NativeCallEventType.ringing:
      case NativeCallEventType.registered:
      case NativeCallEventType.disconnected:
      case NativeCallEventType.failed:
        break;
    }
  }

  /// Media-engine events, engine-agnostic (Baresip SIP or hidden WebView).
  void _onMediaEvent(CallMediaService source, CallMediaEvent event) {
    if (!state.hasCall || !identical(source, _activeMedia)) return;
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
      case CallMediaEventType.incoming:
      case CallMediaEventType.micStatus:
        break;
      case CallMediaEventType.connected:
        if (!state.isActive) _activate(DateTime.now().toUtc());
      case CallMediaEventType.held:
        state = state.copyWith(onHold: true, phase: CallPhase.held);
      case CallMediaEventType.ended:
        unawaited(end());
      case CallMediaEventType.error:
        _fail(event.reason ?? 'The call connection failed.');
      case CallMediaEventType.processTerminated:
        _fail(event.reason ??
            'The call engine stopped unexpectedly. Please redial.');
    }
  }

  void _activate(DateTime connectedAt) {
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
  }

  void _fail(String message) {
    _durationTimer?.cancel();
    final media = _activeMedia;
    final mediaSessionId = state.mediaSessionId;
    _activeMedia = null;
    if (media != null && mediaSessionId != null && mediaSessionId.isNotEmpty) {
      unawaited(media.endMedia(mediaSessionId).catchError((_) {}));
    }
    state = state.copyWith(
      lifecycle: CallLifecycle.failed,
      phase: CallPhase.failed,
      keypadVisible: false,
      failureMessage: message,
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
