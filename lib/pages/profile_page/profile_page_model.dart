import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../../models/auth/auth_models.dart';
import '../../services/api_service.dart';

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
  // Profile's richer multi-state presence remains local until the backend
  // exposes more than the dashboard's available/unavailable boolean.
  (ref) => LocalAgentPresenceRepository(),
);

class ProfileWorkspace {
  const ProfileWorkspace({
    required this.id,
    required this.name,
    required this.slug,
    required this.role,
    required this.isAvailable,
  });

  final String id;
  final String name;
  final String slug;
  final String role;
  final bool isAvailable;

  WorkspaceMembership toMembership() => WorkspaceMembership(
        id: id,
        name: name,
        slug: slug,
        role: role,
      );
}

abstract class ProfileWorkspaceRepository {
  Future<List<ProfileWorkspace>> loadWorkspaces();
  Future<ProfileWorkspace> switchWorkspace(String workspaceId);
}

class ApiProfileWorkspaceRepository implements ProfileWorkspaceRepository {
  ApiProfileWorkspaceRepository(this._api);
  final ApiService _api;

  @override
  Future<List<ProfileWorkspace>> loadWorkspaces() async {
    final response = await _api.get('/agent/workspaces');
    final data = response is Map ? response['workspaces'] : null;
    if (data is! List) {
      throw const FormatException('Invalid workspaces response.');
    }
    return data.whereType<Map>().map(_parse).toList(growable: false);
  }

  @override
  Future<ProfileWorkspace> switchWorkspace(String workspaceId) async {
    final response = await _api.post('/agent/workspaces/switch', {
      'workspace_id': int.tryParse(workspaceId) ?? workspaceId,
    });
    final active = response is Map ? response['activeWorkspace'] : null;
    if (active is! Map) {
      throw const FormatException('Invalid workspace response.');
    }
    return _parse(active);
  }

  ProfileWorkspace _parse(Map value) => ProfileWorkspace(
        id: value['id'].toString(),
        name: (value['name'] ?? '').toString(),
        slug: (value['slug'] ?? '').toString(),
        role: (value['role'] ?? 'agent').toString(),
        isAvailable:
            value['isAvailable'] == true || value['is_available'] == true,
      );
}

class LocalProfileWorkspaceRepository implements ProfileWorkspaceRepository {
  const LocalProfileWorkspaceRepository();
  @override
  Future<List<ProfileWorkspace>> loadWorkspaces() async => const [];
  @override
  Future<ProfileWorkspace> switchWorkspace(String workspaceId) =>
      throw StateError('Workspace switching is unavailable offline.');
}

class ProfileWorkspaceState {
  const ProfileWorkspaceState(
      {this.items = const [],
      this.loading = false,
      this.switching = false,
      this.failure});
  final List<ProfileWorkspace> items;
  final bool loading;
  final bool switching;
  final Object? failure;
  ProfileWorkspaceState copyWith(
          {List<ProfileWorkspace>? items,
          bool? loading,
          bool? switching,
          Object? failure = _keep}) =>
      ProfileWorkspaceState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        switching: switching ?? this.switching,
        failure: identical(failure, _keep) ? this.failure : failure,
      );
  static const _keep = Object();
}

final profileWorkspaceRepositoryProvider =
    Provider<ProfileWorkspaceRepository>((ref) {
  final api = ref.read(apiServiceProvider);
  return api.baseUrl.isEmpty
      ? const LocalProfileWorkspaceRepository()
      : ApiProfileWorkspaceRepository(api);
});

final profileWorkspacesProvider =
    NotifierProvider<ProfileWorkspaceController, ProfileWorkspaceState>(
        ProfileWorkspaceController.new);

class ProfileWorkspaceController extends Notifier<ProfileWorkspaceState> {
  @override
  ProfileWorkspaceState build() {
    Future.microtask(load);
    return const ProfileWorkspaceState(loading: true);
  }

  Future<void> load() async {
    try {
      state = state.copyWith(loading: true, failure: null);
      state = ProfileWorkspaceState(
          items: await ref
              .read(profileWorkspaceRepositoryProvider)
              .loadWorkspaces());
    } catch (error) {
      state = state.copyWith(loading: false, failure: error);
    }
  }

  Future<ProfileWorkspace?> switchWorkspace(String id) async {
    if (state.switching) return null;
    try {
      state = state.copyWith(switching: true, failure: null);
      final selected = await ref
          .read(profileWorkspaceRepositoryProvider)
          .switchWorkspace(id);
      state = state.copyWith(
        switching: false,
        items: [
          for (final item in state.items)
            item.id == selected.id ? selected : item
        ],
      );
      return selected;
    } catch (error) {
      state = state.copyWith(switching: false, failure: error);
      return null;
    }
  }
}

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
