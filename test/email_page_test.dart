import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/email_page/email_page_widget.dart';

void main() {
  test('Email provider exposes folders and composes search with selection', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(emailPageProvider.notifier);
    final initial = container.read(emailPageProvider);
    expect(initial.folder, EmailFolder.inbox);
    expect(initial.filteredMessages, isNotEmpty);
    expect(initial.subtitle, '21 messages · 11 unread');

    notifier.selectFolder(EmailFolder.pending);
    expect(container.read(emailPageProvider).filteredMessages, hasLength(2));
    notifier.setSearchQuery('360');
    expect(container.read(emailPageProvider).filteredMessages.single.ticketId,
        'DGKSL-360');

    notifier.selectFolder(EmailFolder.starred);
    final starred = container.read(emailPageProvider);
    expect(starred.folder, EmailFolder.starred);
    expect(starred.query, isEmpty);
    expect(starred.filteredMessages, isNotEmpty);
  });

  testWidgets('Email folders, search, and all folder tabs are available',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: EmailPageWidget()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('21 messages · 11 unread'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Starred'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.byTooltip('Compose email'), findsNWidgets(2));
    expect(find.text('accounts@bigbrainz.co.ke'), findsOneWidget);
    expect(find.text('DGKSL-386'), findsOneWidget);

    await tester.tap(find.text('Pending'));
    await tester.pumpAndSettle();
    expect(find.text('Requisition approval required'), findsOneWidget);

    await tester.tap(find.text('Starred'));
    await tester.pumpAndSettle();
    expect(find.text('Fwd: SCHOOL MANAGEMENT SYSTEM'), findsOneWidget);

    await tester.tap(find.byTooltip('Search email'));
    await tester.pumpAndSettle();
    expect(find.text('Search email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bigbrainz');
    await tester.pump();
    expect(find.text('accounts@bigbrainz.co.ke'), findsOneWidget);
    expect(find.text('Tony Kirui Sunshine'), findsNothing);

    await tester.tap(find.byTooltip('Close search').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}
