import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../flutter_flow/flutter_flow_theme.dart';

/// The operational presence states accepted by the future agent-presence API.
enum PresenceStatus { available, busy, away, offline }

extension PresenceStatusLabels on PresenceStatus {
  String get label => switch (this) {
        PresenceStatus.available => 'Available',
        PresenceStatus.busy => 'Busy',
        PresenceStatus.away => 'Away',
        PresenceStatus.offline => 'Offline',
      };

  String get description => switch (this) {
        PresenceStatus.available =>
          'Ready to receive calls, chats and ticket assignments.',
        PresenceStatus.busy =>
          'Working on something. Reduce new interruptions.',
        PresenceStatus.away => 'Temporarily unavailable.',
        PresenceStatus.offline => 'Do not route new work to me.',
      };
}

class AgentPresenceState {
  const AgentPresenceState({
    this.status = PresenceStatus.available,
    this.receiveIncomingCalls = true,
    this.isSaving = false,
    this.failure,
  });

  final PresenceStatus status;
  final bool receiveIncomingCalls;
  final bool isSaving;
  final Object? failure;

  AgentPresenceState copyWith({
    PresenceStatus? status,
    bool? receiveIncomingCalls,
    bool? isSaving,
    Object? failure = _keep,
  }) =>
      AgentPresenceState(
        status: status ?? this.status,
        receiveIncomingCalls: receiveIncomingCalls ?? this.receiveIncomingCalls,
        isSaving: isSaving ?? this.isSaving,
        failure: identical(failure, _keep) ? this.failure : failure,
      );

  static const _keep = Object();
}

/// Repository seam for API-backed presence updates.
abstract class AgentPresenceRepository {
  Future<void> updateStatus(PresenceStatus status);
  Future<void> updateCallAvailability(bool enabled);
}

class LocalAgentPresenceRepository implements AgentPresenceRepository {
  @override
  Future<void> updateCallAvailability(bool enabled) async {}

  @override
  Future<void> updateStatus(PresenceStatus status) async {}
}

final agentPresenceRepositoryProvider = Provider<AgentPresenceRepository>(
  // The dashboard owns the live availability endpoint. Profile keeps its
  // richer multi-state presence controls local until that API supports them.
  (ref) => LocalAgentPresenceRepository(),
);

final agentPresenceProvider =
    NotifierProvider<AgentPresenceController, AgentPresenceState>(
  AgentPresenceController.new,
);

/// App-wide persisted display preference. FlutterFlowTheme owns the backing
/// SharedPreferences key so generated FlutterFlow surfaces keep the same mode.
final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, ThemeMode>(
  AppThemeModeController.new,
);

class AppThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => FlutterFlowTheme.themeMode;

  void setThemeMode(ThemeMode mode) {
    FlutterFlowTheme.saveThemeMode(mode);
    state = mode;
  }
}

class AgentPresenceController extends Notifier<AgentPresenceState> {
  _PresenceMutation? _lastMutation;

  @override
  AgentPresenceState build() => const AgentPresenceState();

  Future<bool> setStatus(PresenceStatus status) => _perform(
        _PresenceMutation.status(status),
        () => ref.read(agentPresenceRepositoryProvider).updateStatus(status),
        () => state.copyWith(status: status),
      );

  Future<bool> setReceiveIncomingCalls(bool enabled) => _perform(
        _PresenceMutation.calls(enabled),
        () => ref
            .read(agentPresenceRepositoryProvider)
            .updateCallAvailability(enabled),
        () => state.copyWith(receiveIncomingCalls: enabled),
      );

  Future<bool> retry() {
    final mutation = _lastMutation;
    if (mutation == null || state.isSaving) return Future.value(false);
    return mutation.status != null
        ? setStatus(mutation.status!)
        : setReceiveIncomingCalls(mutation.callAvailability!);
  }

  Future<bool> _perform(
    _PresenceMutation mutation,
    Future<void> Function() request,
    AgentPresenceState Function() onSuccess,
  ) async {
    if (state.isSaving) return false;
    _lastMutation = mutation;
    state = state.copyWith(isSaving: true, failure: null);
    try {
      await request();
      state = onSuccess().copyWith(isSaving: false, failure: null);
      return true;
    } catch (error) {
      state = state.copyWith(isSaving: false, failure: error);
      return false;
    }
  }
}

class _PresenceMutation {
  const _PresenceMutation.status(PresenceStatus value)
      : status = value,
        callAvailability = null;
  const _PresenceMutation.calls(bool value)
      : status = null,
        callAvailability = value;

  final PresenceStatus? status;
  final bool? callAvailability;
}
