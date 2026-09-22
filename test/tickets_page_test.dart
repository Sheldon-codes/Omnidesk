import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:omnidesk_agent/pages/ticket_details_page/ticket_details_page_widget.dart';
import 'package:omnidesk_agent/pages/tickets_page/tickets_page_widget.dart';

class _FakeTicketsRepository implements TicketsRepository {
  _FakeTicketsRepository({TicketFilterOptions? options})
      : _options = options ??
            const TicketFilterOptions(
              statuses: [
                TicketFilterOption(value: 'open', label: 'Open'),
                TicketFilterOption(value: 'in_progress', label: 'In Progress'),
              ],
              sources: [
                TicketFilterOption(value: 'phone', label: 'Phone'),
              ],
              priorities: [
                TicketFilterOption(value: 'urgent', label: 'Urgent'),
              ],
              categories: [
                TicketFilterOption(value: '2', label: 'Billing'),
              ],
            );

  final TicketFilterOptions _options;
  final requests = <TicketQuery>[];
  final TicketRecord ticket = ticketFixtures.first.copyWith(
    displayId: '#TKT-392',
    department: '',
    description: const TicketDescription(plainText: 'Live ticket details.'),
  );

  @override
  Future<TicketFilterOptions> filters(
          {CancelToken? cancelToken,
          void Function(TicketFilterOptions)? onCached,
          void Function()? onCacheMiss}) async =>
      _options;

  @override
  Future<TicketPageResult> list(TicketQuery query,
      {CancelToken? cancelToken,
      void Function(TicketPageResult)? onCached,
      void Function()? onCacheMiss}) async {
    requests.add(query);
    final matches =
        query.status == null || query.status == ticket.status.apiValue
            ? [ticket]
            : <TicketRecord>[];
    return TicketPageResult(
      tickets: matches,
      page: query.page,
      lastPage: 1,
      total: matches.length,
    );
  }

  @override
  Future<TicketDetailResult> detail(String id,
          {CancelToken? cancelToken,
          void Function(TicketDetailResult)? onCached,
          void Function()? onCacheMiss}) async =>
      TicketDetailResult(
        ticket: ticket,
        activity: [
          TicketActivity(
            id: 'event-1',
            type: TicketActivityType.messageReceived,
            title: 'Customer message',
            description: 'Need billing assistance.',
            timestamp: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

  @override
  Future<void> updateStatus(String id, String status,
      {String? reason, CancelToken? cancelToken}) async {}
}

void main() {
  testWidgets('filter sheet only renders configured fields and always dates',
      (tester) async {
    final repository = _FakeTicketsRepository(
      options: const TicketFilterOptions(
        statuses: [
          TicketFilterOption(value: 'awaiting_vendor', label: 'Awaiting vendor')
        ],
      ),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [ticketsRepositoryProvider.overrideWith((ref) => repository)],
      child: const MaterialApp(home: TicketsPageWidget()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter tickets'));
    await tester.pumpAndSettle();

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Date range'), findsOneWidget);
    expect(find.text('Source'), findsNothing);
    expect(find.text('Priority'), findsNothing);
    expect(find.text('Department'), findsNothing);
    expect(find.text('Category'), findsNothing);
    expect(find.text('Assignment'), findsNothing);
    expect(find.text('Awaiting vendor'), findsWidgets);

    await tester.tap(find.byType(InputDecorator).first);
    await tester.pumpAndSettle();
    expect(find.text('Awaiting vendor'), findsWidgets);
    expect(find.byIcon(IconsaxPlusBroken.setting_2), findsWidgets);
  });

  testWidgets('Tickets list loads live rows and submits dynamic filters',
      (tester) async {
    final repository = _FakeTicketsRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [ticketsRepositoryProvider.overrideWith((ref) => repository)],
      child: const MaterialApp(home: TicketsPageWidget()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('#TKT-392'), findsOneWidget);
    expect(repository.requests.first.assignment, 'me');
    expect(repository.requests.first.status, 'open');

    await tester.tap(find.byTooltip('Filter tickets'));
    await tester.pumpAndSettle();
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Department'), findsNothing);
    await tester.drag(find.byType(ListView).last, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(InputDecorator).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(repository.requests.last.source, 'phone');
  });

  testWidgets('ticket list opens standalone detail with loaded API content',
      (tester) async {
    final repository = _FakeTicketsRepository();
    final router = GoRouter(
      initialLocation: '/tickets',
      routes: [
        GoRoute(
          path: '/tickets',
          builder: (_, __) => const TicketsPageWidget(),
        ),
        GoRoute(
          path: '/tickets/:ticketId',
          builder: (_, state) => TicketDetailsPageWidget(
              ticketId: state.pathParameters['ticketId']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [ticketsRepositoryProvider.overrideWith((ref) => repository)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#TKT-392'));
    await tester.pumpAndSettle();

    expect(find.text('Live ticket details.'), findsOneWidget);
    await tester.drag(
        find.byType(CustomScrollView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Customer message'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });
}
