import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/api_service.dart';
import '../../services/auth_session_controller.dart';
import '../../services/response_cache.dart';
import 'ticket_store.dart';

part 'ticket_api_repository.g.dart';

class TicketFilterOption {
  const TicketFilterOption({required this.value, required this.label});
  final String value;
  final String label;
}

Map<String, dynamic> _stringMap(Map value) =>
    value.map((key, item) => MapEntry(key.toString(), item));

class TicketFilterOptions {
  const TicketFilterOptions({
    this.statuses = const [],
    this.sources = const [],
    this.priorities = const [],
    this.periods = const [],
    this.categories = const [],
    this.departments = const [],
    this.assignments = const [],
  });
  final List<TicketFilterOption> statuses;
  final List<TicketFilterOption> sources;
  final List<TicketFilterOption> priorities;
  final List<TicketFilterOption> periods;
  final List<TicketFilterOption> categories;
  final List<TicketFilterOption> departments;
  final List<TicketFilterOption> assignments;

  factory TicketFilterOptions.fromJson(Map<String, dynamic> json) {
    List<TicketFilterOption> read(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) {
            final map = _stringMap(item);
            final value = map['value'];
            final label = map['label']?.toString().trim() ?? '';
            if (value == null || label.isEmpty) return null;
            return TicketFilterOption(value: value.toString(), label: label);
          })
          .whereType<TicketFilterOption>()
          .toList(growable: false);
    }

    return TicketFilterOptions(
      statuses: read('statuses'),
      sources: read('sources'),
      priorities: read('priorities'),
      periods: read('periods'),
      categories: read('categories'),
      departments: read('departments'),
      assignments: read('assignments'),
    );
  }
}

class TicketQuery {
  const TicketQuery({
    this.search = '',
    this.status,
    this.source,
    this.priority,
    this.categoryId,
    this.departmentId,
    this.assignment = 'me',
    this.period,
    this.fromDate,
    this.toDate,
    this.page = 1,
    this.perPage = 20,
  });
  final String search;
  final String? status;
  final String? source;
  final String? priority;
  final String? categoryId;
  final String? departmentId;
  final String? assignment;
  final String? period;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int page;
  final int perPage;

  Map<String, dynamic> toQueryParameters() => {
        if (assignment != null) 'assigned': assignment,
        if (status != null && status!.isNotEmpty) 'status': status,
        if (source != null && source!.isNotEmpty) 'source': source,
        if (priority != null && priority!.isNotEmpty) 'priority': priority,
        if (categoryId != null && categoryId!.isNotEmpty)
          'category_id': int.tryParse(categoryId!) ?? categoryId,
        if (departmentId != null && departmentId!.isNotEmpty)
          'department_id': int.tryParse(departmentId!) ?? departmentId,
        if (period != null && period!.isNotEmpty) 'period': period,
        if (fromDate != null) 'from_date': _date(fromDate!),
        if (toDate != null) 'to_date': _date(toDate!),
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'page': page,
        'per_page': perPage.clamp(1, 100),
      };

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class TicketPageResult {
  const TicketPageResult({
    required this.tickets,
    required this.page,
    required this.lastPage,
    required this.total,
  });
  final List<TicketRecord> tickets;
  final int page;
  final int lastPage;
  final int total;
}

class TicketDetailResult {
  const TicketDetailResult({required this.ticket, required this.activity});
  final TicketRecord ticket;
  final List<TicketActivity> activity;
}

class TicketReassignmentResult {
  const TicketReassignmentResult({this.agentName});
  final String? agentName;
}

abstract interface class TicketsRepository {
  Future<TicketFilterOptions> filters(
      {CancelToken? cancelToken,
      void Function(TicketFilterOptions value)? onCached,
      void Function()? onCacheMiss});
  Future<TicketPageResult> list(TicketQuery query,
      {CancelToken? cancelToken,
      void Function(TicketPageResult value)? onCached,
      void Function()? onCacheMiss});
  Future<TicketDetailResult> detail(String id,
      {CancelToken? cancelToken,
      void Function(TicketDetailResult value)? onCached,
      void Function()? onCacheMiss});
  Future<void> updateStatus(String id, String status,
      {String? reason, CancelToken? cancelToken});
  Future<TicketReassignmentResult> reassign(
    String id, {
    required int agentId,
    int? teamId,
  });
}

@Riverpod(keepAlive: true)
TicketsRepository ticketsRepository(Ref ref) => RemoteTicketsRepository(
      ref.watch(apiServiceProvider),
      cache: ref.watch(responseCacheProvider),
      readScope: () {
        final user = ref.read(authSessionControllerProvider).session?.user;
        return user == null ? null : ResponseCacheScope.fromUser(user);
      },
    );

class RemoteTicketsRepository implements TicketsRepository {
  RemoteTicketsRepository(this._api,
      {ResponseCache? cache, ResponseCacheScope? Function()? readScope})
      : _cache = cache,
        _readScope = readScope;
  final ApiService _api;
  final ResponseCache? _cache;
  final ResponseCacheScope? Function()? _readScope;

  Future<T?> _fetchCached<T>({
    required String module,
    required String key,
    required CancelToken? cancelToken,
    required Future<Object?> Function() fetch,
    required T Function(Object?) decode,
    void Function(T)? onCached,
    void Function()? onCacheMiss,
  }) async {
    final cache = _cache;
    final scope = _readScope?.call();
    if (cache == null || scope == null) return null;
    return (await CacheFirstJsonLoader(cache).load(
      scope: scope,
      module: module,
      key: key,
      expectedEpoch: cache.writeEpoch,
      fetch: fetch,
      decode: decode,
      onCached: onCached ?? (_) {},
      onFresh: (_) {},
      onCacheMiss: onCacheMiss,
    ))
        .value;
  }

  @override
  Future<TicketFilterOptions> filters({
    CancelToken? cancelToken,
    void Function(TicketFilterOptions value)? onCached,
    void Function()? onCacheMiss,
  }) async {
    final cached = await _fetchCached(
      module: 'tickets',
      key: 'filters',
      cancelToken: cancelToken,
      fetch: () => _api.get('/tickets/filters', cancelToken: cancelToken),
      decode: _decodeFilters,
      onCached: onCached,
      onCacheMiss: onCacheMiss,
    );
    if (cached != null) return cached;
    return _decodeFilters(
        await _api.get('/tickets/filters', cancelToken: cancelToken));
  }

  TicketFilterOptions _decodeFilters(Object? response) {
    final root = _map(response, 'ticket filters');
    final filters = root['filters'];
    if (filters is! Map) {
      throw const FormatException('Ticket filters are missing.');
    }
    return TicketFilterOptions.fromJson(_stringMap(filters));
  }

  @override
  Future<TicketPageResult> list(TicketQuery query,
      {CancelToken? cancelToken,
      void Function(TicketPageResult value)? onCached,
      void Function()? onCacheMiss}) async {
    final parameters = query.toQueryParameters();
    final cached = await _fetchCached(
      module: 'tickets',
      key: 'list?${stableCacheQueryKey(parameters)}',
      cancelToken: cancelToken,
      fetch: () => _api.get('/tickets',
          queryParameters: parameters, cancelToken: cancelToken),
      decode: (response) => _decodeList(response, query),
      onCached: onCached,
      onCacheMiss: onCacheMiss,
    );
    if (cached != null) return cached;
    return _decodeList(
      await _api.get('/tickets',
          queryParameters: parameters, cancelToken: cancelToken),
      query,
    );
  }

  TicketPageResult _decodeList(Object? response, TicketQuery query) {
    final root = _map(response, 'ticket list');
    final rows = root['data'];
    if (rows is! List) throw const FormatException('Ticket data is missing.');
    final meta = root['meta'] is Map ? _stringMap(root['meta']) : const {};
    final tickets = rows
        .map((row) => _ticket(_map(row, 'ticket summary')))
        .toList(growable: false);
    return TicketPageResult(
      tickets: tickets,
      page: _integer(meta['current_page'], query.page),
      lastPage: _integer(meta['last_page'], query.page),
      total: _integer(meta['total'], tickets.length),
    );
  }

  @override
  Future<TicketDetailResult> detail(String id,
      {CancelToken? cancelToken,
      void Function(TicketDetailResult value)? onCached,
      void Function()? onCacheMiss}) async {
    final encodedId = Uri.encodeComponent(id);
    final cache = _cache;
    final scope = _readScope?.call();
    if (cache != null && scope != null) {
      return (await CacheFirstJsonLoader(cache).load(
        scope: scope,
        module: 'tickets',
        key: 'detail:$id',
        expectedEpoch: cache.writeEpoch,
        fetch: () async => {
          'ticket':
              await _api.get('/tickets/$encodedId', cancelToken: cancelToken),
          'timeline': await _api.get('/tickets/$encodedId/timeline',
              cancelToken: cancelToken),
        },
        decode: (payload) => _decodeDetail(id, payload),
        onCached: onCached ?? (_) {},
        onFresh: (_) {},
        onCacheMiss: onCacheMiss,
      ))
          .value;
    }
    return _decodeDetail(id, {
      'ticket': await _api.get('/tickets/$encodedId', cancelToken: cancelToken),
      'timeline': await _api.get('/tickets/$encodedId/timeline',
          cancelToken: cancelToken),
    });
  }

  TicketDetailResult _decodeDetail(String id, Object? payload) {
    final root = _map(payload, 'ticket detail payload');
    final raw = _map(root['ticket'], 'ticket detail response');
    final ticketJson = raw['ticket'];
    if (ticketJson is! Map) {
      throw const FormatException('Ticket detail is missing.');
    }
    final ticket = _ticket(_stringMap(ticketJson));
    final timelineRoot = _map(root['timeline'], 'ticket timeline');
    final events = timelineRoot['timeline'];
    if (events is! List) {
      throw const FormatException('Ticket timeline is missing.');
    }
    return TicketDetailResult(
      ticket: ticket,
      activity: events
          .map((event) => _activity(_map(event, 'ticket timeline entry')))
          .toList(growable: false),
    );
  }

  @override
  Future<void> updateStatus(String id, String status,
      {String? reason, CancelToken? cancelToken}) async {
    await _api.post('/tickets/${Uri.encodeComponent(id)}/status', {
      'status': status,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  @override
  Future<TicketReassignmentResult> reassign(
    String id, {
    required int agentId,
    int? teamId,
  }) async {
    final response = await _api.post(
      '/tickets/${Uri.encodeComponent(id)}/reassign',
      {
        'agent_id': agentId,
        if (teamId != null) 'team_id': teamId,
      },
    );
    final root = _map(response, 'ticket reassignment response');
    if (root['success'] == false) {
      throw FormatException(
          _string(root['error']).ifEmpty('Ticket reassignment failed.'));
    }
    return TicketReassignmentResult(agentName: _nullable(root['agent_name']));
  }

  static TicketRecord _ticket(Map<String, dynamic> json) {
    final customer = json['customer'] is Map
        ? _stringMap(json['customer'])
        : const <String, dynamic>{};
    final agent = json['assigned_agent'] is Map
        ? _stringMap(json['assigned_agent'])
        : const <String, dynamic>{};
    final department = json['department'] is Map
        ? _stringMap(json['department'])
        : const <String, dynamic>{};
    final category = json['ticket_category'] is Map
        ? _stringMap(json['ticket_category'])
        : const <String, dynamic>{};
    final id = _required(json['id'], 'ticket id');
    final sourceRaw = _string(json['source']).ifEmpty('manual');
    final statusRaw = _string(json['status']).ifEmpty('open');
    final priorityRaw = _string(json['priority']).ifEmpty('medium');
    final created = _dateTime(json['created_at']) ?? DateTime.now().toUtc();
    final updated = _dateTime(json['updated_at']) ?? created;
    final customerName = _string(customer['name']).ifEmpty('Unknown customer');
    final customerPhone = _string(customer['phone_number']);
    final customerEmail = _string(customer['email']);
    final contact = customerPhone.isNotEmpty ? customerPhone : customerEmail;
    final departmentName = _string(department['name']);
    final categoryName =
        _string(category['name']).ifEmpty(_string(json['category']));
    final slaDeadline = _dateTime(json['sla_deadline']);
    final resolutionRaw = json['resolution'] is Map
        ? _stringMap(json['resolution'])
        : const <String, dynamic>{};
    final capabilitiesRaw = json['capabilities'] is Map
        ? _stringMap(json['capabilities'] as Map)
        : const <String, dynamic>{};
    final rawCanEdit = capabilitiesRaw['can_edit'] ??
        capabilitiesRaw['canEdit'] ??
        json['can_edit'] ??
        json['canEdit'];
    final canEdit = rawCanEdit is bool ? rawCanEdit : true;
    final resolutionNote = _string(resolutionRaw['note'])
        .ifEmpty(_string(json['resolution_note']));
    final resolvedAt = _dateTime(resolutionRaw['resolved_at']) ??
        _dateTime(json['resolved_at']);
    return TicketRecord(
      id: id,
      displayId: _string(json['display_number'])
          .ifEmpty(_string(json['prefixed_id']).ifEmpty('#$id')),
      subject: _string(json['subject']).ifEmpty('Untitled ticket'),
      customerLabel: customerName,
      sourceActor: customerName,
      customerId: customer['id']?.toString(),
      source: _source(sourceRaw),
      sourceRaw: sourceRaw,
      status: _status(statusRaw),
      statusRaw: statusRaw,
      priority: _priority(priorityRaw),
      priorityRaw: priorityRaw,
      department: departmentName,
      departmentId: (department['id'] ?? json['department_id'])?.toString(),
      category: categoryName.isEmpty ? null : categoryName,
      categoryId: (category['id'] ?? json['category_id'])?.toString(),
      sla: slaDeadline == null ? null : 'Due ${_dateTimeLabel(slaDeadline)}',
      slaDeadline: slaDeadline,
      isOverdue: json['is_overdue'] == true,
      contactIdentifier: contact.isEmpty ? null : contact,
      description: TicketDescription(plainText: _string(json['description'])),
      assignedAgent: _string(agent['name']).ifEmpty('Unassigned'),
      assignedAgentId: agent['id']?.toString(),
      createdAt: created,
      updatedAt: updated,
      sourceContext: _context(sourceRaw, json, id, customerName, contact),
      resolution: statusRaw == 'resolved' || statusRaw == 'closed'
          ? TicketResolution(
              note: resolutionNote,
              resolvedBy:
                  _string(resolutionRaw['resolved_by_name']).ifEmpty('Agent'),
              resolvedAt: resolvedAt ?? updated,
              template: _nullable(resolutionRaw['template']),
            )
          : null,
      activities: const [],
      revision: _integer(json['revision'], 1),
      capabilities: TicketCapabilities(
        canEdit: canEdit,
        canReassign: false,
        canChangeStatus: true,
        canResolve: true,
        canDelete: false,
      ),
    );
  }

  static TicketActivity _activity(Map<String, dynamic> json) {
    final type = _string(json['event_type']);
    final created = _dateTime(json['created_at']) ?? DateTime.now().toUtc();
    final isCustomer = json['is_from_customer'] == true;
    return TicketActivity(
      id: _required(json['id'], 'timeline event id'),
      type: switch (type) {
        'customer_message' => TicketActivityType.messageReceived,
        'agent_reply' => TicketActivityType.messageReceived,
        'status_update' => TicketActivityType.statusChanged,
        'created' => TicketActivityType.created,
        _ => TicketActivityType.noteAdded,
      },
      title: switch (type) {
        'customer_message' => 'Customer message',
        'agent_reply' => 'Agent reply',
        'status_update' => 'Status update',
        'created' => 'Ticket created',
        '' => 'Activity',
        _ => type.replaceAll('_', ' '),
      },
      description: _nullable(json['description']),
      timestamp: created,
      actor: isCustomer ? 'Customer' : _nullable(json['actor_name']),
    );
  }

  static TicketStatus _status(String value) => switch (value) {
        'in_progress' => TicketStatus.inProgress,
        'pending' => TicketStatus.pending,
        'resolved' => TicketStatus.resolved,
        'closed' || 'closed_all' => TicketStatus.closed,
        'overdue' => TicketStatus.overdue,
        'escalated' => TicketStatus.escalated,
        _ => TicketStatus.open,
      };

  static TicketPriority _priority(String value) => switch (value) {
        'low' => TicketPriority.low,
        'high' => TicketPriority.high,
        'urgent' => TicketPriority.urgent,
        _ => TicketPriority.medium,
      };

  static TicketSource _source(String value) => switch (value) {
        'phone' => TicketSource.call,
        'whatsapp' => TicketSource.whatsapp,
        'email' => TicketSource.email,
        'widget' => TicketSource.widget,
        _ => TicketSource.manual,
      };

  static TicketSourceContext _context(
      String source,
      Map<String, dynamic> ticket,
      String ticketId,
      String customerName,
      String contact) {
    if (source == 'phone') return const TicketPhoneSourceContext();
    final rawContext = ticket['source_context'];
    final context =
        rawContext is Map ? _stringMap(rawContext) : const <String, dynamic>{};
    final channel = _string(context['channel']).ifEmpty(source).toLowerCase();
    final contextTicketId = _string(context['ticket_id']).ifEmpty(ticketId);
    final sourceTimelineId = _nullable(context['source_timeline_id']) ??
        _nullable(ticket['source_timeline_id']);
    final latestTimelineId = _nullable(context['latest_timeline_id']) ??
        _nullable(ticket['latest_timeline_id']);
    if (channel == 'email' || source == 'email') {
      return TicketEmailSourceContext(
        threadId: contextTicketId,
        preview: _string(ticket['subject']),
        from: _string(context['customer_email'])
            .ifEmpty(contact)
            .ifEmpty(customerName),
        sourceTimelineId: sourceTimelineId,
        latestTimelineId: latestTimelineId,
      );
    }
    if (channel == 'whatsapp' ||
        channel == 'widget' ||
        source == 'whatsapp' ||
        source == 'widget') {
      return TicketConversationSourceContext(
        conversationId: contextTicketId,
        preview: _string(ticket['subject']),
        channel:
            channel == 'widget' ? TicketSource.widget : TicketSource.whatsapp,
        sourceTimelineId: sourceTimelineId,
        latestTimelineId: latestTimelineId,
      );
    }
    return const TicketManualSourceContext();
  }

  static Map<String, dynamic> _map(dynamic value, String label) {
    if (value is Map) return _stringMap(value);
    throw FormatException('Invalid $label.');
  }

  static String _required(dynamic value, String name) {
    final result = _string(value);
    if (result.isEmpty) throw FormatException('Missing $name.');
    return result;
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';
  static String? _nullable(dynamic value) {
    final result = _string(value);
    return result.isEmpty ? null : result;
  }

  static int _integer(dynamic value, int fallback) =>
      value is int ? value : int.tryParse(_string(value)) ?? fallback;
  static DateTime? _dateTime(dynamic value) =>
      value == null ? null : DateTime.tryParse(_string(value))?.toUtc();
  static String _dateTimeLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

extension _NonEmptyString on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
