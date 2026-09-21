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
  StreamSubscription<NativeCallEvent>? _nativeEvents;
  StreamSubscription<CallMediaEvent>? _webViewEvents;
  CallMediaService? _activeMedia;
  Completer<void>? _incomingMedia;
  bool _isFinishing = false;

  CallApi get _api => ref.read(callApiProvider);
  Future<String> Function() get _installationId =>
      ref.read(callInstallationIdProvider);
  NativeCallService get _native => ref.read(nativeCallServiceProvider);
  CallMediaService get _webView => ref.read(callMediaServiceProvider);

  /// WebRTC is the only supported production media implementation.
  CallMediaService get _media => _activeMedia ?? _webView;

  /// Backend-driven engine choice: a `transport: "webrtc"` media-config
  /// (no SIP block) must go to the hidden WebView engine, never Baresip.
  CallMediaService _selectMedia(CallMediaConfig config) {
    if (!usesSupportedWebViewMedia(config)) {
      throw const MediaUnavailable(
        'The call service returned an unsupported media transport.',
      );
    }
    _activeMedia = _webView;
    return _webView;
  }

  @override
  CallSessionState build() {
    _nativeEvents = _native.events.listen(_onNativeEvent);
    _webViewEvents = _webView.events.listen(
      (event) => _onMediaEvent(_webView, event),
    );
    ref.onDispose(() {
      _durationTimer?.cancel();
      unawaited(_nativeEvents?.cancel() ?? Future<void>.value());
      unawaited(_webViewEvents?.cancel() ?? Future<void>.value());
    });
    return const CallSessionState();
  }

  /// Receives a canonical offer from FCM/PushKit after workspace validation.
  Future<bool> handleIncomingOffer(CallOffer offer) async {
    developer.log(
      'Session received incoming offer callId=${offer.callId} '
      'offerId=${offer.offerId} hasExistingCall=${state.hasCall} '
      'expired=${offer.isExpired}.',
      name: 'CallSession',
    );
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
      developer.log(
        'Presenting incoming call callId=${offer.callId}.',
        name: 'CallSession',
      );
      final presentation = await _native.presentIncoming(offer);
      if (state.callId == offer.callId &&
          state.lifecycle == CallLifecycle.incomingRinging) {
        state = state.copyWith(nativeIncomingSurfaceActive: true);
      }
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
      state = state.copyWith(
        callId: result.callId,
        callSid: result.callSid,
        failureMessage: null,
      );
      await _native.beginOutgoing(_identityFor(state));
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
      developer.log(
        'Answer started callId=$callId offerId=$offerId.',
        name: 'CallSession',
      );
      state = state.copyWith(
        lifecycle: CallLifecycle.connecting,
        phase: CallPhase.accepted,
        nativeIncomingSurfaceActive: false,
        failureMessage: null,
      );
      final installationId = await _installationId();
      final accepted = await _api.accept(
        callId: callId,
        offerId: offerId,
        installationId: installationId,
      );
      developer.log('Backend accept confirmed callId=$callId.',
          name: 'CallSession');
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
      await _api.mediaReady(
        callId: callId,
        offerId: offerId,
        installationId: installationId,
      );
      developer.log('Backend media-ready confirmed callId=$callId.',
          name: 'CallSession');
      state = state.copyWith(
        phase: CallPhase.connecting,
        mediaSessionId: mediaSessionId,
      );
      // Africa's Talking delivers the media leg only after media-ready. Do
      // not answer merely because the backend handshake completed: wait for
      // the bridge's canonical incoming event, then accept that pending leg.
      await _waitForIncomingMedia(callId);
      developer.log(
        'Incoming WebRTC event received; answering media callId=$callId.',
        name: 'CallSession',
      );
      await _media.answerIncoming(callSid: callId);
      // Native media emits `connected`; only that starts the duration clock.
    } catch (error) {
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
        await (finishingMedia ?? _webView).endMedia(mediaSessionId);
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
          await _native.dismiss(_identityFor(oldState));
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
      await _native.setSystemSpeaker(enabled);
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

  /// Media-engine events, engine-agnostic (Baresip SIP or hidden WebView).
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
      case CallMediaEventType.micStatus:
        break;
      case CallMediaEventType.incoming:
        final incoming = _incomingMedia;
        if (incoming != null && !incoming.isCompleted) incoming.complete();
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
  void _handleRemoteDisconnect(String? reason) {
    if (!state.hasCall) return;
    _durationTimer?.cancel();
    _incomingMedia = null;
    final media = _activeMedia;
    final mediaSessionId = state.mediaSessionId;
    _activeMedia = null;
    state = const CallSessionState();
    if (media != null && mediaSessionId != null && mediaSessionId.isNotEmpty) {
      unawaited(media.endMedia(mediaSessionId).catchError((_) {}));
    }
    developer.log(
      'Remote/native call cancellation cleared local state reason=${reason ?? "none"}.',
      name: 'CallSession',
    );
  }

  void _fail(String message) {
    developer.log('Call session failed: $message', name: 'CallSession');
    _durationTimer?.cancel();
    _incomingMedia = null;
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
    final failed = state;
    if (failed.callId != null || failed.callSid != null) {
      unawaited(_native
          .markFailed(_identityFor(failed), reason: message)
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
