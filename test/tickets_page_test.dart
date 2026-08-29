import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/tickets_page/tickets_page_widget.dart';

void main() {
  test('Tickets provider filters status, metadata, and search together', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(ticketsPageProvider.notifier);
    final initial = container.read(ticketsPageProvider);

    expect(initial.selectedStatus, TicketStatus.open);
    expect(initial.filteredTickets, hasLength(2));
    expect(initial.filteredTickets.first.id, 'DGKSL-392');

    notifier.selectStatus(TicketStatus.overdue);
    expect(container.read(ticketsPageProvider).filteredTickets.single.id,
        'DGKSL-378');

    notifier.applyFilters(
      status: null,
      priorities: {TicketPriority.high},
      departments: {'Finance'},
      categories: {'Accounting'},
    );
    expect(container.read(ticketsPageProvider).filteredTickets, hasLength(1));
    notifier.setSearchQuery('373');
    expect(container.read(ticketsPageProvider).filteredTickets.single.customer,
        'Nana Betterstream');

    notifier.closeSearch();
    expect(container.read(ticketsPageProvider).query, isEmpty);
    notifier.clearFilters();
    expect(container.read(ticketsPageProvider).selectedStatus, isNull);
    expect(container.read(ticketsPageProvider).filteredTickets, hasLength(7));
  });

  testWidgets('Tickets page renders tabs, search, and filter sheet',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: TicketsPageWidget()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('7 open · 2 overdue'), findsOneWidget);
    expect(find.text('DGKSL-392'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Open'), findsWidgets);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Escalated'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('DGKSL-378'), findsOneWidget);

    await tester.tap(find.text('Overdue').first);
    await tester.pumpAndSettle();
    expect(find.text('DGKSL-378'), findsOneWidget);
    expect(find.text('DGKSL-392'), findsNothing);

    await tester.tap(find.byTooltip('Search tickets'));
    await tester.pumpAndSettle();
    expect(find.text('Search tickets...'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Deborah');
    await tester.pump();
    expect(find.text('DGKSL-378'), findsOneWidget);

    await tester.tap(find.byTooltip('Close search').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter tickets'));
    await tester.pumpAndSettle();
    expect(find.text('Filter tickets'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Department'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('Tickets query status and swipe actions are supported',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TicketsPageWidget(initialStatus: TicketStatus.overdue),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DGKSL-378'), findsOneWidget);
    expect(find.text('DGKSL-392'), findsNothing);

    await tester.drag(find.text('DGKSL-378'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.text('Resolve'), findsOneWidget);
    expect(find.text('Assign'), findsOneWidget);
  });
}
