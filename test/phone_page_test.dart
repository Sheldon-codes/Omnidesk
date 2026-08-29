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

  test('Phone keypad state supports entry, deletion, matching, and reset', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(phonePageProvider.notifier);

    notifier.openDialPad();
    expect(container.read(phonePageProvider).viewMode, PhoneViewMode.dialPad);
    notifier.appendDigit('+'); // Unsupported symbols are ignored.
    notifier.appendDigit('7');
    notifier.appendDigit('1');
    notifier.appendDigit('9');
    expect(container.read(phonePageProvider).dialedNumber, '719');
    expect(container.read(phonePageProvider).matchedContact?.title, 'Nana');
    notifier.deleteLastDigit();
    expect(container.read(phonePageProvider).dialedNumber, '71');
    notifier.clearDialedNumber();
    expect(container.read(phonePageProvider).dialedNumber, isEmpty);
    notifier.closeDialPad();
    expect(container.read(phonePageProvider).viewMode, PhoneViewMode.list);
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

    await tester.tap(find.byTooltip('Open keypad'));
    await tester.pumpAndSettle();
    expect(find.text('Enter number'), findsOneWidget);
    expect(find.text('Recents'), findsNothing);
    expect(find.bySemanticsLabel('Digit 2, ABC'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Digit 7, PQRS'));
    await tester.tap(find.bySemanticsLabel('Digit 1'));
    await tester.pump();
    expect(find.text('71'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Phone'));
    await tester.pumpAndSettle();
    expect(find.text('Recents'), findsOneWidget);

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
