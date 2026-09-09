import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'conversation_room_page_model.g.dart';

enum ChatChannel { whatsapp, widgetChat }

extension ChatChannelLabel on ChatChannel {
  String get label => switch (this) {
        ChatChannel.whatsapp => 'WhatsApp',
        ChatChannel.widgetChat => 'Widget Chat',
      };
}

enum ChatConversationType { all, dms, groups }

enum ChatConversationStatus { all, open, resolved }

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.channel,
    required this.type,
    required this.status,
    required this.name,
    required this.preview,
    required this.time,
    this.avatar,
    this.avatarUrl,
    this.customerId,
    this.contactIdentifier,
    this.unreadCount = 0,
    this.ticketId,
  });

  final String id;
  final ChatChannel channel;
  final ChatConversationType type;
  final ChatConversationStatus status;
  final String name;
  final String preview;
  final String time;
  final String? avatar;
  final String? avatarUrl;
  final String? customerId;
  final String? contactIdentifier;
  final int unreadCount;
  final String? ticketId;

  String get initials =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  ChatConversation copyWith({
    ChatConversationStatus? status,
    String? preview,
    String? time,
    int? unreadCount,
    String? avatarUrl,
  }) =>
      ChatConversation(
        id: id,
        channel: channel,
        type: type,
        status: status ?? this.status,
        name: name,
        preview: preview ?? this.preview,
        time: time ?? this.time,
        avatar: avatar,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        customerId: customerId,
        contactIdentifier: contactIdentifier,
        unreadCount: unreadCount ?? this.unreadCount,
        ticketId: ticketId,
      );
}

enum MessageSender { customer, agent, system }

enum MessageDelivery { none, sending, sent, delivered, read, failed }

sealed class ConversationMessageContent {
  const ConversationMessageContent();
}

class TextMessageContent extends ConversationMessageContent {
  const TextMessageContent(this.text);
  final String text;
}

class ImageMessageContent extends ConversationMessageContent {
  const ImageMessageContent({
    required this.assetPath,
    this.caption,
    this.width,
    this.height,
    this.viewOnce = false,
    this.opened = false,
  });
  final String assetPath;
  final String? caption;
  final double? width;
  final double? height;
  final bool viewOnce;
  final bool opened;
}

class VideoMessageContent extends ConversationMessageContent {
  const VideoMessageContent({
    required this.assetPath,
    required this.thumbnailAssetPath,
    required this.duration,
    this.caption,
    this.viewOnce = false,
    this.opened = false,
  });
  final String assetPath;
  final String thumbnailAssetPath;
  final Duration duration;
  final String? caption;
  final bool viewOnce;
  final bool opened;
}

class AudioMessageContent extends ConversationMessageContent {
  const AudioMessageContent({
    required this.assetPath,
    required this.duration,
    required this.waveform,
    this.viewOnce = false,
    this.opened = false,
  });
  final String assetPath;
  final Duration duration;
  final List<double> waveform;
  final bool viewOnce;
  final bool opened;
}

class DocumentMessageContent extends ConversationMessageContent {
  const DocumentMessageContent({
    required this.assetPath,
    required this.fileName,
    required this.mimeType,
    required this.sizeLabel,
  });
  final String assetPath;
  final String fileName;
  final String mimeType;
  final String sizeLabel;
  String get description => '${mimeType.toUpperCase()} · $sizeLabel';
}

class LocationMessageContent extends ConversationMessageContent {
  const LocationMessageContent({
    required this.title,
    required this.subtitle,
    required this.previewAssetPath,
    this.latitude,
    this.longitude,
  });
  final String title;
  final String subtitle;
  final String previewAssetPath;
  final double? latitude;
  final double? longitude;
}

class ContactMessageContent extends ConversationMessageContent {
  const ContactMessageContent({
    required this.name,
    required this.phone,
    this.avatar,
    this.customerId,
  });
  final String name;
  final String phone;
  final String? avatar;
  final String? customerId;
}

class SystemMessageContent extends ConversationMessageContent {
  const SystemMessageContent(this.text, {this.emphasized = false});
  final String text;
  final bool emphasized;
}

class UnsupportedMessageContent extends ConversationMessageContent {
  const UnsupportedMessageContent(this.description);
  final String description;
}

class MessageReaction {
  const MessageReaction({
    required this.emoji,
    this.count = 1,
    this.reactedByAgent = false,
  });
  final String emoji;
  final int count;
  final bool reactedByAgent;

  MessageReaction copyWith({int? count, bool? reactedByAgent}) =>
      MessageReaction(
        emoji: emoji,
        count: count ?? this.count,
        reactedByAgent: reactedByAgent ?? this.reactedByAgent,
      );
}

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.sender,
    required this.sentAt,
    required this.content,
    this.delivery = MessageDelivery.none,
    this.replyToId,
    this.reactions = const [],
    this.quotedText,
    this.quotedSenderName,
    this.agentName,
    this.customerAvatarUrl,
    this.fallbackLabel,
    this.uploadProgress,
  });
  final String id;
  final MessageSender sender;
  final DateTime sentAt;
  final ConversationMessageContent content;
  final MessageDelivery delivery;
  final String? replyToId;
  final List<MessageReaction> reactions;
  final String? quotedText;
  final String? quotedSenderName;
  final String? agentName;
  final String? customerAvatarUrl;
  final String? fallbackLabel;
  final double? uploadProgress;

  ConversationMessage copyWith({
    MessageDelivery? delivery,
    List<MessageReaction>? reactions,
    double? uploadProgress,
    bool clearUploadProgress = false,
  }) =>
      ConversationMessage(
        id: id,
        sender: sender,
        sentAt: sentAt,
        content: content,
        delivery: delivery ?? this.delivery,
        replyToId: replyToId,
        reactions: reactions ?? this.reactions,
        quotedText: quotedText,
        quotedSenderName: quotedSenderName,
        agentName: agentName,
        customerAvatarUrl: customerAvatarUrl,
        fallbackLabel: fallbackLabel,
        uploadProgress:
            clearUploadProgress ? null : (uploadProgress ?? this.uploadProgress),
      );
}

class ConversationCapabilities {
  const ConversationCapabilities({
    required this.canSendText,
    required this.canSendImages,
    required this.canSendVideo,
    required this.canSendDocuments,
    required this.canSendLocations,
    required this.canSendContacts,
    required this.canReply,
    required this.showsDeliveryReceipts,
  });
  final bool canSendText;
  final bool canSendImages;
  final bool canSendVideo;
  final bool canSendDocuments;
  final bool canSendLocations;
  final bool canSendContacts;
  final bool canReply;
  final bool showsDeliveryReceipts;

  static const whatsApp = ConversationCapabilities(
    canSendText: true,
    canSendImages: true,
    canSendVideo: true,
    canSendDocuments: true,
    canSendLocations: true,
    canSendContacts: true,
    canReply: true,
    showsDeliveryReceipts: true,
  );
  static const widgetChat = ConversationCapabilities(
    canSendText: true,
    canSendImages: true,
    canSendVideo: false,
    canSendDocuments: false,
    canSendLocations: false,
    canSendContacts: false,
    canReply: false,
    showsDeliveryReceipts: false,
  );
}

class ConversationThread {
  const ConversationThread({
    required this.conversation,
    required this.messages,
    required this.summary,
    this.hasOlderMessages = false,
    this.isLoadingOlderMessages = false,
  });
  final ChatConversation conversation;
  final List<ConversationMessage> messages;
  final String summary;
  final bool hasOlderMessages;
  final bool isLoadingOlderMessages;

  ConversationCapabilities get capabilities =>
      conversation.channel == ChatChannel.whatsapp
          ? ConversationCapabilities.whatsApp
          : ConversationCapabilities.widgetChat;

  ConversationThread copyWith({
    ChatConversation? conversation,
    List<ConversationMessage>? messages,
    bool? isLoadingOlderMessages,
  }) =>
      ConversationThread(
        conversation: conversation ?? this.conversation,
        messages: messages ?? this.messages,
        summary: summary,
        hasOlderMessages: hasOlderMessages,
        isLoadingOlderMessages:
            isLoadingOlderMessages ?? this.isLoadingOlderMessages,
      );
}

@Riverpod(keepAlive: true)
class ConversationStore extends _$ConversationStore {
  @override
  List<ConversationThread> build() => _initialThreads;

  ConversationThread? findById(String id) {
    for (final thread in state) {
      if (thread.conversation.id == id) return thread;
    }
    return null;
  }

  void sendText(String conversationId, String rawText, {String? replyToId}) {
    final text = rawText.trim();
    if (text.isEmpty) return;
    sendContent(conversationId, TextMessageContent(text), replyToId: replyToId);
  }

  void sendContent(
    String conversationId,
    ConversationMessageContent content, {
    String? replyToId,
  }) {
    _update(conversationId, (thread) {
      final message = ConversationMessage(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        sender: MessageSender.agent,
        sentAt: DateTime.now(),
        content: content,
        replyToId: replyToId,
        delivery: thread.capabilities.showsDeliveryReceipts
            ? MessageDelivery.sent
            : MessageDelivery.none,
      );
      return thread.copyWith(
        messages: [...thread.messages, message],
        conversation: thread.conversation.copyWith(
          preview: conversationMessagePreview(content),
          time: 'Now',
          unreadCount: 0,
        ),
      );
    });
  }

  void addReaction(String conversationId, String messageId, String emoji) {
    _update(conversationId, (thread) {
      final messages = [
        for (final message in thread.messages)
          if (message.id == messageId)
            message.copyWith(reactions: _toggleReaction(message, emoji))
          else
            message,
      ];
      return thread.copyWith(messages: messages);
    });
  }

  void retryMessage(String conversationId, String messageId) {
    _update(conversationId, (thread) {
      final messages = [
        for (final message in thread.messages)
          if (message.id == messageId &&
              message.delivery == MessageDelivery.failed)
            message.copyWith(delivery: MessageDelivery.sent)
          else
            message,
      ];
      return thread.copyWith(messages: messages);
    });
  }

  void markUnread(String conversationId) => _update(
        conversationId,
        (thread) => thread.copyWith(
          conversation: thread.conversation.copyWith(unreadCount: 1),
        ),
      );

  void resolve(String conversationId) => _update(
        conversationId,
        (thread) => thread.copyWith(
          conversation: thread.conversation.copyWith(
            status: ChatConversationStatus.resolved,
            preview: 'Conversation resolved',
            time: 'Now',
          ),
          messages: [
            ...thread.messages,
            ConversationMessage(
              id: 'system-${DateTime.now().microsecondsSinceEpoch}',
              sender: MessageSender.system,
              sentAt: DateTime.now(),
              content: const SystemMessageContent(
                'Conversation resolved',
                emphasized: true,
              ),
            ),
          ],
        ),
      );

  void reopen(String conversationId) => _update(
        conversationId,
        (thread) => thread.copyWith(
          conversation: thread.conversation.copyWith(
            status: ChatConversationStatus.open,
            preview: 'Conversation reopened',
            time: 'Now',
          ),
        ),
      );

  void loadOlderMessages(String conversationId) {
    final thread = findById(conversationId);
    if (thread == null ||
        !thread.hasOlderMessages ||
        thread.isLoadingOlderMessages) {
      return;
    }
    _update(
        conversationId, (item) => item.copyWith(isLoadingOlderMessages: true));
    _update(
        conversationId, (item) => item.copyWith(isLoadingOlderMessages: false));
  }

  List<MessageReaction> _toggleReaction(
    ConversationMessage message,
    String emoji,
  ) {
    final existing = message.reactions.where((item) => item.emoji == emoji);
    if (existing.isEmpty) {
      return [
        ...message.reactions,
        MessageReaction(emoji: emoji, reactedByAgent: true),
      ];
    }
    final reaction = existing.first;
    if (reaction.reactedByAgent) {
      if (reaction.count <= 1) {
        return message.reactions.where((item) => item.emoji != emoji).toList();
      }
      return [
        for (final item in message.reactions)
          if (item.emoji == emoji)
            item.copyWith(count: item.count - 1, reactedByAgent: false)
          else
            item,
      ];
    }
    return [
      for (final item in message.reactions)
        if (item.emoji == emoji)
          item.copyWith(count: item.count + 1, reactedByAgent: true)
        else
          item,
    ];
  }

  void _update(
    String conversationId,
    ConversationThread Function(ConversationThread thread) transform,
  ) {
    state = [
      for (final thread in state)
        if (thread.conversation.id == conversationId)
          transform(thread)
        else
          thread,
    ];
  }
}

@riverpod
ConversationThread? conversationThread(Ref ref, String conversationId) {
  final threads = ref.watch(conversationStoreProvider);
  for (final thread in threads) {
    if (thread.conversation.id == conversationId) return thread;
  }
  return null;
}

String conversationMessagePreview(ConversationMessageContent content) =>
    switch (content) {
      TextMessageContent(:final text) => text,
      ImageMessageContent(:final caption) => caption ?? 'Photo',
      VideoMessageContent(:final caption) => caption ?? 'Video',
      AudioMessageContent() => 'Voice message',
      DocumentMessageContent(:final fileName) => fileName,
      LocationMessageContent(:final title) => title,
      ContactMessageContent(:final name) => name,
      SystemMessageContent(:final text) => text,
      UnsupportedMessageContent(:final description) => description,
    };

final _today = DateTime(2026, 8, 29);

ConversationMessage _message(
  String id,
  MessageSender sender,
  int hour,
  int minute,
  ConversationMessageContent content, {
  MessageDelivery delivery = MessageDelivery.none,
  String? replyToId,
  List<MessageReaction> reactions = const [],
}) =>
    ConversationMessage(
      id: id,
      sender: sender,
      sentAt: _today.add(Duration(hours: hour, minutes: minute)),
      content: content,
      delivery: delivery,
      replyToId: replyToId,
      reactions: reactions,
    );

const _errorScreenshot = 'assets/demo/chat/error_screenshot.png';
const _schoolPhoto = 'assets/demo/chat/school_photo.png';
const _walkthroughVideo = 'assets/demo/chat/walkthrough.mp4';
const _voiceNote = 'assets/demo/chat/voice_note.m4a';
const _feeSchedule = 'assets/demo/chat/fees_schedule.pdf';
const _mapPreview = 'assets/demo/chat/map_preview.png';

final _initialThreads = <ConversationThread>[
  ConversationThread(
    conversation: const ChatConversation(
      id: 'aloise-whatsapp',
      channel: ChatChannel.whatsapp,
      type: ChatConversationType.dms,
      status: ChatConversationStatus.open,
      name: 'Aloise Obaga Kaizen School',
      preview: 'The school is here',
      time: '13:58',
      avatar: 'A',
      customerId: 'aloise-obaga',
      contactIdentifier: '+254723506031',
      unreadCount: 1,
      ticketId: 'DGKSL-103',
    ),
    summary: 'Technical support — student results submission',
    hasOlderMessages: true,
    messages: [
      _message(
          'aloise-0',
          MessageSender.customer,
          10,
          58,
          const UnsupportedMessageContent(
              'An older message type is not supported on this device.')),
      _message(
          'aloise-1',
          MessageSender.customer,
          11,
          27,
          const TextMessageContent(
              'Hi Hillary, I am having trouble submitting the student results.')),
      _message('aloise-2', MessageSender.customer, 11, 28,
          const TextMessageContent('It keeps showing this error.')),
      _message(
          'aloise-3',
          MessageSender.customer,
          11,
          28,
          const ImageMessageContent(
              assetPath: _errorScreenshot,
              caption: 'This is what I see when I press Submit Results.',
              width: 720,
              height: 960)),
      _message(
          'aloise-4',
          MessageSender.agent,
          11,
          32,
          const TextMessageContent(
              'I can see the validation issue. Let me check the required fields.'),
          delivery: MessageDelivery.read,
          replyToId: 'aloise-3'),
      _message(
          'aloise-5',
          MessageSender.customer,
          11,
          35,
          const AudioMessageContent(
              assetPath: _voiceNote,
              duration: Duration(seconds: 8),
              waveform: [
                .18,
                .42,
                .68,
                .31,
                .82,
                .54,
                .26,
                .72,
                .91,
                .48,
                .36,
                .64,
                .22,
                .76,
                .58,
                .33,
                .67,
                .29
              ])),
      _message(
          'aloise-6',
          MessageSender.agent,
          11,
          41,
          const TextMessageContent(
              'Thanks. Select the class, term and subject again, then retry from the results list.'),
          delivery: MessageDelivery.delivered),
      _message(
          'aloise-7',
          MessageSender.agent,
          11,
          43,
          const VideoMessageContent(
              assetPath: _walkthroughVideo,
              thumbnailAssetPath: _schoolPhoto,
              duration: Duration(seconds: 8),
              caption: 'Here is a quick walkthrough of the corrected flow.'),
          delivery: MessageDelivery.read),
      _message('aloise-8', MessageSender.customer, 11, 51,
          const TextMessageContent('That worked. Thank you 👍'),
          reactions: const [MessageReaction(emoji: '❤️')]),
      _message(
          'aloise-system-1',
          MessageSender.system,
          11,
          52,
          const SystemMessageContent('Ticket DGKSL-103 updated',
              emphasized: true)),
      _message('aloise-9', MessageSender.customer, 13, 20,
          const TextMessageContent('Can you also send me the fee schedule?')),
      _message(
          'aloise-10',
          MessageSender.agent,
          13,
          23,
          const DocumentMessageContent(
              assetPath: _feeSchedule,
              fileName: 'Fees_Schedule.pdf',
              mimeType: 'PDF',
              sizeLabel: '4 KB'),
          delivery: MessageDelivery.read,
          replyToId: 'aloise-9'),
      _message('aloise-11', MessageSender.customer, 13, 30,
          const TextMessageContent('Received, thank you.')),
      _message(
          'aloise-12',
          MessageSender.customer,
          13,
          55,
          const ImageMessageContent(
              assetPath: _schoolPhoto,
              caption: 'This is our main courtyard.',
              width: 960,
              height: 720)),
      _message(
          'aloise-13',
          MessageSender.customer,
          13,
          56,
          const LocationMessageContent(
              title: 'Kaizen School',
              subtitle: 'Nairobi',
              previewAssetPath: _mapPreview,
              latitude: -1.286389,
              longitude: 36.817223)),
      _message(
          'aloise-14',
          MessageSender.customer,
          13,
          57,
          const ContactMessageContent(
              name: 'John Kamau', phone: '+254 720 000 000', avatar: 'J')),
      _message(
          'aloise-15',
          MessageSender.agent,
          13,
          58,
          const TextMessageContent(
              'Got it. I have added the location to the case.'),
          delivery: MessageDelivery.failed),
      _message('aloise-system-2', MessageSender.system, 13, 59,
          const SystemMessageContent('Satisfaction survey sent')),
    ],
  ),
  ..._secondaryThreads,
];

final _secondaryThreads = <ConversationThread>[
  _thread('bettie-whatsapp', ChatChannel.whatsapp, 'Bettie SSP Main', 'B',
      'Ticket marked as resolved', '16:22', ChatConversationStatus.resolved,
      ticketId: 'DGKSL-208', phone: '+254700288997', unread: 1),
  _thread('wika-whatsapp', ChatChannel.whatsapp, 'Wika School', 'W',
      'Rated: Good (5/5)', '08:13', ChatConversationStatus.open,
      ticketId: 'DGKSL-287', type: ChatConversationType.groups, unread: 1),
  _thread('kirawa-whatsapp', ChatChannel.whatsapp, 'kirawafinance', 'K',
      'Ticket marked as resolved', '14:35', ChatConversationStatus.resolved),
  _thread(
      'david-widget',
      ChatChannel.widgetChat,
      'David',
      'D',
      'Trying to send results and fees notification...',
      '09:09',
      ChatConversationStatus.open,
      ticketId: 'DGKSL-223',
      phone: 'davidleleito039@gmail.com',
      unread: 4),
  _thread('phyllis-widget', ChatChannel.widgetChat, 'Phyllis', 'P',
      'How do I create a payroll?', '11:14', ChatConversationStatus.resolved,
      ticketId: 'DGKSL-220'),
  _thread(
      'otieno-widget',
      ChatChannel.widgetChat,
      'otieno',
      'O',
      'Who uploads marks for teachers?',
      '23:44',
      ChatConversationStatus.resolved,
      phone: 'sullyvan83@gmail.com',
      customerId: 'otieno'),
  _thread(
      'amos-widget',
      ChatChannel.widgetChat,
      'amos',
      'A',
      'How do I enable the new changes?',
      '11:31',
      ChatConversationStatus.resolved,
      type: ChatConversationType.groups),
];

ConversationThread _thread(
  String id,
  ChatChannel channel,
  String name,
  String avatar,
  String preview,
  String time,
  ChatConversationStatus status, {
  String? ticketId,
  String? phone,
  String? customerId,
  int unread = 0,
  ChatConversationType type = ChatConversationType.dms,
}) =>
    ConversationThread(
      conversation: ChatConversation(
        id: id,
        channel: channel,
        type: type,
        status: status,
        name: name,
        preview: preview,
        time: time,
        avatar: avatar,
        customerId: customerId,
        contactIdentifier: phone,
        unreadCount: unread,
        ticketId: ticketId,
      ),
      summary: preview,
      messages: [
        _message('$id-1', MessageSender.customer, 11, 14,
            TextMessageContent(preview)),
      ],
    );
