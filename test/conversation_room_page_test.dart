import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/conversation_room_page/conversation_room_page_widget.dart';

void main() {
  test('conversation store updates a thread, preview, and resolution state',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(conversationStoreProvider.notifier);

    final initial = store.findById('aloise-whatsapp')!;
    expect(initial.conversation.channel, ChatChannel.whatsapp);
    expect(initial.capabilities.canSendDocuments, isTrue);
    expect(initial.messages, isNotEmpty);
    expect(initial.messages.any((item) => item.content is ImageMessageContent),
        isTrue);
    expect(initial.messages.any((item) => item.content is VideoMessageContent),
        isTrue);
    expect(initial.messages.any((item) => item.content is AudioMessageContent),
        isTrue);
    expect(
        initial.messages.any((item) => item.content is LocationMessageContent),
        isTrue);

    store.sendText('aloise-whatsapp', '  Reply from mobile  ',
        replyToId: 'aloise-3');
    expect(
        store.findById('aloise-whatsapp')!.messages.last.replyToId, 'aloise-3');

    store.addReaction('aloise-whatsapp', 'aloise-8', '👍');
    expect(
        store
            .findById('aloise-whatsapp')!
            .messages
            .firstWhere((item) => item.id == 'aloise-8')
            .reactions
            .any((item) => item.emoji == '👍' && item.reactedByAgent),
        isTrue);

    store.retryMessage('aloise-whatsapp', 'aloise-15');
    expect(
        store
            .findById('aloise-whatsapp')!
            .messages
            .firstWhere((item) => item.id == 'aloise-15')
            .delivery,
        MessageDelivery.sent);

    store.sendText('aloise-whatsapp', '  Sent from mobile  ');
    final sent = store.findById('aloise-whatsapp')!;
    expect(sent.messages.last.content, isA<TextMessageContent>());
    expect(sent.conversation.preview, 'Sent from mobile');

    store.resolve('aloise-whatsapp');
    expect(store.findById('aloise-whatsapp')!.conversation.status,
        ChatConversationStatus.resolved);
    store.reopen('aloise-whatsapp');
    expect(store.findById('aloise-whatsapp')!.conversation.status,
        ChatConversationStatus.open);
  });

  testWidgets('conversation room renders, sends locally, and resolves',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: ConversationRoomPageWidget(conversationId: 'aloise-whatsapp'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Aloise Obaga Kaizen School'), findsOneWidget);
    expect(find.text('WhatsApp · DGKSL-103'), findsOneWidget);
    expect(find.text('Satisfaction survey sent'), findsOneWidget);
    expect(find.text('Type a message…'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'A local reply');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('A local reply'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Conversation actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolve conversation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();
    expect(find.text('Conversation resolved'), findsWidgets);
    expect(find.text('Reopen'), findsOneWidget);
  });

  testWidgets('swipe reply links the outgoing message to its source',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: ConversationRoomPageWidget(conversationId: 'aloise-whatsapp'),
      ),
    ));
    await tester.pumpAndSettle();

    const sourceText = 'Got it. I have added the location to the case.';
    await tester.drag(find.text(sourceText), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(find.text('Replying to yourself'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Retrying with context');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    final thread = container
        .read(conversationStoreProvider.notifier)
        .findById('aloise-whatsapp')!;
    expect(thread.messages.last.replyToId, 'aloise-15');
  });
}
