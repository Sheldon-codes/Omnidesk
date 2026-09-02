import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import 'conversation_room_page_model.dart';

class WhatsAppInboxState {
  const WhatsAppInboxState({
    this.threads = const [],
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.page = 0,
    this.lastPage = 1,
    this.total = 0,
    this.query = '',
    this.status = ChatConversationStatus.all,
  });

  final List<ConversationThread> threads;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final Object? error;
  final int page;
  final int lastPage;
  final int total;
  final String query;
  final ChatConversationStatus status;
  bool get hasMore => page < lastPage;
  bool get isOffline =>
      error is ApiClientException &&
      (error as ApiClientException).isNetworkError;

  WhatsAppInboxState copyWith({
    List<ConversationThread>? threads,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
    int? page,
    int? lastPage,
    int? total,
    String? query,
    ChatConversationStatus? status,
  }) =>
      WhatsAppInboxState(
        threads: threads ?? this.threads,
        loading: loading ?? this.loading,
        refreshing: refreshing ?? this.refreshing,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
        page: page ?? this.page,
        lastPage: lastPage ?? this.lastPage,
        total: total ?? this.total,
        query: query ?? this.query,
        status: status ?? this.status,
      );
}

class WhatsAppThreadState {
  const WhatsAppThreadState({
    this.thread,
    this.loading = false,
    this.sending = false,
    this.error,
  });
  final ConversationThread? thread;
  final bool loading;
  final bool sending;
  final Object? error;
}

class WhatsAppTemplate {
  const WhatsAppTemplate(
      {required this.id,
      required this.title,
      required this.body,
      this.shortcut});
  final String id;
  final String title;
  final String body;
  final String? shortcut;
}

class WhatsAppRepository {
  WhatsAppRepository(this._api);
  final ApiService _api;

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : <String, dynamic>{};

  Future<
      ({
        List<ConversationThread> threads,
        int page,
        int lastPage,
        int total
      })> inbox({
    required ChatConversationStatus status,
    required String query,
    required int page,
  }) async {
    final response = await _api.get('/tickets', queryParameters: {
      'source': 'whatsapp',
      'assigned': 'me',
      'page': page,
      'per_page': 20,
      if (status == ChatConversationStatus.open) 'status': 'open_all',
      if (status == ChatConversationStatus.resolved) 'status': 'closed_all',
      if (query.trim().isNotEmpty) 'search': query.trim(),
    });
    final root = _map(response);
    final meta = _map(root['meta']);
    final data = root['data'];
    return (
      threads: data is List
          ? data.whereType<Map>().map((item) => _summary(_map(item))).toList()
          : const <ConversationThread>[],
      page: (meta['current_page'] as num?)?.toInt() ?? page,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? 1,
      total: (meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<ConversationThread> thread(String id) async {
    final ticketResponse = _map(await _api.get('/tickets/$id'));
    final ticket = _map(ticketResponse['ticket']).isEmpty
        ? ticketResponse
        : _map(ticketResponse['ticket']);
    final timelineResponse = _map(await _api.get('/tickets/$id/timeline'));
    final summary = _summary(ticket);
    final timeline = timelineResponse['timeline'];
    final messages = timeline is List
        ? timeline.whereType<Map>().map((item) => _message(_map(item))).toList()
        : const <ConversationMessage>[];
    return summary.copyWith(messages: messages);
  }

  Future<List<ConversationMessage>> newer(String id, int sinceId) async {
    final response = _map(await _api
        .get('/tickets/$id/timeline', queryParameters: {'since_id': sinceId}));
    final timeline = response['timeline'];
    return timeline is List
        ? timeline.whereType<Map>().map((item) => _message(_map(item))).toList()
        : const [];
  }

  Future<void> markRead(String id) => _api.post('/tickets/$id/mark-read', {});
  Future<void> typing(String id) =>
      _api.post('/tickets/$id/typing', {'typing': true});
  Future<void> status(String id, String status,
          {String? reason, String? pendingReason}) =>
      _api.post('/tickets/$id/status', {
        'status': status,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (pendingReason != null && pendingReason.trim().isNotEmpty)
          'pending_reason': pendingReason.trim(),
      });

  Future<void> send(String id,
      {required String? message, String? replyToId, File? attachment}) async {
    final body = <String, dynamic>{
      'channel': 'whatsapp',
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
      if (replyToId != null) 'reply_to_message_id': int.tryParse(replyToId),
    };
    if (attachment != null) {
      body['media_data'] = base64Encode(await attachment.readAsBytes());
      body['media_type'] = _mimeType(attachment.path);
      body['media_filename'] = attachment.uri.pathSegments.last;
    }
    await _api.post('/tickets/$id/reply', body);
  }

  Future<List<WhatsAppTemplate>> templates() async {
    final root = _map(await _api.get('/tickets/response-templates'));
    final values = root['templates'];
    return values is List
        ? values.whereType<Map>().map((item) {
            final value = _map(item);
            return WhatsAppTemplate(
                id: value['id'].toString(),
                title: (value['title'] ?? '').toString(),
                body: (value['body'] ?? '').toString(),
                shortcut: value['shortcut']?.toString());
          }).toList()
        : const [];
  }

  ConversationThread _summary(Map<String, dynamic> value) {
    final customer = _map(value['customer']);
    final rawStatus = value['status']?.toString() ?? 'open';
    final customerName = (customer['name'] ?? 'Customer').toString();
    final updated = DateTime.tryParse(
            (value['updated_at'] ?? value['created_at'] ?? '').toString()) ??
        DateTime.now();
    final conversation = ChatConversation(
      id: value['id'].toString(),
      channel: ChatChannel.whatsapp,
      type: (value['subject']?.toString().toLowerCase().contains('group') ??
              false)
          ? ChatConversationType.groups
          : ChatConversationType.dms,
      status: rawStatus == 'resolved' || rawStatus == 'closed'
          ? ChatConversationStatus.resolved
          : ChatConversationStatus.open,
      name: customerName,
      preview: (value['subject'] ?? 'No messages yet').toString(),
      time: DateFormat.Hm().format(updated.toLocal()),
      avatar: customerName.isEmpty ? null : customerName[0].toUpperCase(),
      customerId: customer['id']?.toString(),
      contactIdentifier: customer['phone_number']?.toString(),
      unreadCount: value['unread_count'] is num
          ? (value['unread_count'] as num).toInt()
          : 0,
      ticketId: (value['display_number'] ?? value['display_id'])?.toString(),
    );
    return ConversationThread(
        conversation: conversation,
        messages: const [],
        summary: (value['description'] ?? value['category'] ?? '').toString());
  }

  ConversationMessage _message(Map<String, dynamic> value) {
    final fromCustomer = value['is_from_customer'] == true;
    final type = (value['media_type'] ?? '').toString().toLowerCase();
    final url = value['media_url']?.toString();
    final text = (value['description'] ?? '').toString();
    final content = url == null || url.isEmpty
        ? text.isEmpty
            ? const UnsupportedMessageContent(
                'Message content is unavailable. The server did not provide an attachment reference.',
              )
            : TextMessageContent(text)
        : type.startsWith('image/')
            ? ImageMessageContent(
                assetPath: url, caption: text.isEmpty ? null : text)
            : type.startsWith('video/')
                ? VideoMessageContent(
                    assetPath: url,
                    thumbnailAssetPath: url,
                    duration: Duration.zero,
                    caption: text.isEmpty ? null : text)
                : type.startsWith('audio/')
                    ? AudioMessageContent(
                        assetPath: url,
                        duration: Duration.zero,
                        waveform: const [.25, .5, .7, .45, .6, .3])
                    : DocumentMessageContent(
                        assetPath: url,
                        fileName: (value['media_filename'] ?? 'Attachment')
                            .toString(),
                        mimeType: type.isEmpty ? 'file' : type,
                        sizeLabel: 'Attachment');
    return ConversationMessage(
      id: value['id'].toString(),
      sender: value['event_type'] == 'note'
          ? MessageSender.system
          : (fromCustomer ? MessageSender.customer : MessageSender.agent),
      sentAt: DateTime.tryParse((value['created_at'] ?? '').toString()) ??
          DateTime.now(),
      content:
          value['event_type'] == 'note' ? SystemMessageContent(text) : content,
      delivery: fromCustomer ? MessageDelivery.none : MessageDelivery.sent,
    );
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    return 'application/octet-stream';
  }
}

final whatsAppRepositoryProvider = Provider<WhatsAppRepository>(
    (ref) => WhatsAppRepository(ref.read(apiServiceProvider)));

final whatsAppInboxProvider =
    NotifierProvider<WhatsAppInboxController, WhatsAppInboxState>(
        WhatsAppInboxController.new);

class WhatsAppInboxController extends Notifier<WhatsAppInboxState> {
  int _request = 0;
  @override
  WhatsAppInboxState build() => const WhatsAppInboxState();
  Future<void> load(
      {ChatConversationStatus status = ChatConversationStatus.all,
      String query = ''}) async {
    final request = ++_request;
    state = state.copyWith(
        loading: state.threads.isEmpty,
        refreshing: state.threads.isNotEmpty,
        clearError: true,
        query: query,
        status: status);
    try {
      final result = await ref
          .read(whatsAppRepositoryProvider)
          .inbox(status: status, query: query, page: 1);
      if (request != _request) return;
      state = WhatsAppInboxState(
          threads: result.threads,
          page: result.page,
          lastPage: result.lastPage,
          total: result.total,
          query: query,
          status: status);
    } catch (error) {
      if (request != _request) return;
      state = state.copyWith(loading: false, refreshing: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final result = await ref.read(whatsAppRepositoryProvider).inbox(
          status: state.status, query: state.query, page: state.page + 1);
      final merged = <String, ConversationThread>{
        for (final item in state.threads) item.conversation.id: item,
        for (final item in result.threads) item.conversation.id: item
      };
      state = state.copyWith(
          threads: merged.values.toList(),
          page: result.page,
          lastPage: result.lastPage,
          total: result.total,
          loadingMore: false);
    } catch (error) {
      state = state.copyWith(loadingMore: false, error: error);
    }
  }
}

final whatsAppThreadsProvider = NotifierProvider<WhatsAppThreadController,
    Map<String, WhatsAppThreadState>>(WhatsAppThreadController.new);

class WhatsAppThreadController
    extends Notifier<Map<String, WhatsAppThreadState>> {
  final _timers = <String, Timer>{};
  final _polling = <String>{};
  @override
  Map<String, WhatsAppThreadState> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
    });
    return {};
  }

  WhatsAppThreadState? byId(String id) => state[id];
  Future<void> load(String id) async {
    final previous = state[id];
    state = {
      ...state,
      id: WhatsAppThreadState(
        thread: previous?.thread,
        loading: true,
        sending: previous?.sending ?? false,
      ),
    };
    try {
      final thread = await ref.read(whatsAppRepositoryProvider).thread(id);
      state = {
        ...state,
        id: WhatsAppThreadState(
            thread: thread, sending: previous?.sending ?? false),
      };
      unawaited(ref.read(whatsAppRepositoryProvider).markRead(id));
    } catch (error) {
      state = {
        ...state,
        id: WhatsAppThreadState(
          thread: previous?.thread,
          sending: previous?.sending ?? false,
          error: error,
        ),
      };
    }
  }

  void startPolling(String id) {
    if (_timers.containsKey(id)) return;
    _timers[id] = Timer.periodic(const Duration(seconds: 4), (_) => _poll(id));
  }

  void stopPolling(String id) {
    _timers.remove(id)?.cancel();
  }

  Future<void> _poll(String id) async {
    if (!_polling.add(id)) return;
    try {
      final thread = state[id]?.thread;
      if (thread == null ||
          thread.conversation.status == ChatConversationStatus.resolved) {
        stopPolling(id);
        return;
      }
      final last = thread.messages.fold<int>(0, (max, item) {
        final value = int.tryParse(item.id) ?? 0;
        return value > max ? value : max;
      });
      if (last == 0) return;
      final newer = await ref.read(whatsAppRepositoryProvider).newer(id, last);
      final existing = state[id]?.thread;
      if (newer.isEmpty || existing == null) return;
      final knownIds = existing.messages.map((item) => item.id).toSet();
      final appended = newer.where((item) => knownIds.add(item.id)).toList();
      if (appended.isNotEmpty) {
        state = {
          ...state,
          id: WhatsAppThreadState(
            thread: existing
                .copyWith(messages: [...existing.messages, ...appended]),
          ),
        };
      }
    } catch (_) {
      // Polling is best effort. The visible room retains its last confirmed state.
    } finally {
      _polling.remove(id);
    }
  }

  Future<void> send(
    String id,
    String text, {
    String? replyToId,
    File? attachment,
  }) async {
    final previous = state[id];
    state = {
      ...state,
      id: WhatsAppThreadState(
        thread: previous?.thread,
        sending: true,
      ),
    };
    try {
      await ref.read(whatsAppRepositoryProvider).send(
            id,
            message: text,
            replyToId: replyToId,
            attachment: attachment,
          );
      await load(id);
    } finally {
      final refreshed = state[id];
      state = {
        ...state,
        id: WhatsAppThreadState(
          thread: refreshed?.thread,
          error: refreshed?.error,
        ),
      };
    }
  }

  Future<void> status(String id, String value) async {
    await ref.read(whatsAppRepositoryProvider).status(id, value);
    await load(id);
  }

  Future<List<WhatsAppTemplate>> templates() =>
      ref.read(whatsAppRepositoryProvider).templates();
}
