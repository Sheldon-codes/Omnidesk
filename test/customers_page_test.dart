import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omnidesk_agent/pages/customer_details_page/customer_details_page_widget.dart';
import 'package:omnidesk_agent/pages/customer_editor_page/customer_editor_page_model.dart';
import 'package:omnidesk_agent/pages/customers_page/customer_repository.dart';
import 'package:omnidesk_agent/pages/customers_page/customers_page_widget.dart';

class _CustomersRepository implements CustomerRepository {
  final queries = <String>[];

  @override
  Future<CustomerPageResult> list({
    String search = '',
    int page = 1,
    int perPage = 20,
    CancelToken? cancelToken,
    void Function(CustomerPageResult)? onCached,
    void Function()? onCacheMiss,
  }) async {
    queries.add('$search:$page:$perPage');
    final rows = search.isEmpty
        ? [
            const CustomerRecord(
                id: '88', name: 'David Mwangi', email: 'david@example.com'),
            const CustomerRecord(
                id: '89', name: 'Jane Doe', phone: '+254700000000'),
          ]
        : [
            const CustomerRecord(
                id: '88', name: 'David Mwangi', email: 'david@example.com'),
          ];
    return CustomerPageResult(
      customers: rows,
      page: page,
      lastPage: page == 1 ? 2 : 2,
      total: 3,
    );
  }

  @override
  Future<CustomerProfile> profile(String id,
          {CancelToken? cancelToken,
          void Function(CustomerProfile)? onCached,
          void Function()? onCacheMiss}) async =>
      CustomerProfile(
        customer: const CustomerRecord(
            id: '88', name: 'David Mwangi', email: 'david@example.com'),
        tickets: const [],
        callLogs: const [],
      );
}

void main() {
  test('customers list loads pages into the shared customer cache', () async {
    final repository = _CustomersRepository();
    final container = ProviderContainer(overrides: [
      customerRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    await container.read(customersPageProvider.notifier).load();
    expect(container.read(customersPageProvider).customers, hasLength(2));
    expect(container.read(customersStoreProvider).map((item) => item.id),
        contains('88'));
    await container.read(customersPageProvider.notifier).loadMore();
    expect(repository.queries, [' :1:20'.trim(), ' :2:20'.trim()]);
  });

  testWidgets(
      'directory row opens standalone customer detail with cached identity',
      (tester) async {
    final repository = _CustomersRepository();
    final router = GoRouter(
      initialLocation: '/customers',
      routes: [
        GoRoute(
          path: '/customers',
          builder: (_, __) => const CustomersPageWidget(),
        ),
        GoRoute(
          path: '/customers/:id',
          builder: (_, state) => CustomerDetailsPageWidget(
            customerId: state.pathParameters['id']!,
            initialCustomer: state.extra is CustomerRecord
                ? state.extra as CustomerRecord
                : null,
          ),
        ),
        GoRoute(
          path: '/customers/new',
          builder: (_, __) => const Scaffold(body: Text('Create customer')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [customerRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('David Mwangi'), findsOneWidget);
    await tester.tap(find.text('David Mwangi'));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
  });
}
