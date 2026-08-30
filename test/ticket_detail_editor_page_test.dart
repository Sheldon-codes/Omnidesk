import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/ticket_details_page/ticket_details_page_widget.dart';
import 'package:omnidesk_agent/pages/ticket_editor_page/ticket_editor_page_widget.dart';

void main() {
  testWidgets('ticket detail presents the case workspace and resolve action',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child:
            MaterialApp(home: TicketDetailsPageWidget(ticketId: 'DGKSL-388'))));
    await tester.pumpAndSettle();
    expect(find.text('DGKSL-388'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Resolve ticket'), findsOneWidget);
  });

  testWidgets(
      'ticket editor has separate information and classification sections',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: TicketEditorPageWidget())));
    await tester.pumpAndSettle();
    expect(find.text('Create ticket'), findsWidgets);
    expect(find.text('Ticket info'), findsOneWidget);
  });
}
