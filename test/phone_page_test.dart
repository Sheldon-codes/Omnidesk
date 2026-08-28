import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/phone_page/phone_page_widget.dart';

void main() {
  test('Phone provider starts on Recents and filters local fixtures', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(phonePageProvider.notifier);
    expect(container.read(phonePageProvider).tab, PhoneTab.recents);
    expect(container.read(phonePageProvider).filteredRecents, hasLength(5));

    notifier.setSearchQuery('1967');
    expect(container.read(phonePageProvider).filteredRecents, hasLength(1));
    expect(container.read(phonePageProvider).filteredRecents.single.name,
        'Caller 1967');

    notifier.selectTab(PhoneTab.contacts);
    expect(container.read(phonePageProvider).subtitle, '192 contacts');
    expect(container.read(phonePageProvider).query, isEmpty);
    expect(container.read(phonePageProvider).filteredContacts, hasLength(6));
  });

  testWidgets('Phone search appears below tabs and filters contacts',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PhonePageWidget()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    expect(find.text('192 contacts'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Nana'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Search contacts'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Nana');
    await tester.pump();
    expect(
      find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Nana'),
      findsOneWidget,
    );
    expect(find.text('Caller 1967'), findsNothing);

    await tester.tap(find.byTooltip('Close search').last);
    await tester.pumpAndSettle();
    expect(find.text('Search contacts'), findsNothing);
  });

  testWidgets('Add contact stays in the header and keypad is Recents-only',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PhonePageWidget()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add contact'), findsOneWidget);
    expect(find.byTooltip('Open keypad'), findsOneWidget);

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open keypad'), findsNothing);
    expect(find.byTooltip('Add contact'), findsOneWidget);
  });

  testWidgets('swipe actions reveal Coming soon feedback', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PhonePageWidget()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('Caller 1967'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call').at(1));
    await tester.pump();

    expect(find.text('Coming soon'), findsOneWidget);
    await tester.pumpAndSettle();

    await tester.drag(find.text('Caller 1967'), const Offset(180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call').first);
    await tester.pump();

    expect(find.text('Coming soon'), findsOneWidget);
  });
}
