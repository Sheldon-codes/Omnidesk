import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/calls/call_api.dart';
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

  CallApi get _api => ref.read(callApiProvider);
  Future<String> Function() get _installationId =>
      ref.read(callInstallationIdProvider);
  NativeCallService get _native => ref.read(nativeCallServiceProvider);

  @override
  CallSessionState build() {
    _nativeEvents = _native.events.listen(_onNativeEvent);
    ref.onDispose(() {
      _durationTimer?.cancel();
      unawaited(_nativeEvents?.cancel() ?? Future<void>.value());
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

  /// Temporary, explicitly local visual demo. Production offers must enter via
  /// [handleIncomingOffer], where the backend's offer ID is required.
  bool startDemoIncoming(CallParty party) {
    if (state.hasCall) return false;
    state = CallSessionState(
      lifecycle: CallLifecycle.incomingRinging,
      phase: CallPhase.incomingRinging,
      party: party,
    );
    return true;
  }

  @Deprecated('Use handleIncomingOffer for live calls or startDemoIncoming.')
  bool startIncoming(CallParty party) => startDemoIncoming(party);

  /// Outbound calling is unavailable until the backend exposes a mobile
  /// originate contract. It intentionally does not recreate the old timer.
  bool startOutgoing(CallParty party) {
    if (state.hasCall) return false;
    state = CallSessionState(
      failureMessage:
          'Outgoing calling is not enabled by the call service yet.',
    );
    return false;
  }

  Future<void> answer() async {
    if (state.lifecycle != CallLifecycle.incomingRinging) return;
    if (!state.isBackendCall || state.offerId == null) {
      // Demo-only flow; never used for a live incoming offer.
      _activate(DateTime.now().toUtc());
      return;
    }
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
      if (!config.canAuthenticate) {
        throw const CallApiException(
          CallApiErrorKind.unavailable,
          'The call service did not provide a native media credential.',
        );
      }
      await _native.registerMedia(config);
      await _api.mediaReady(
        callId: callId,
        offerId: offerId,
        installationId: installationId,
      );
      state = state.copyWith(phase: CallPhase.connecting);
      // Native media emits `connected`; only that starts the duration clock.
    } catch (error) {
      _fail(_messageFor(error));
    }
  }

  /// Kept as a deterministic demo/test seam. Real activation is driven by a
  /// native media `connected` event.
  void connectOutgoing() {
    if (state.lifecycle == CallLifecycle.outgoingRinging) {
      _activate(DateTime.now().toUtc());
    }
  }

  Future<void> decline() => _finish(reason: 'agent_declined', decline: true);

  Future<void> end() => _finish(reason: 'agent_hangup');

  Future<void> _finish({required String reason, bool decline = false}) async {
    final callId = state.callId;
    final offerId = state.offerId;
    final wasBackendCall = state.isBackendCall;
    _durationTimer?.cancel();
    final oldState = state;
    state = const CallSessionState();
    if (!wasBackendCall || callId == null) return;
    try {
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
      await _native.endMedia(callId);
      await _native.dismiss(callId);
    } catch (error) {
      // Always release local UI. Recovery later reconciles `/calls/active`.
      if (!state.hasCall) {
        state = oldState.copyWith(
          lifecycle: CallLifecycle.failed,
          phase: CallPhase.failed,
          failureMessage: _messageFor(error),
        );
      }
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
      await _native.setMuted(enabled);
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
      await _native.setHeld(enabled);
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
      await _native.sendDtmf(digit);
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
    if (event.callId != state.callId) return;
    switch (event.type) {
      case NativeCallEventType.answer:
        unawaited(answer());
      case NativeCallEventType.decline:
        unawaited(decline());
      case NativeCallEventType.end:
      case NativeCallEventType.disconnected:
        unawaited(end());
      case NativeCallEventType.connected:
        _activate(DateTime.now().toUtc());
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
    state = state.copyWith(
      lifecycle: CallLifecycle.failed,
      phase: CallPhase.failed,
      keypadVisible: false,
      failureMessage: message,
    );
  }

  String _messageFor(Object error) => error is CallApiException
      ? error.message
      : error is NativeCallUnavailable
          ? error.message
          : 'Unable to set up this call. Please try again.';
}
