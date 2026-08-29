import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'call_session_controller.g.dart';

enum CallLifecycle { idle, incomingRinging, outgoingRinging, active }

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
    this.presentation = CallPresentation.fullscreen,
    this.party,
    this.startedAt,
    this.elapsed = Duration.zero,
    this.muted = false,
    this.speakerEnabled = false,
    this.onHold = false,
    this.keypadVisible = false,
    this.dtmfDigits = '',
  });

  final CallLifecycle lifecycle;
  final CallPresentation presentation;
  final CallParty? party;
  final DateTime? startedAt;
  final Duration elapsed;
  final bool muted;
  final bool speakerEnabled;
  final bool onHold;
  final bool keypadVisible;
  final String dtmfDigits;

  bool get hasCall => lifecycle != CallLifecycle.idle && party != null;

  String get statusLabel => switch (lifecycle) {
        CallLifecycle.idle => '',
        CallLifecycle.incomingRinging => 'Incoming call',
        CallLifecycle.outgoingRinging => 'Calling…',
        CallLifecycle.active => formatCallDuration(elapsed),
      };

  CallSessionState copyWith({
    CallLifecycle? lifecycle,
    CallPresentation? presentation,
    Object? party = _keep,
    Object? startedAt = _keep,
    Duration? elapsed,
    bool? muted,
    bool? speakerEnabled,
    bool? onHold,
    bool? keypadVisible,
    String? dtmfDigits,
  }) =>
      CallSessionState(
        lifecycle: lifecycle ?? this.lifecycle,
        presentation: presentation ?? this.presentation,
        party: identical(party, _keep) ? this.party : party as CallParty?,
        startedAt: identical(startedAt, _keep)
            ? this.startedAt
            : startedAt as DateTime?,
        elapsed: elapsed ?? this.elapsed,
        muted: muted ?? this.muted,
        speakerEnabled: speakerEnabled ?? this.speakerEnabled,
        onHold: onHold ?? this.onHold,
        keypadVisible: keypadVisible ?? this.keypadVisible,
        dtmfDigits: dtmfDigits ?? this.dtmfDigits,
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
  Timer? _connectionTimer;
  Timer? _durationTimer;

  @override
  CallSessionState build() {
    ref.onDispose(_cancelTimers);
    return const CallSessionState();
  }

  bool startIncoming(CallParty party) {
    if (state.hasCall) return false;
    _cancelTimers();
    state = CallSessionState(
      lifecycle: CallLifecycle.incomingRinging,
      party: party,
    );
    return true;
  }

  bool startOutgoing(CallParty party) {
    if (state.hasCall) return false;
    _cancelTimers();
    state = CallSessionState(
      lifecycle: CallLifecycle.outgoingRinging,
      party: party,
    );
    _connectionTimer = Timer(const Duration(seconds: 3), connectOutgoing);
    return true;
  }

  void answer() {
    if (state.lifecycle != CallLifecycle.incomingRinging) return;
    _activate();
  }

  void connectOutgoing() {
    if (state.lifecycle != CallLifecycle.outgoingRinging) return;
    _activate();
  }

  void decline() => end();

  void end() {
    _cancelTimers();
    state = const CallSessionState();
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

  void toggleMute() {
    if (!state.hasCall) return;
    state = state.copyWith(muted: !state.muted);
  }

  void toggleSpeaker() {
    if (!state.hasCall) return;
    state = state.copyWith(speakerEnabled: !state.speakerEnabled);
  }

  void toggleHold() {
    if (state.lifecycle != CallLifecycle.active) return;
    state = state.copyWith(onHold: !state.onHold);
  }

  void openKeypad() {
    if (!state.hasCall) return;
    state = state.copyWith(keypadVisible: true);
  }

  void closeKeypad() => state = state.copyWith(keypadVisible: false);

  void appendDtmfDigit(String digit) {
    if (!state.keypadVisible || !RegExp(r'^[0-9*#]$').hasMatch(digit)) return;
    state = state.copyWith(dtmfDigits: '${state.dtmfDigits}$digit');
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

  void _activate() {
    _connectionTimer?.cancel();
    final startedAt = DateTime.now();
    state = state.copyWith(
      lifecycle: CallLifecycle.active,
      startedAt: startedAt,
      elapsed: Duration.zero,
    );
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.lifecycle != CallLifecycle.active || state.startedAt == null) {
        return;
      }
      state = state.copyWith(
        elapsed: DateTime.now().difference(state.startedAt!),
      );
    });
  }

  void _cancelTimers() {
    _connectionTimer?.cancel();
    _durationTimer?.cancel();
    _connectionTimer = null;
    _durationTimer = null;
  }
}
