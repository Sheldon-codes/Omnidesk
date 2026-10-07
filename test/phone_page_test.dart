import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/components/call_experience/call_session_controller.dart';
import 'package:omnidesk_agent/pages/phone_page/phone_page_widget.dart';
import 'package:omnidesk_agent/pages/customer_editor_page/customer_editor_page_model.dart';
import 'package:omnidesk_agent/pages/customers_page/customer_repository.dart';

class _PhoneCustomersRepository implements CustomerRepository {
  static const _rows = [
    CustomerRecord(
        id: 'c1', name: 'Aloise Obaga Kaizen School', phone: '+254723506031'),
    CustomerRecord(id: 'c2', name: 'Customer Two', phone: '+254700000002'),
    CustomerRecord(id: 'c3', name: 'Customer Three', phone: '+254700000003'),
    CustomerRecord(id: 'c4', name: 'Customer Four', phone: '+254700000004'),
    CustomerRecord(id: 'c5', name: 'Customer Five', phone: '+254700000005'),
    CustomerRecord(id: 'c6', name: 'Customer Six', phone: '+254700000006'),
    CustomerRecord(id: 'c7', name: 'Customer Seven', phone: '+254700000007'),
  ];

  @override
  Future<CustomerPageResult> list({
    String search = '',
    int page = 1,
    int perPage = 20,
    CancelToken? cancelToken,
    void Function(CustomerPageResult)? onCached,
    void Function()? onCacheMiss,
  }) async =>
      CustomerPageResult(
        customers: _rows
            .where(
                (row) => row.name.toLowerCase().contains(search.toLowerCase()))
            .toList(growable: false),
        page: page,
        lastPage: 1,
        total: _rows.length,
      );

  @override
  Future<CustomerProfile> profile(String id,
          {CancelToken? cancelToken,
          void Function(CustomerProfile)? onCached,
          void Function()? onCacheMiss}) =>
      throw UnimplementedError();

  @override
  Future<CustomerRecord> update(String id,
          {required Map<String, Object?> fields,
          required CustomerRecord fallback,
          CancelToken? cancelToken}) async =>
      fallback;
}

void main() {
  test('Phone provider starts on an empty live-history Recents state',
      () async {
    final container = ProviderContainer(overrides: [
      customerRepositoryProvider.overrideWithValue(_PhoneCustomersRepository()),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(phonePageProvider, (_, __) {});
    addTearDown(subscription.close);

    final notifier = container.read(phonePageProvider.notifier);
    expect(container.read(phonePageProvider).tab, PhoneTab.recents);
    expect(container.read(phonePageProvider).subtitle, 'Call history');

    notifier.selectTab(PhoneTab.contacts);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(phonePageProvider).subtitle, '7 contacts');
    expect(container.read(phonePageProvider).query, isEmpty);
    expect(container.read(phonePageProvider).filteredContacts, hasLength(7));
  });

  test('Phone keypad state supports entry, deletion, matching, and reset',
      () async {
    final container = ProviderContainer(overrides: [
      customerRepositoryProvider.overrideWithValue(_PhoneCustomersRepository()),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(phonePageProvider, (_, __) {});
    addTearDown(subscription.close);
    final notifier = container.read(phonePageProvider.notifier);

    notifier.openDialPad();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(phonePageProvider).viewMode, PhoneViewMode.dialPad);
    notifier.appendDigit('+'); // Unsupported symbols are ignored.
    notifier.appendDigit('7');
    notifier.appendDigit('2');
    notifier.appendDigit('3');
    expect(container.read(phonePageProvider).dialedNumber, '723');
    expect(container.read(phonePageProvider).matchedContact?.title,
        'Aloise Obaga Kaizen School');
    notifier.deleteLastDigit();
    expect(container.read(phonePageProvider).dialedNumber, '72');
    notifier.clearDialedNumber();
    expect(container.read(phonePageProvider).dialedNumber, isEmpty);
    notifier.closeDialPad();
    expect(container.read(phonePageProvider).viewMode, PhoneViewMode.list);
  });

  test('Phone call history exposes playback only for a server recording URL',
      () {
    const unavailable = PhoneRecent(
      name: 'Caller',
      phone: '+254700000001',
      time: '12:00',
      detail: '0:18',
    );
    const available = PhoneRecent(
      name: 'Caller',
      phone: '+254700000001',
      time: '12:00',
      detail: '0:18',
      recordingUrl: 'https://recordings.example.test/call-1.mp3',
    );

    expect(unavailable.hasRecording, isFalse);
    expect(available.hasRecording, isTrue);
  });

  testWidgets('Phone search appears below tabs and filters contacts',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerRepositoryProvider
              .overrideWithValue(_PhoneCustomersRepository()),
        ],
        child: MaterialApp(home: PhonePageWidget()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    expect(find.text('7 contacts'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Text && widget.data == 'Aloise Obaga Kaizen School'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Search contacts'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Aloise');
    await tester.pump();
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Text && widget.data == 'Aloise Obaga Kaizen School'),
      findsOneWidget,
    );
    expect(find.text('Caller 1967'), findsNothing);

    await tester.tap(find.byTooltip('Close search').last);
    await tester.pumpAndSettle();
    expect(find.text('Search contacts'), findsNothing);
  });

  testWidgets('Contacts header has no add action and keypad is Recents-only',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerRepositoryProvider
              .overrideWithValue(_PhoneCustomersRepository()),
        ],
        child: MaterialApp(home: PhonePageWidget()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add contact'), findsNothing);
    expect(find.byTooltip('Open keypad'), findsOneWidget);

    await tester.tap(find.byTooltip('Open keypad'));
    await tester.pumpAndSettle();
    expect(find.text('Enter number'), findsOneWidget);
    expect(find.text('Recents'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('7'));
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('71'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Phone'));
    await tester.pumpAndSettle();
    expect(find.text('Recents'), findsOneWidget);

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open keypad'), findsNothing);
    expect(find.byTooltip('Add contact'), findsNothing);
  });

  testWidgets('dial pad hands a non-empty number to the global call session',
      (tester) async {
    final container = ProviderContainer(overrides: [
      customerRepositoryProvider.overrideWithValue(_PhoneCustomersRepository()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PhonePageWidget()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open keypad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7'));
    await tester.tap(find.text('1'));
    await tester.tap(find.byTooltip('Call'));
    await tester.pump();

    final call = container.read(callSessionControllerProvider);
    expect(call.party?.phoneNumber, '71');
    expect(container.read(phonePageProvider).viewMode, PhoneViewMode.list);
    container.read(callSessionControllerProvider.notifier).end();
  });

  testWidgets('Recents never renders fabricated call history or demo actions',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: [
        customerRepositoryProvider
            .overrideWithValue(_PhoneCustomersRepository()),
      ], child: const MaterialApp(home: PhonePageWidget())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Caller 1967'), findsNothing);
    expect(find.byTooltip('Demo incoming call'), findsNothing);
  });
}
