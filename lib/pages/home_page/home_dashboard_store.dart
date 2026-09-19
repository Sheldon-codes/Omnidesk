import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_service.dart';

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

  @override
  HomeDashboardState build() {
    final state = const HomeDashboardState(loading: true);
    Future.microtask(load);
    ref.onDispose(() {
      _loadFuture = null;
    });
    return state;
  }

  Future<void> load({bool force = false}) {
    if (!force && _loadFuture != null) return _loadFuture!;
    final task = _load();
    _loadFuture = task;
    task.whenComplete(() {
      if (identical(_loadFuture, task)) {
        _loadFuture = null;
      }
    });
    return task;
  }

  Future<void> _load() async {
    final hadData = state.hasData;
    state =
        state.copyWith(loading: !hadData, refreshing: hadData, failure: null);
    try {
      final repository = ref.read(homeDashboardRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repository.loadStats(),
        repository.loadMyTickets(),
      ]);
      state = HomeDashboardState(
        stats: results[0] as DashboardStats,
        tickets: results[1] as List<DashboardTicket>,
        lastUpdated: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(loading: false, refreshing: false, failure: error);
    }
  }

  Future<bool> setAvailability(bool isAvailable) async {
    try {
      final result = await ref
          .read(homeDashboardRepositoryProvider)
          .updateAvailability(isAvailable);
      final current = state.stats;
      if (current != null) {
        state = state.copyWith(
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
