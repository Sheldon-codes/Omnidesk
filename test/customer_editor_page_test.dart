import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:omnidesk_agent/pages/customer_editor_page/customer_editor_page_widget.dart';

void main() {
  test('customer editor validates and stores a new customer', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container
        .read(customerEditorNotifierProvider(customerId: null).notifier);
    notifier.setName('New Customer');
    notifier.setEmail('customer@example.com');
    final record = notifier.submit();
    expect(record?.name, 'New Customer');
    expect(
        container.read(customersStoreProvider),
        contains(predicate<CustomerRecord>(
            (value) => value.name == 'New Customer')));
  });

  testWidgets('create editor renders sliver form and fixed CTA',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: CustomerEditorPageWidget()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Create customer'), findsNWidgets(2));
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Company'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.byIcon(IconsaxPlusBroken.arrow_left_2), findsOneWidget);
  });
}
