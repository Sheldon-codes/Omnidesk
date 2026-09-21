import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../../services/auth_session_controller.dart';

class DashboardGreeting {
  const DashboardGreeting({
    required this.agentName,
    required this.totalTickets,
    required this.urgentCount,
    required this.overdueCount,
    required this.isAvailable,
  });

  final String agentName;
  final int totalTickets;
  final int urgentCount;
  final int overdueCount;
  final bool isAvailable;
}

class ChannelStats {
  const ChannelStats(
      {this.open = 0,
      this.inProgress = 0,
      this.resolved = 0,
      this.overdue = 0});
  final int open;
  final int inProgress;
  final int resolved;
  final int overdue;
  int get total => open + inProgress + resolved + overdue;
}

class DashboardChannels {
  const DashboardChannels(
      {required this.calls,
      required this.whatsapp,
      required this.email,
      required this.widget});
  final ChannelStats calls;
  final ChannelStats whatsapp;
  final ChannelStats email;
  final ChannelStats widget;
}

class RecentCall {
  const RecentCall(
      {required this.label,
      required this.timestamp,
      this.ticketId,
      this.duration = '0:00',
      this.missed = false});
  final String label;
  final DateTime? timestamp;
  final String? ticketId;
  final String duration;
  final bool missed;
}

class RecentCaller {
  const RecentCaller(
      {required this.label,
      required this.phone,
      required this.timestamp,
      this.ticketId,
      this.customerId});
  final String label;
  final String phone;
  final DateTime? timestamp;
  final String? ticketId;
  final String? customerId;
}

class DashboardStats {
  const DashboardStats({
    required this.greeting,
    required this.channels,
    required this.recentCalls,
    required this.recentCallers,
    required this.myOpen,
    required this.myPending,
    required this.myResolvedToday,
    required this.allUnassigned,
    required this.overdue,
    required this.unreadMessages,
  });
  final DashboardGreeting greeting;
  final DashboardChannels channels;
  final List<RecentCall> recentCalls;
  final List<RecentCaller> recentCallers;
  final int myOpen;
  final int myPending;
  final int myResolvedToday;
  final int allUnassigned;
  final int overdue;
  final int unreadMessages;
}

class DashboardTicket {
  const DashboardTicket({
    required this.id,
    required this.displayNumber,
    required this.subject,
    required this.status,
    required this.priority,
    required this.source,
    required this.isOverdue,
    required this.customerName,
    required this.customerPhone,
    required this.createdAt,
    this.customerId,
  });
  final String id;
  final String displayNumber;
  final String subject;
  final String status;
  final String priority;
  final String source;
  final bool isOverdue;
  final String customerName;
  final String customerPhone;
  final DateTime? createdAt;
  final String? customerId;
}

class AvailabilityResult {
  const AvailabilityResult(this.isAvailable);
  final bool isAvailable;
}

abstract class HomeDashboardRepository {
  Future<DashboardStats> loadStats();
  Future<AvailabilityResult> updateAvailability(bool isAvailable);
  Future<List<DashboardTicket>> loadMyTickets({int perPage = 10});
  Future<void> heartbeat();
}

class ApiHomeDashboardRepository implements HomeDashboardRepository {
  ApiHomeDashboardRepository(this._api);
  final ApiService _api;

  @override
  Future<DashboardStats> loadStats() async {
    final response = await _api.get('/agent/stats');
    return _parseStats(_map(response));
  }

  @override
  Future<AvailabilityResult> updateAvailability(bool isAvailable) async {
    final response =
        await _api.post('/agent/availability', {'is_available': isAvailable});
    final map = _map(response);
    final value = map['is_available'];
    if (value is! bool) {
      throw const FormatException('Invalid availability response.');
    }
    return AvailabilityResult(value);
  }

  @override
  Future<List<DashboardTicket>> loadMyTickets({int perPage = 10}) async {
    final response = await _api.get('/tickets',
        queryParameters: {'assigned': 'me', 'per_page': perPage});
    final map = _map(response);
    final data = map['data'];
    if (data is! List) throw const FormatException('Invalid ticket response.');
    return data
        .whereType<Map>()
        .map((item) => _parseTicket(_map(item)))
        .toList(growable: false);
  }

  @override
  Future<void> heartbeat() async {
    // Heartbeat reporting is disabled product-wide: the mobile app must never
    // call POST /agent/heartbeat. Kept as a no-op so lifecycle callers and
    // repository fakes don't churn if reporting is ever reintroduced.
  }

  DashboardStats _parseStats(Map<String, dynamic> json) {
    final greeting = _map(json['greeting']);
    final channels = _map(json['channels']);
    final recent = _map(json['recent_calls']);
    final callers = json['recent_callers'];
    return DashboardStats(
      greeting: DashboardGreeting(
        agentName: _string(greeting['agent_name']),
        totalTickets: _int(greeting['total_tickets']),
        urgentCount: _int(greeting['urgent_count']),
        overdueCount: _int(greeting['overdue_count']),
        isAvailable: greeting['is_available'] == true,
      ),
      channels: DashboardChannels(
        calls: _parseChannel(_map(channels['calls'])),
        whatsapp: _parseChannel(_map(channels['whatsapp'])),
        email: _parseChannel(_map(channels['email'])),
        widget: _parseChannel(_map(channels['widget'])),
      ),
      recentCalls:
          (recent['list'] is List ? recent['list'] as List : const <dynamic>[])
              .whereType<Map>()
              .map((item) => _parseCall(_map(item)))
              .toList(growable: false),
      recentCallers: (callers is List ? callers : const <dynamic>[])
          .whereType<Map>()
          .map((item) => _parseCaller(_map(item)))
          .toList(growable: false),
      myOpen: _int(json['my_open']),
      myPending: _int(json['my_pending']),
      myResolvedToday: _int(json['my_resolved_today']),
      allUnassigned: _int(json['all_unassigned']),
      overdue: _int(json['overdue']),
      unreadMessages: _int(json['unread_messages']),
    );
  }

  ChannelStats _parseChannel(Map<String, dynamic> json) => ChannelStats(
        open: _int(json['open']),
        inProgress: _int(json['in_progress']),
        resolved: _int(json['resolved']),
        overdue: _int(json['overdue']),
      );

  RecentCall _parseCall(Map<String, dynamic> json) => RecentCall(
        label: _string(json['name'] ?? json['phone_number'] ?? json['caller']),
        timestamp: _date(json['timestamp'] ?? json['created_at']),
        ticketId: json['ticket_id']?.toString(),
        duration: _string(json['duration'] ?? '0:00'),
        missed: json['missed'] == true ||
            json['status']?.toString().toLowerCase() == 'missed',
      );

  RecentCaller _parseCaller(Map<String, dynamic> json) => RecentCaller(
        label: _string(
            json['name'] ?? json['display_name'] ?? json['phone_number']),
        phone: _string(json['phone_number']),
        timestamp: _date(json['timestamp'] ?? json['created_at']),
        ticketId: json['ticket_id']?.toString(),
        customerId: json['customer_id']?.toString(),
      );

  DashboardTicket _parseTicket(Map<String, dynamic> json) {
    final customer = _map(json['customer']);
    return DashboardTicket(
      id: _string(json['id']),
      displayNumber:
          _string(json['display_number'], fallback: '#${_string(json['id'])}'),
      subject: _string(json['subject']),
      status: _string(json['status']),
      priority: _string(json['priority']),
      source: _string(json['source']),
      isOverdue: json['is_overdue'] == true,
      customerName: _string(customer['name']),
      customerPhone: _string(customer['phone_number']),
      customerId: customer['id']?.toString(),
      createdAt: _date(json['created_at']),
    );
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  static String _string(dynamic value, {String fallback = ''}) =>
      value?.toString() ?? fallback;
  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static DateTime? _date(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '');
}

class HomeDashboardState {
  const HomeDashboardState(
      {this.stats,
      this.tickets = const [],
      this.loading = false,
      this.refreshing = false,
      this.failure,
      this.lastUpdated});
  final DashboardStats? stats;
  final List<DashboardTicket> tickets;
  final bool loading;
  final bool refreshing;
  final Object? failure;
  final DateTime? lastUpdated;
  bool get hasData => stats != null;
  HomeDashboardState copyWith(
          {DashboardStats? stats,
          List<DashboardTicket>? tickets,
          bool? loading,
          bool? refreshing,
          Object? failure = _keep,
          DateTime? lastUpdated}) =>
      HomeDashboardState(
        stats: stats ?? this.stats,
        tickets: tickets ?? this.tickets,
        loading: loading ?? this.loading,
        refreshing: refreshing ?? this.refreshing,
        failure: identical(failure, _keep) ? this.failure : failure,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
  static const _keep = Object();
}

/// A non-sensitive, per-agent/workspace dashboard snapshot. The access token
/// remains exclusively in secure storage; this cache contains only content the
/// Home screen already renders. Scoping is essential because a device can be
/// used by more than one agent or workspace.
class HomeDashboardCache {
  static const _prefix = 'omnidesk_home_dashboard_v1';

  Future<HomeDashboardState?> read(String scope) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString('$_prefix.$scope');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _stateFromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String scope, HomeDashboardState state) async {
    if (!state.hasData) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        '$_prefix.$scope',
        jsonEncode(_stateToJson(state)),
      );
    } catch (_) {
      // The network response remains valid when cache persistence fails.
    }
  }

  Map<String, dynamic> _stateToJson(HomeDashboardState state) => {
        'stats': _statsToJson(state.stats!),
        'tickets': state.tickets.map(_ticketToJson).toList(growable: false),
        'lastUpdated': state.lastUpdated?.toIso8601String(),
      };

  HomeDashboardState? _stateFromJson(Map<String, dynamic> json) {
    try {
      final stats = json['stats'];
      final tickets = json['tickets'];
      if (stats is! Map || tickets is! List) return null;
      return HomeDashboardState(
        stats: _statsFromJson(_map(stats)),
        tickets: tickets
            .whereType<Map>()
            .map((value) => _ticketFromJson(_map(value)))
            .toList(growable: false),
        lastUpdated: DateTime.tryParse(json['lastUpdated']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _statsToJson(DashboardStats stats) => {
        'greeting': {
          'agentName': stats.greeting.agentName,
          'totalTickets': stats.greeting.totalTickets,
          'urgentCount': stats.greeting.urgentCount,
          'overdueCount': stats.greeting.overdueCount,
          'isAvailable': stats.greeting.isAvailable,
        },
        'channels': {
          'calls': _channelToJson(stats.channels.calls),
          'whatsapp': _channelToJson(stats.channels.whatsapp),
          'email': _channelToJson(stats.channels.email),
          'widget': _channelToJson(stats.channels.widget),
        },
        'recentCalls': stats.recentCalls
            .map((value) => {
                  'label': value.label,
                  'timestamp': value.timestamp?.toIso8601String(),
                  'ticketId': value.ticketId,
                  'duration': value.duration,
                  'missed': value.missed,
                })
            .toList(growable: false),
        'recentCallers': stats.recentCallers
            .map((value) => {
                  'label': value.label,
                  'phone': value.phone,
                  'timestamp': value.timestamp?.toIso8601String(),
                  'ticketId': value.ticketId,
                  'customerId': value.customerId,
                })
            .toList(growable: false),
        'myOpen': stats.myOpen,
        'myPending': stats.myPending,
        'myResolvedToday': stats.myResolvedToday,
        'allUnassigned': stats.allUnassigned,
        'overdue': stats.overdue,
        'unreadMessages': stats.unreadMessages,
      };

  static Map<String, dynamic> _channelToJson(ChannelStats stats) => {
        'open': stats.open,
        'inProgress': stats.inProgress,
        'resolved': stats.resolved,
        'overdue': stats.overdue,
      };

  static Map<String, dynamic> _ticketToJson(DashboardTicket ticket) => {
        'id': ticket.id,
        'displayNumber': ticket.displayNumber,
        'subject': ticket.subject,
        'status': ticket.status,
        'priority': ticket.priority,
        'source': ticket.source,
        'isOverdue': ticket.isOverdue,
        'customerName': ticket.customerName,
        'customerPhone': ticket.customerPhone,
        'createdAt': ticket.createdAt?.toIso8601String(),
        'customerId': ticket.customerId,
      };

  static DashboardStats _statsFromJson(Map<String, dynamic> json) {
    final greeting = _map(json['greeting']);
    final channels = _map(json['channels']);
    return DashboardStats(
      greeting: DashboardGreeting(
        agentName: _string(greeting['agentName']),
        totalTickets: _int(greeting['totalTickets']),
        urgentCount: _int(greeting['urgentCount']),
        overdueCount: _int(greeting['overdueCount']),
        isAvailable: greeting['isAvailable'] == true,
      ),
      channels: DashboardChannels(
        calls: _channelFromJson(_map(channels['calls'])),
        whatsapp: _channelFromJson(_map(channels['whatsapp'])),
        email: _channelFromJson(_map(channels['email'])),
        widget: _channelFromJson(_map(channels['widget'])),
      ),
      recentCalls: (_list(json['recentCalls'])).whereType<Map>().map((value) {
        final item = _map(value);
        return RecentCall(
          label: _string(item['label']),
          timestamp: DateTime.tryParse(item['timestamp']?.toString() ?? ''),
          ticketId: _nullableString(item['ticketId']),
          duration: _string(item['duration'], fallback: '0:00'),
          missed: item['missed'] == true,
        );
      }).toList(growable: false),
      recentCallers:
          (_list(json['recentCallers'])).whereType<Map>().map((value) {
        final item = _map(value);
        return RecentCaller(
          label: _string(item['label']),
          phone: _string(item['phone']),
          timestamp: DateTime.tryParse(item['timestamp']?.toString() ?? ''),
          ticketId: _nullableString(item['ticketId']),
          customerId: _nullableString(item['customerId']),
        );
      }).toList(growable: false),
      myOpen: _int(json['myOpen']),
      myPending: _int(json['myPending']),
      myResolvedToday: _int(json['myResolvedToday']),
      allUnassigned: _int(json['allUnassigned']),
      overdue: _int(json['overdue']),
      unreadMessages: _int(json['unreadMessages']),
    );
  }

  static ChannelStats _channelFromJson(Map<String, dynamic> json) =>
      ChannelStats(
        open: _int(json['open']),
        inProgress: _int(json['inProgress']),
        resolved: _int(json['resolved']),
        overdue: _int(json['overdue']),
      );

  static DashboardTicket _ticketFromJson(Map<String, dynamic> json) =>
      DashboardTicket(
        id: _string(json['id']),
        displayNumber: _string(json['displayNumber']),
        subject: _string(json['subject']),
        status: _string(json['status']),
        priority: _string(json['priority']),
        source: _string(json['source']),
        isOverdue: json['isOverdue'] == true,
        customerName: _string(json['customerName']),
        customerPhone: _string(json['customerPhone']),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        customerId: _nullableString(json['customerId']),
      );

  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, nested) => MapEntry('$key', nested))
      : <String, dynamic>{};
  static List<dynamic> _list(dynamic value) => value is List ? value : const [];
  static String _string(dynamic value, {String fallback = ''}) =>
      value?.toString() ?? fallback;
  static String? _nullableString(dynamic value) {
    final string = value?.toString();
    return string == null || string.isEmpty ? null : string;
  }

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

final homeDashboardRepositoryProvider =
    Provider<HomeDashboardRepository>((ref) {
  final api = ref.read(apiServiceProvider);
  return api.baseUrl.isEmpty
      ? const LocalDemoHomeDashboardRepository()
      : ApiHomeDashboardRepository(api);
});

/// Keeps test/dev shells deterministic when no `.env` API root is loaded.
class LocalDemoHomeDashboardRepository implements HomeDashboardRepository {
  const LocalDemoHomeDashboardRepository();

  @override
  Future<DashboardStats> loadStats() async => const DashboardStats(
        greeting: DashboardGreeting(
          agentName: 'Omnidesk Agent',
          totalTickets: 0,
          urgentCount: 0,
          overdueCount: 0,
          isAvailable: true,
        ),
        channels: DashboardChannels(
          calls: ChannelStats(),
          whatsapp: ChannelStats(),
          email: ChannelStats(),
          widget: ChannelStats(),
        ),
        recentCalls: [],
        recentCallers: [],
        myOpen: 0,
        myPending: 0,
        myResolvedToday: 0,
        allUnassigned: 0,
        overdue: 0,
        unreadMessages: 0,
      );

  @override
  Future<AvailabilityResult> updateAvailability(bool isAvailable) async =>
      AvailabilityResult(isAvailable);

  @override
  Future<List<DashboardTicket>> loadMyTickets({int perPage = 10}) async =>
      const [];

  @override
  Future<void> heartbeat() async {}
}

final homeDashboardProvider =
    NotifierProvider<HomeDashboardController, HomeDashboardState>(
        HomeDashboardController.new);

class HomeDashboardController extends Notifier<HomeDashboardState> {
  Future<void>? _loadFuture;
  final _cache = HomeDashboardCache();
  String? _activeScope;
  int _generation = 0;

  @override
  HomeDashboardState build() {
    ref.listen<AuthState>(authSessionControllerProvider, (_, next) {
      // A notifier may not mutate its state synchronously while its own
      // `build` is executing. Scheduling also coalesces the bootstrap's
      // provisional-session and verified-session updates.
      Future.microtask(() => _handleAuthChanged(next));
    }, fireImmediately: true);
    ref.onDispose(() {
      _loadFuture = null;
      _generation++;
    });
    return const HomeDashboardState();
  }

  Future<void> load({bool force = false}) {
    if (_activeScope == null) return Future.value();
    if (!force && _loadFuture != null) return _loadFuture!;
    final task = _refresh(_activeScope!, _generation);
    _loadFuture = task;
    task.whenComplete(() {
      if (identical(_loadFuture, task)) {
        _loadFuture = null;
      }
    });
    return task;
  }

  void _handleAuthChanged(AuthState auth) {
    if (!auth.isAuthenticated) {
      _activeScope = null;
      _generation++;
      _loadFuture = null;
      if (state.hasData || state.loading || state.failure != null) {
        state = const HomeDashboardState();
      }
      return;
    }
    final user = auth.session!.user;
    final workspaceId = user.activeWorkspace?.id ?? 'no-workspace';
    final scope = '${user.id}.$workspaceId';
    if (scope == _activeScope) return;
    _activeScope = scope;
    final generation = ++_generation;
    _loadFuture = _hydrateThenRefresh(scope, generation);
  }

  Future<void> _hydrateThenRefresh(String scope, int generation) async {
    state = const HomeDashboardState(loading: true);
    final cached = await _cache.read(scope);
    if (generation != _generation || scope != _activeScope) return;
    if (cached != null && cached.hasData) {
      state = cached.copyWith(refreshing: true, failure: null);
      developer.log(
        'Restored cached dashboard for the active workspace; refreshing.',
        name: 'HomeDashboard',
      );
    }
    await _refresh(scope, generation);
  }

  Future<void> _refresh(String scope, int generation) async {
    if (generation != _generation || scope != _activeScope) return;
    final hadData = state.hasData;
    state =
        state.copyWith(loading: !hadData, refreshing: hadData, failure: null);
    try {
      final repository = ref.read(homeDashboardRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repository.loadStats(),
        repository.loadMyTickets(),
      ]);
      final next = HomeDashboardState(
        stats: results[0] as DashboardStats,
        tickets: results[1] as List<DashboardTicket>,
        lastUpdated: DateTime.now(),
      );
      if (generation != _generation || scope != _activeScope) return;
      state = next;
      unawaited(_cache.write(scope, next));
      developer.log(
        'Dashboard refresh completed and cache was scheduled for update.',
        name: 'HomeDashboard',
      );
    } catch (error) {
      if (generation != _generation || scope != _activeScope) return;
      state = state.copyWith(loading: false, refreshing: false, failure: error);
      developer.log(
        'Dashboard refresh failed: ${error.runtimeType}.',
        name: 'HomeDashboard',
      );
    }
  }

  Future<bool> setAvailability(bool isAvailable) async {
    try {
      final result = await ref
          .read(homeDashboardRepositoryProvider)
          .updateAvailability(isAvailable);
      final current = state.stats;
      if (current != null) {
        final next = state.copyWith(
            stats: DashboardStats(
          greeting: DashboardGreeting(
            agentName: current.greeting.agentName,
            totalTickets: current.greeting.totalTickets,
            urgentCount: current.greeting.urgentCount,
            overdueCount: current.greeting.overdueCount,
            isAvailable: result.isAvailable,
          ),
          channels: current.channels,
          recentCalls: current.recentCalls,
          recentCallers: current.recentCallers,
          myOpen: current.myOpen,
          myPending: current.myPending,
          myResolvedToday: current.myResolvedToday,
          allUnassigned: current.allUnassigned,
          overdue: current.overdue,
          unreadMessages: current.unreadMessages,
        ));
        state = next;
        final scope = _activeScope;
        if (scope != null) unawaited(_cache.write(scope, next));
      }
      return true;
    } catch (error) {
      state = state.copyWith(failure: error);
      return false;
    }
  }

  /// Heartbeat reporting is disabled product-wide (see
  /// [HomeDashboardRepository.heartbeat]). Kept so app-lifecycle callers
  /// don't churn; intentionally does nothing.
  void startHeartbeat() {}

  /// See [startHeartbeat].
  void stopHeartbeat() {}
}
