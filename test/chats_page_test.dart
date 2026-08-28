import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/chats_page/chats_page_widget.dart';

void main() {
  test('Chats provider filters by channel, type, status, and query', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(chatsPageProvider.notifier);
    final initial = container.read(chatsPageProvider);
    expect(initial.channel, ChatChannel.whatsapp);
    expect(initial.filteredConversations, hasLength(5));

    notifier.applyFilters(
      type: ChatConversationType.groups,
      status: ChatConversationStatus.open,
    );
    expect(
        container.read(chatsPageProvider).filteredConversations, hasLength(2));

    notifier.setSearchQuery('wika');
    expect(container.read(chatsPageProvider).filteredConversations.single.name,
        'Wika School');

    notifier.selectChannel(ChatChannel.liveChat);
    expect(container.read(chatsPageProvider).subtitle, '1 open · 73 resolved');
    expect(container.read(chatsPageProvider).query, isEmpty);
    expect(container.read(chatsPageProvider).type, ChatConversationType.all);
  });

  testWidgets('Chats tabs, search, and filter sheet are available',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ChatsPageWidget()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('kirawafinance'), findsOneWidget);
    await tester.tap(find.text('Live Chat'));
    await tester.pumpAndSettle();
    expect(find.text('1 open · 73 resolved'), findsOneWidget);
    expect(find.text('Phyllis'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Search live chats'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'David');
    await tester.pump();
    expect(find.text('David'), findsWidgets);
    expect(find.text('Phyllis'), findsNothing);

    await tester.tap(find.byTooltip('Close search').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter conversations'));
    await tester.pumpAndSettle();
    expect(find.text('Filter conversations'), findsOneWidget);
    expect(find.text('DMs'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
  });
}
