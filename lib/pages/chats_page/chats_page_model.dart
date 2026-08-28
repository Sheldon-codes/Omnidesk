import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chats_page_model.g.dart';

enum ChatChannel { whatsapp, liveChat }

enum ChatConversationType { all, dms, groups }

enum ChatConversationStatus { all, open, resolved }

class ChatConversation {
  const ChatConversation({
    required this.channel,
    required this.type,
    required this.status,
    required this.name,
    required this.preview,
    required this.time,
    this.avatar,
    this.contactIdentifier,
    this.unreadCount = 0,
    this.ticketId,
  });

  final ChatChannel channel;
  final ChatConversationType type;
  final ChatConversationStatus status;
  final String name;
  final String preview;
  final String time;
  final String? avatar;
  final String? contactIdentifier;
  final int unreadCount;
  final String? ticketId;

  String get initials =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

class ChatsPageState {
  const ChatsPageState({
    this.channel = ChatChannel.whatsapp,
    this.type = ChatConversationType.all,
    this.status = ChatConversationStatus.all,
    this.searchActive = false,
    this.query = '',
    this.conversations = _defaultConversations,
  });

  final ChatChannel channel;
  final ChatConversationType type;
  final ChatConversationStatus status;
  final bool searchActive;
  final String query;
  final List<ChatConversation> conversations;

  String get subtitle => channel == ChatChannel.whatsapp
      ? '74 conversations · 3 unread'
      : '1 open · 73 resolved';

  List<ChatConversation> get filteredConversations {
    final query = this.query.trim().toLowerCase();
    return conversations.where((conversation) {
      if (conversation.channel != channel) return false;
      if (type != ChatConversationType.all && conversation.type != type) {
        return false;
      }
      if (status != ChatConversationStatus.all &&
          conversation.status != status) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        conversation.name,
        conversation.preview,
        conversation.contactIdentifier ?? '',
        conversation.ticketId ?? '',
      ].any((value) => value.toLowerCase().contains(query));
    }).toList(growable: false);
  }

  ChatFilterSelection get filterSelection => ChatFilterSelection(
        type: type,
        status: status,
      );

  ChatsPageState copyWith({
    ChatChannel? channel,
    ChatConversationType? type,
    ChatConversationStatus? status,
    bool? searchActive,
    String? query,
  }) =>
      ChatsPageState(
        channel: channel ?? this.channel,
        type: type ?? this.type,
        status: status ?? this.status,
        searchActive: searchActive ?? this.searchActive,
        query: query ?? this.query,
        conversations: conversations,
      );
}

class ChatFilterSelection {
  const ChatFilterSelection({required this.type, required this.status});

  final ChatConversationType type;
  final ChatConversationStatus status;
}

const _defaultConversations = <ChatConversation>[
  ChatConversation(
    channel: ChatChannel.whatsapp,
    type: ChatConversationType.dms,
    status: ChatConversationStatus.resolved,
    name: 'kirawafinance',
    preview: 'Ticket marked as resolved. The error in school fees…',
    time: '14:35',
    avatar: 'K',
    contactIdentifier: '+254722000111',
  ),
  ChatConversation(
    channel: ChatChannel.whatsapp,
    type: ChatConversationType.groups,
    status: ChatConversationStatus.open,
    name: 'Wika School',
    preview: 'Rated: Good (5/5) ⭐⭐⭐⭐⭐',
    time: '08:13',
    unreadCount: 1,
    contactIdentifier: '+254733000222',
  ),
  ChatConversation(
    channel: ChatChannel.whatsapp,
    type: ChatConversationType.dms,
    status: ChatConversationStatus.open,
    name: 'Bettie SSP Main',
    preview: 'Rated: Good (5/5) ⭐⭐⭐⭐⭐',
    time: '16:22',
    unreadCount: 1,
    contactIdentifier: '+254744000333',
  ),
  ChatConversation(
    channel: ChatChannel.whatsapp,
    type: ChatConversationType.dms,
    status: ChatConversationStatus.resolved,
    name: 'Paul Obengo Sunshine',
    preview: 'Ticket marked as resolved. Resolved',
    time: '16:20',
    contactIdentifier: '+254755000444',
  ),
  ChatConversation(
    channel: ChatChannel.whatsapp,
    type: ChatConversationType.groups,
    status: ChatConversationStatus.open,
    name: 'Nancy Betterstream',
    preview: '📊 Satisfaction survey sent (Good/Average…',
    time: '14:54',
    unreadCount: 1,
    ticketId: 'DGKSL-103',
    contactIdentifier: '+254766000555',
  ),
  ChatConversation(
    channel: ChatChannel.liveChat,
    type: ChatConversationType.dms,
    status: ChatConversationStatus.open,
    name: 'Phyllis',
    preview: 'How do I create a payroll',
    time: '11:14',
    unreadCount: 1,
    contactIdentifier: 'phyllis@example.com',
  ),
  ChatConversation(
    channel: ChatChannel.liveChat,
    type: ChatConversationType.dms,
    status: ChatConversationStatus.resolved,
    name: 'otieno',
    preview: 'who does the upload marks on teachers, i…',
    time: '23:44',
    contactIdentifier: 'otieno@example.com',
  ),
  ChatConversation(
    channel: ChatChannel.liveChat,
    type: ChatConversationType.dms,
    status: ChatConversationStatus.open,
    name: 'David',
    preview: 'Trying to send results and fees notification…',
    time: '09:09',
    unreadCount: 4,
    ticketId: 'DGKSL-223',
    contactIdentifier: 'david@example.com',
  ),
  ChatConversation(
    channel: ChatChannel.liveChat,
    type: ChatConversationType.dms,
    status: ChatConversationStatus.resolved,
    name: 'amos',
    preview: 'HOW TO ENSURE THE NEW CHANGES IN…',
    time: '11:31',
    contactIdentifier: 'amos@example.com',
  ),
];

@riverpod
class ChatsPageNotifier extends _$ChatsPageNotifier {
  @override
  ChatsPageState build() => const ChatsPageState();

  void selectChannel(ChatChannel channel) {
    state = state.copyWith(
      channel: channel,
      type: ChatConversationType.all,
      status: ChatConversationStatus.all,
      searchActive: false,
      query: '',
    );
  }

  void openSearch() => state = state.copyWith(searchActive: true);

  void closeSearch() => state = state.copyWith(searchActive: false, query: '');

  void setSearchQuery(String value) => state = state.copyWith(query: value);

  void applyFilters({
    required ChatConversationType type,
    required ChatConversationStatus status,
  }) =>
      state = state.copyWith(type: type, status: status);

  void clearFilters() => applyFilters(
        type: ChatConversationType.all,
        status: ChatConversationStatus.all,
      );
}
