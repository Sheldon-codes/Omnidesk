import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:omnidesk_agent/pages/ticket_details_page/ticket_details_page_widget.dart';
import 'package:omnidesk_agent/pages/ticket_editor_page/ticket_editor_page_widget.dart';
import 'package:omnidesk_agent/pages/tickets_page/tickets_page_widget.dart';

class _TicketRepository implements TicketsRepository {
  @override
  Future<TicketFilterOptions> filters(
          {CancelToken? cancelToken,
          void Function(TicketFilterOptions)? onCached,
          void Function()? onCacheMiss}) async =>
      const TicketFilterOptions();
  @override
  Future<TicketPageResult> list(TicketQuery query,
          {CancelToken? cancelToken,
          void Function(TicketPageResult)? onCached,
          void Function()? onCacheMiss}) async =>
      const TicketPageResult(tickets: [], page: 1, lastPage: 1, total: 0);
  @override
  Future<TicketDetailResult> detail(String id,
          {CancelToken? cancelToken,
          void Function(TicketDetailResult)? onCached,
          void Function()? onCacheMiss}) async =>
      TicketDetailResult(
        ticket: ticketFixtures[1],
        activity: ticketFixtures[1].activities,
      );
  @override
  Future<void> updateStatus(String id, String status,
      {String? reason, CancelToken? cancelToken}) async {}
  @override
  Future<TicketReassignmentResult> reassign(String id,
          {required int agentId, int? teamId}) async =>
      TicketReassignmentResult(agentName: 'Agent');
}

void main() {
  testWidgets('ticket detail presents the case workspace and resolve action',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          ticketsRepositoryProvider.overrideWith((ref) => _TicketRepository())
        ],
        child: const MaterialApp(
            home: TicketDetailsPageWidget(ticketId: 'DGKSL-388'))));
    await tester.pumpAndSettle();
    expect(find.text('DGKSL-388'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Resolve ticket'), findsOneWidget);
  });

  testWidgets('ticket creation screen is blocked', (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: TicketEditorPageWidget())));
    await tester.pumpAndSettle();
    expect(find.text('Creating tickets is not available.'), findsOneWidget);
    expect(find.text('Ticket info'), findsNothing);
  });

  test('editor notifier refuses create submissions', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier =
        container.read(ticketEditorProvider(ticketId: null).notifier);

    expect(await notifier.submit(), isNull);
    expect(
      container.read(ticketEditorProvider(ticketId: null)).errors['form'],
      'Creating tickets is not available.',
    );
  });
}
