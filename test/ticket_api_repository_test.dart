import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/tickets_page/ticket_api_repository.dart';
import 'package:omnidesk_agent/pages/tickets_page/ticket_store.dart';
import 'package:omnidesk_agent/services/api_service.dart';

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.responses);
  final List<String> responses;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final body = responses.removeAt(0);
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('maps dynamic filters while preserving unknown workspace values', () {
    final filters = TicketFilterOptions.fromJson({
      'statuses': [
        {'value': 'awaiting_vendor', 'label': 'Awaiting vendor'}
      ],
      'sources': [],
      'departments': [
        {'value': 72, 'label': 'Escalations'}
      ],
      'categories': [],
    });

    expect(filters.statuses.single.value, 'awaiting_vendor');
    expect(filters.departments.single.value, '72');
    expect(filters.sources, isEmpty);
    expect(filters.categories, isEmpty);
  });

  test('builds documented list query with optional custom date filters', () {
    final query = TicketQuery(
      assignment: 'unassigned',
      status: 'open_all',
      source: 'phone',
      priority: 'urgent',
      categoryId: '3',
      departmentId: '7',
      period: 'custom',
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 22),
      search: '  billing  ',
      page: 2,
      perPage: 500,
    );

    expect(query.toQueryParameters(), {
      'assigned': 'unassigned',
      'status': 'open_all',
      'source': 'phone',
      'priority': 'urgent',
      'category_id': 3,
      'department_id': 7,
      'period': 'custom',
      'from_date': '2026-09-01',
      'to_date': '2026-09-22',
      'search': 'billing',
      'page': 2,
      'per_page': 100,
    });
  });

  test('loads tickets with workspace auth headers and normalizes API fields',
      () async {
    final adapter = _QueueAdapter([
      '''{"data":[{"id":14,"display_number":"#TKT-14","subject":"Account change","status":"pending","priority":"urgent","source":"whatsapp","source_timeline_id":501,"latest_timeline_id":508,"source_context":{"channel":"whatsapp","ticket_id":14,"source_timeline_id":501,"latest_timeline_id":508,"deep_link_path":"/chats/14?timelineId=501"},"category":"Account","is_overdue":true,"sla_deadline":"2026-08-31T14:30:00Z","customer":{"id":88,"name":"David Mwangi","phone_number":"+254768270973","email":"david@example.com"},"assigned_agent":{"id":5,"name":"Alice Agent"},"created_at":"2026-08-31T07:38:00Z","updated_at":"2026-08-31T08:00:00Z"}],"meta":{"current_page":1,"last_page":3,"total":41}}'''
    ]);
    final repository = RemoteTicketsRepository(_api(adapter));
    final result = await repository.list(const TicketQuery(status: 'pending'));

    final ticket = result.tickets.single;
    expect(ticket.id, '14');
    expect(ticket.displayId, '#TKT-14');
    expect(ticket.statusRaw, 'pending');
    expect(ticket.priorityRaw, 'urgent');
    expect(ticket.customer, 'David Mwangi');
    expect(ticket.contactIdentifier, '+254768270973');
    expect(ticket.assignedAgentId, '5');
    expect(ticket.isOverdue, isTrue);
    expect(ticket.capabilities.canEdit, isTrue);
    expect(ticket.sourceContext, isA<TicketConversationSourceContext>());
    final source = ticket.sourceContext as TicketConversationSourceContext;
    expect(source.conversationId, '14');
    expect(source.sourceTimelineId, '501');
    expect(source.latestTimelineId, '508');
    expect(result.lastPage, 3);
    expect(adapter.requests.single.path, '/tickets');
    expect(adapter.requests.single.queryParameters['status'], 'pending');
    expect(adapter.requests.single.headers['X-Workspace-Id'], '9');
    expect(adapter.requests.single.headers['Authorization'],
        'Bearer session-token');
  });

  test('loads ticket details and timeline using their documented endpoints',
      () async {
    final adapter = _QueueAdapter([
      '''{"ticket":{"id":14,"subject":"Billing","description":"Body","status":"open","priority":"medium","source":"email","source_context":{"channel":"email","ticket_id":14,"source_timeline_id":501,"latest_timeline_id":508,"customer_email":"david@example.com"},"capabilities":{"can_edit":false},"customer":{"id":88,"name":"David Mwangi","email":"david@example.com"},"department":{"id":1,"name":"Support"},"ticket_category":{"id":2,"name":"General Inquiries"},"assigned_agent":{"id":5,"name":"Alice Agent"},"created_at":"2026-08-31T07:38:00Z"}}''',
      '''{"ticket_id":14,"timeline":[{"id":501,"event_type":"customer_message","description":"Please help","is_from_customer":true,"is_read_by_agent":true,"created_at":"2026-08-31T07:38:00Z","formatted_time":"07:38"}]}''',
    ]);
    final detail = await RemoteTicketsRepository(_api(adapter)).detail('14');

    expect(detail.ticket.description.plainText, 'Body');
    expect(detail.ticket.department, 'Support');
    expect(detail.ticket.categoryId, '2');
    expect(detail.ticket.capabilities.canEdit, isFalse);
    expect(detail.ticket.sourceContext, isA<TicketEmailSourceContext>());
    final source = detail.ticket.sourceContext as TicketEmailSourceContext;
    expect(source.threadId, '14');
    expect(source.sourceTimelineId, '501');
    expect(detail.activity.single.id, '501');
    expect(detail.activity.single.title, 'Customer message');
    expect(adapter.requests.map((request) => request.path), [
      '/tickets/14',
      '/tickets/14/timeline',
    ]);
  });

  test('status mutation sends only documented values and optional reason',
      () async {
    final adapter = _QueueAdapter(['{"success":true}']);
    await RemoteTicketsRepository(_api(adapter))
        .updateStatus('14', 'resolved', reason: 'Issue fixed');
    expect(adapter.requests.single.path, '/tickets/14/status');
    expect(adapter.requests.single.data,
        {'status': 'resolved', 'reason': 'Issue fixed'});
  });

  test('reassigns ticket with numeric agent and optional team IDs', () async {
    final adapter = _QueueAdapter(['{"success":true,"agent_name":"Jane Doe"}']);
    final result = await RemoteTicketsRepository(_api(adapter)).reassign(
      '14',
      agentId: 6,
      teamId: 1,
    );

    expect(result.agentName, 'Jane Doe');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/tickets/14/reassign');
    expect(adapter.requests.single.data, {'agent_id': 6, 'team_id': 1});
  });

  test('rejects malformed detail payloads without inventing a ticket',
      () async {
    final repository = RemoteTicketsRepository(
        _api(_QueueAdapter(['{"ok":true}', '{"timeline":[]}'])));
    await expectLater(repository.detail('14'), throwsA(isA<FormatException>()));
  });
}

ApiService _api(_QueueAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
    ..httpClientAdapter = adapter;
  return ApiService(
    baseUrl: 'https://api.example.test',
    dio: dio,
    readAccessToken: () => 'session-token',
    readWorkspaceId: () => '9',
    onUnauthorized: () async {},
  );
}
