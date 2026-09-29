import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_service.dart';
import 'auth_session_controller.dart';
import 'response_cache.dart';

/// The lightweight server-owned totals used by navigation badges.
///
/// This deliberately does not infer counts from loaded inbox pages: those
/// pages can be filtered, paginated, or stale while the badges must describe
/// the agent's complete active workspace.
class AgentCounters {
  const AgentCounters({
    this.openTickets = 0,
    this.missedCalls = 0,
    this.whatsAppUnread = 0,
    this.emailUnread = 0,
    this.widgetUnread = 0,
  });

  final int openTickets;
  final int missedCalls;
  final int whatsAppUnread;
  final int emailUnread;
  final int widgetUnread;

  int get chatUnread => whatsAppUnread + widgetUnread;

  factory AgentCounters.fromJson(Object? raw) {
    final root = raw is Map
        ? raw.map((key, value) => MapEntry('$key', value))
        : <String, dynamic>{};
    final unread = root['unread_chats'] is Map
        ? (root['unread_chats'] as Map)
            .map((key, value) => MapEntry('$key', value))
        : <String, dynamic>{};
    int number(Object? value) {
      final parsed =
          value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;
      return parsed.clamp(0, 1 << 31).toInt();
    }

    return AgentCounters(
      openTickets: number(root['open_tickets']),
      missedCalls: number(root['missed_calls']),
      whatsAppUnread: number(unread['whatsapp']),
      emailUnread: number(unread['email']),
      widgetUnread: number(unread['widget']),
    );
  }

  Map<String, Object> toJson() => {
        'open_tickets': openTickets,
        'missed_calls': missedCalls,
        'unread_chats': {
          'whatsapp': whatsAppUnread,
          'email': emailUnread,
          'widget': widgetUnread,
        },
      };
}

class AgentCountersState {
  const AgentCountersState({
    this.counters = const AgentCounters(),
    this.hasLoaded = false,
    this.loading = false,
    this.refreshing = false,
    this.error,
  });

  final AgentCounters counters;

  /// True once a cache snapshot or a successful server response exists.
  ///
  /// All-zero counts are valid data and must never be mistaken for a cache
  /// miss, otherwise navigation badges would remain in a loading lifecycle.
  final bool hasLoaded;
  final bool loading;
  final bool refreshing;
  final Object? error;

  AgentCountersState copyWith({
    AgentCounters? counters,
    bool? hasLoaded,
    bool? loading,
    bool? refreshing,
    Object? error = _keep,
  }) =>
      AgentCountersState(
        counters: counters ?? this.counters,
        hasLoaded: hasLoaded ?? this.hasLoaded,
        loading: loading ?? this.loading,
        refreshing: refreshing ?? this.refreshing,
        error: identical(error, _keep) ? this.error : error,
      );

  static const _keep = Object();
}

class AgentCountersRepository {
  AgentCountersRepository(this._api, this._cache, this._readScope);

  final ApiService _api;
  final ResponseCache _cache;
  final ResponseCacheScope? Function() _readScope;

  Future<AgentCounters> load({
    required void Function(AgentCounters) onCached,
  }) async {
    final scope = _readScope();
    if (scope == null) return const AgentCounters();
    return (await CacheFirstJsonLoader(_cache).load(
      scope: scope,
      module: 'agent_counters',
      key: 'current',
      expectedEpoch: _cache.writeEpoch,
      fetch: () => _api.get('/agent/counters'),
      decode: AgentCounters.fromJson,
      onCached: onCached,
      onFresh: (_) {},
    ))
        .value;
  }
}

final agentCountersRepositoryProvider = Provider<AgentCountersRepository>(
  (ref) {
    final user = ref.watch(authSessionControllerProvider).session?.user;
    return AgentCountersRepository(
      ref.read(apiServiceProvider),
      ref.watch(responseCacheProvider),
      user == null ? () => null : () => ResponseCacheScope.fromUser(user),
    );
  },
);

final agentCountersProvider =
    NotifierProvider<AgentCountersController, AgentCountersState>(
  AgentCountersController.new,
);

class AgentCountersController extends Notifier<AgentCountersState> {
  static const _refreshInterval = Duration(seconds: 60);

  String? _scopeKey;
  int _generation = 0;
  Timer? _timer;
  bool _appActive = true;
  bool _callCritical = false;
  bool _deferredRefresh = false;
  Future<void>? _refreshInFlight;

  @override
  AgentCountersState build() {
    final authenticated =
        ref.read(authSessionControllerProvider).isAuthenticated;
    ref.listen<AuthState>(authSessionControllerProvider, (_, next) {
      Future.microtask(() {
        if (ref.mounted) _handleScopeChange(next);
      });
    }, fireImmediately: true);
    ref.onDispose(() => _timer?.cancel());
    return AgentCountersState(loading: authenticated);
  }

  void _handleScopeChange(AuthState auth) {
    final scope = auth.session == null
        ? 'anonymous'
        : '${auth.session!.user.id}:${auth.session!.user.activeWorkspace?.id ?? 'none'}';
    if (scope == _scopeKey) return;
    _scopeKey = scope;
    _generation++;
    _timer?.cancel();
    state = AgentCountersState(loading: auth.isAuthenticated);
    if (!auth.isAuthenticated) return;
    unawaited(refresh(reason: 'auth_scope'));
    _startTimer();
  }

  void setAppActive(bool active) {
    _appActive = active;
    if (!active) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (ref.read(authSessionControllerProvider).isAuthenticated) {
      unawaited(refresh(reason: 'app_resumed'));
      _startTimer();
    }
  }

  void setCallCritical(bool active) {
    if (_callCritical == active) return;
    _callCritical = active;
    if (!active && _deferredRefresh) {
      _deferredRefresh = false;
      unawaited(refresh(reason: 'call_terminal'));
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_appActive) return;
    _timer = Timer.periodic(
      _refreshInterval,
      (_) => unawaited(refresh(reason: 'periodic')),
    );
  }

  Future<void> refresh({String reason = 'manual'}) {
    if (_callCritical) {
      _deferredRefresh = true;
      developer.log('Counter refresh deferred reason=$reason',
          name: 'AgentCounters');
      return Future<void>.value();
    }
    final active = _refreshInFlight;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _performRefresh(reason).whenComplete(() {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    });
    _refreshInFlight = operation;
    return operation;
  }

  Future<void> _performRefresh(String reason) async {
    final auth = ref.read(authSessionControllerProvider);
    if (!auth.isAuthenticated) return;
    developer.log('Counter refresh started reason=$reason',
        name: 'AgentCounters');
    final generation = _generation;
    state = state.copyWith(
      loading: !state.hasLoaded,
      refreshing: state.hasLoaded,
      error: null,
    );
    try {
      final counters = await ref.read(agentCountersRepositoryProvider).load(
        onCached: (cached) {
          if (!ref.mounted || generation != _generation) return;
          state = AgentCountersState(
            counters: cached,
            hasLoaded: true,
            refreshing: true,
          );
        },
      );
      if (!ref.mounted || generation != _generation) return;
      state = AgentCountersState(counters: counters, hasLoaded: true);
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      // Cached counts stay visible; an unavailable network must not erase
      // badges or turn them into misleading zeroes.
      state = state.copyWith(loading: false, refreshing: false, error: error);
    }
  }
}
