import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../conversation_room_page/conversation_room_page_model.dart';

export '../conversation_room_page/conversation_room_page_model.dart';

part 'chats_page_model.g.dart';

class ChatsPageState {
  const ChatsPageState({
    this.channel = ChatChannel.whatsapp,
    this.type = ChatConversationType.all,
    this.status = ChatConversationStatus.all,
    this.searchActive = false,
    this.query = '',
  });

  final ChatChannel channel;
  final ChatConversationType type;
  final ChatConversationStatus status;
  final bool searchActive;
  final String query;

  String get subtitle => channel == ChatChannel.whatsapp
      ? '74 conversations · 3 unread'
      : '1 open · 73 resolved';

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
      );
}

class ChatFilterSelection {
  const ChatFilterSelection({required this.type, required this.status});

  final ChatConversationType type;
  final ChatConversationStatus status;
}

List<ChatConversation> filterChatConversations(
  Iterable<ChatConversation> conversations,
  ChatsPageState state,
) {
  final query = state.query.trim().toLowerCase();
  return conversations.where((conversation) {
    if (conversation.channel != state.channel) return false;
    if (state.type != ChatConversationType.all &&
        conversation.type != state.type) {
      return false;
    }
    if (state.status != ChatConversationStatus.all &&
        conversation.status != state.status) {
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
