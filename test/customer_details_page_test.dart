import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/customer_details_page/customer_details_page_widget.dart';

void main() {
  test('details provider resolves customer and local history', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state =
        container.read(customerDetailNotifierProvider(customerId: 'nana'));

    expect(state.customer?.name, 'Nana');
    expect(state.tickets, isNotEmpty);
    expect(state.activities, isNotEmpty);
  });

  test('fully populated customer fixture exposes all detail sections', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container
        .read(customerDetailNotifierProvider(customerId: 'aloise-obaga'));

    expect(state.customer?.email, 'aloise.obaga@example.com');
    expect(state.customer?.phone, '+254723506031');
    expect(state.customer?.company, 'Kaizen School');
    expect(state.customer?.notes, isNotEmpty);
    expect(state.tickets, hasLength(2));
    expect(state.activities, hasLength(3));
  });

  test('details provider returns not found for unknown customer', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state =
        container.read(customerDetailNotifierProvider(customerId: 'missing'));

    expect(state.notFound, isTrue);
    expect(state.tickets, isEmpty);
    expect(state.activities, isEmpty);
  });

  testWidgets('details page renders identity, sections, and actions',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: CustomerDetailsPageWidget(customerId: 'nana'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Nana'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('DGKSL-376'), findsOneWidget);
    expect(find.byTooltip('Edit customer'), findsOneWidget);
    expect(find.byTooltip('Download customer report'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('quick action gives coming soon feedback', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: CustomerDetailsPageWidget(customerId: 'nana'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Message'));
    await tester.pump();
    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('download report gives coming soon feedback', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: CustomerDetailsPageWidget(customerId: 'nana'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Download customer report'));
    await tester.pump();
    expect(find.text('Coming soon'), findsOneWidget);
  });
}
