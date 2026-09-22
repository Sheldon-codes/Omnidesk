import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/customer_details_page/customer_details_page_widget.dart';
import 'package:omnidesk_agent/pages/customer_editor_page/customer_editor_page_model.dart';
import 'package:omnidesk_agent/pages/customers_page/customer_repository.dart';

class _FakeCustomerRepository implements CustomerRepository {
  _FakeCustomerRepository({this.fail = false, this.noContact = false});

  final bool fail;
  final bool noContact;

  @override
  Future<CustomerPageResult> list({
    String search = '',
    int page = 1,
    int perPage = 20,
    CancelToken? cancelToken,
    void Function(CustomerPageResult)? onCached,
    void Function()? onCacheMiss,
  }) async =>
      const CustomerPageResult(customers: [], page: 1, lastPage: 1, total: 0);

  @override
  Future<CustomerProfile> profile(String id,
      {CancelToken? cancelToken,
      void Function(CustomerProfile)? onCached,
      void Function()? onCacheMiss}) async {
    if (fail) throw Exception('Offline');
    return CustomerProfile(
      customer: CustomerRecord(
        id: '88',
        name: 'David Mwangi',
        phone: noContact ? '' : '+254768270973',
        email: noContact ? '' : 'david@example.com',
        company: 'Nairobi Tech Ltd',
        ticketsCount: 4,
      ),
      tickets: [
        CustomerProfileTicket(
          id: '14',
          displayNumber: '#TKT-14',
          subject: 'Account - Change email',
          status: 'open',
          priority: 'low',
          source: 'whatsapp',
          createdAt: DateTime.utc(2026, 8, 31),
        ),
      ],
      callLogs: [
        CustomerCallLog(
          id: '6',
          direction: 'inbound',
          status: 'missed',
          durationSeconds: 41,
          fromNumber: '+254743379990',
          toNumber: '+254709369917',
          recordingUrl: null,
          agentName: 'Alice Agent',
          createdAt: DateTime.utc(2026, 9, 21, 15, 22),
          endedAt: DateTime.utc(2026, 9, 21, 15, 23),
        ),
      ],
    );
  }

  @override
  Future<CustomerRecord> update(String id,
          {required Map<String, Object?> fields,
          required CustomerRecord fallback,
          CancelToken? cancelToken}) async =>
      fallback;
}

void main() {
  test('detail starts from shared customer cache and fetches live profile',
      () async {
    final container = ProviderContainer(overrides: [
      customerRepositoryProvider.overrideWithValue(_FakeCustomerRepository()),
    ]);
    addTearDown(container.dispose);
    container.read(customersStoreProvider.notifier).upsert(const CustomerRecord(
          id: '88',
          name: 'David Mwangi',
          email: 'david@example.com',
        ));
    expect(
        container.read(customerDetailProvider(customerId: '88')).customer?.name,
        'David Mwangi');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final state = container.read(customerDetailProvider(customerId: '88'));
    expect(state.hasLoaded, isTrue);
    expect(state.tickets.single.displayNumber, '#TKT-14');
    expect(state.callLogs.single.fromNumber, '+254743379990');
    expect(container.read(customersStoreProvider).single.company,
        'Nairobi Tech Ltd');
  });

  test('unknown customer is not treated as not-found while loading', () async {
    final container = ProviderContainer(overrides: [
      customerRepositoryProvider
          .overrideWithValue(_FakeCustomerRepository(fail: true)),
    ]);
    addTearDown(container.dispose);
    final initial =
        container.read(customerDetailProvider(customerId: 'missing'));
    expect(initial.notFound, isFalse);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final failed =
        container.read(customerDetailProvider(customerId: 'missing'));
    expect(failed.error, contains('Offline'));
    expect(failed.notFound, isFalse);
  });

  testWidgets('detail renders live tickets and call-log activity',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        customerRepositoryProvider.overrideWithValue(_FakeCustomerRepository())
      ],
      child:
          const MaterialApp(home: CustomerDetailsPageWidget(customerId: '88')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('David Mwangi'), findsOneWidget);
    expect(find.text('#TKT-14'), findsWidgets);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Inbound call · Missed'), findsOneWidget);
    expect(find.textContaining('Alice Agent'), findsOneWidget);
    expect(find.byTooltip('Edit customer'), findsOneWidget);
  });

  testWidgets('contact actions are omitted when contact data is unavailable',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        customerRepositoryProvider
            .overrideWithValue(_FakeCustomerRepository(noContact: true))
      ],
      child:
          const MaterialApp(home: CustomerDetailsPageWidget(customerId: '88')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Call'), findsNothing);
    expect(find.text('WhatsApp'), findsNothing);
    expect(find.text('Email'), findsNothing);
  });
}
