import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/auth_session_controller.dart';
import '../../services/realtime/realtime_event.dart';
import '../../services/realtime/realtime_service.dart';
import '../../services/realtime/whatsapp_message_mapper.dart';
import '../../services/realtime/whatsapp_outbox.dart';
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
    this.live = false,
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
  final bool live;
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
    bool? live,
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
        live: live ?? this.live,
      );
}

class WhatsAppThreadState {
  const WhatsAppThreadState({
    this.thread,
    this.loading = false,
    this.sending = false,
    this.error,
    this.live = false,
    this.degraded = false,
  });
  final ConversationThread? thread;
  final bool loading;
  final bool sending;
  final Object? error;
  final bool live;
  final bool degraded;
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

class GroupChatAgent {
  const GroupChatAgent({
    required this.id,
    required this.name,
    this.email,
    this.isPrimary = false,
  });
  final String id;
  final String name;
  final String? email;
  final bool isPrimary;
}

class GroupAgentsUnsupported implements Exception {
  const GroupAgentsUnsupported();
  @override
  String toString() => 'Group agent management is not available on this server.';
}

class WhatsAppRepository {
  WhatsAppRepository(this._api) : _mapper = const WhatsAppMessageMapper();
  final ApiService _api;
  final WhatsAppMessageMapper _mapper;

  static const maxMediaBytes = 15 * 1024 * 1024;

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
          ? data
              .whereType<Map>()
              .map((item) => _mapper.summaryToThread(_map(item)))
              .toList()
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
    final summary = _mapper.summaryToThread(ticket);
    final timeline = timelineResponse['timeline'];
    final messages = timeline is List
        ? timeline
            .whereType<Map>()
            .map((item) => _mapper.fromTimeline(_map(item)))
            .toList()
        : const <ConversationMessage>[];
    final preview = messages.isNotEmpty
        ? conversationMessagePreview(messages.last.content)
        : summary.conversation.preview;
    final time = messages.isNotEmpty
        ? DateFormat.Hm().format(messages.last.sentAt.toLocal())
        : summary.conversation.time;
    return summary.copyWith(
      messages: messages,
      conversation: summary.conversation.copyWith(preview: preview, time: time),
    );
  }

  Future<List<ConversationMessage>> newer(String id, int sinceId) async {
    final response = _map(await _api
        .get('/tickets/$id/timeline', queryParameters: {'since_id': sinceId}));
    final timeline = response['timeline'];
    return timeline is List
        ? timeline
            .whereType<Map>()
            .map((item) => _mapper.fromTimeline(_map(item)))
            .toList()
        : const [];
  }

  Future<void> markRead(String id) => _api.post('/tickets/$id/mark-read', {});
  Future<void> typing(String id, {bool isTyping = true}) =>
      _api.post('/tickets/$id/typing', {'typing': isTyping});
  Future<void> status(String id, String status,
          {String? reason, String? pendingReason}) =>
      _api.post('/tickets/$id/status', {
        'status': status,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (pendingReason != null && pendingReason.trim().isNotEmpty)
          'pending_reason': pendingReason.trim(),
      });

  /// Sends a reply. Returns the created timeline id when the backend echoes
  /// one, otherwise null (caller falls back to `since_id` refetch).
  Future<String?> send(
    String id, {
    required String? message,
    String? replyToId,
    File? attachment,
    int? durationSecs,
    void Function(int sent, int total)? onProgress,
  }) async {
    final body = <String, dynamic>{
      'channel': 'whatsapp',
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
      if (replyToId != null) 'reply_to_message_id': int.tryParse(replyToId),
      if (durationSecs != null) 'duration': durationSecs,
    };
    if (attachment != null) {
      final bytes = await attachment.readAsBytes();
      if (bytes.lengthInBytes > maxMediaBytes) {
        throw const ApiClientException(
            message:
                'Attachment is larger than 15 MB. Choose a smaller file.');
      }
      body['media_data'] = base64Encode(bytes);
      body['media_type'] = _mimeType(attachment.path);
      body['media_filename'] = attachment.uri.pathSegments.last;
    }
    if ((body['message'] == null) && !body.containsKey('media_data')) {
      throw const ApiClientException(message: 'Message or media required');
    }
    final response = _map(await _api.postWithProgress(
      '/tickets/$id/reply',
      body,
      onSendProgress: onProgress,
    ));
    final entry = _map(response['entry']);
    if (entry.isEmpty) {
      final fallback = _map(response['timeline_entry']);
      if (fallback.isEmpty) return null;
      return '${fallback['id'] ?? ''}'.isEmpty
          ? null
          : '${fallback['id']}';
    }
    return '${entry['id'] ?? ''}'.isEmpty ? null : '${entry['id']}';
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

  Future<List<GroupChatAgent>> groupAgents(String ticketId) async {
    try {
      final root = _map(await _api.get('/tickets/group-agents',
          queryParameters: {'ticket_id': ticketId}));
      final values = root['agents'];
      if (values is! List) return const [];
      return values.whereType<Map>().map((item) {
        final v = _map(item);
        return GroupChatAgent(
          id: '${v['id']}',
          name: '${v['name'] ?? 'Agent'}',
          email: v['email']?.toString(),
          isPrimary: v['is_primary'] == true,
        );
      }).toList();
    } on ApiClientException catch (e) {
      if (e.statusCode == 404) throw const GroupAgentsUnsupported();
      rethrow;
    }
  }

  Future<void> addGroupAgent(String ticketId, String userId) async {
    try {
      await _api.post('/tickets/group-agents',
          {'ticket_id': int.tryParse(ticketId) ?? ticketId, 'user_id': userId});
    } on ApiClientException catch (e) {
      if (e.statusCode == 404) throw const GroupAgentsUnsupported();
      rethrow;
    }
  }

  Future<void> removeGroupAgent(String ticketId, String userId) async {
    try {
      await _api.delete('/tickets/group-agents',
          body: {
            'ticket_id': int.tryParse(ticketId) ?? ticketId,
            'user_id': userId
          });
    } on ApiClientException catch (e) {
      if (e.statusCode == 404) throw const GroupAgentsUnsupported();
      rethrow;
    }
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.ogg') || lower.endsWith('.opus')) {
      return 'audio/ogg; codecs=opus';
    }
    if (lower.endsWith('.m4a')) return 'audio/mp4';
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
  StreamSubscription<RealtimeEvent>? _events;
  bool _watching = false;

  @override
  WhatsAppInboxState build() {
    ref.onDispose(() => unawaited(_events?.cancel()));
    return const WhatsAppInboxState();
  }

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
          status: status,
          live: state.live);
      await startWatching();
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

  Future<void> startWatching() async {
    if (_watching) return;
    _watching = true;
    final service = ref.read(realtimeServiceProvider);
    if (!service.isEnabled) return;
    final tenantId = ref
        .read(authSessionControllerProvider)
        .session
        ?.user
        .activeWorkspace
        ?.id;
    await service.watchInbox(tenantId: tenantId);
    _events ??= service.events.listen(_onEvent);
    if (!ref.mounted) return;
    state = state.copyWith(live: true, clearError: true);
  }

  Future<void> stopWatching() async {
    _watching = false;
    await _events?.cancel();
    _events = null;
    try {
      final tenantId = ref
          .read(authSessionControllerProvider)
          .session
          ?.user
          .activeWorkspace
          ?.id;
      await ref.read(realtimeServiceProvider).unwatchInbox(tenantId: tenantId);
    } catch (_) {}
  }

  void _onEvent(RealtimeEvent event) {
    if (!ref.mounted) return;
    if (event is TicketMessageEvent) {
      _handleMessageHint(event);
    } else if (event is InboxUpdateEvent) {
      // No background refetch here: realtime hints only merge locally.
      // The inbox refreshes on explicit user action (open / pull-to-refresh).
      _mergeTicketRow(event.payload);
    }
  }

  void _handleMessageHint(TicketMessageEvent event) {
    final payload = event.payload;
    final ticketId = event.ticketId ??
        '${payload['ticket_id'] ?? payload['ticketId'] ?? ''}';
    if (ticketId.isEmpty) return;
    final index =
        state.threads.indexWhere((t) => t.conversation.id == ticketId);
    if (index < 0) return;
    final existing = state.threads[index];
    final description = _hintPreview(payload);
    final updated = existing.conversation.copyWith(
      preview: description ?? existing.conversation.preview,
      time: DateFormat.Hm().format(DateTime.now()),
      unreadCount: existing.conversation.unreadCount + 1,
    );
    final moved = ConversationThread(
        conversation: updated,
        messages: existing.messages,
        summary: existing.summary);
    final rest = List<ConversationThread>.of(state.threads)..removeAt(index);
    state = state.copyWith(threads: [moved, ...rest]);
  }

  String? _hintPreview(Map<String, dynamic> payload) {
    for (final key in [
      'description',
      'body',
      'preview',
      'subject',
      'latest_message'
    ]) {
      final v = payload[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map && '${v['body'] ?? ''}'.trim().isNotEmpty) {
        return '${v['body']}'.trim();
      }
    }
    if (payload['media_url'] != null) return 'Attachment';
    return null;
  }

  /// Merges a full ticket row from a realtime payload into the inbox.
  /// Returns silently when the payload is a thin hint (counts/stubs) so we
  /// never fire background list refetches off socket events.
  void _mergeTicketRow(Map<String, dynamic> payload) {
    final row = payload['ticket'] is Map
        ? Map<String, dynamic>.from(payload['ticket'] as Map)
        : payload;
    if (row['id'] == null || (row['customer'] is! Map && row['subject'] == null)) {
      return;
    }
    try {
      final incoming = const WhatsAppMessageMapper()
          .summaryToThread(row.map((k, v) => MapEntry(k.toString(), v)));
      final id = incoming.conversation.id;
      final threads = List<ConversationThread>.of(state.threads);
      final index = threads.indexWhere((t) => t.conversation.id == id);
      if (index < 0) {
        state = state.copyWith(
            threads: [incoming, ...threads], total: state.total + 1);
      } else {
        final existing = threads[index];
        threads.removeAt(index);
        threads.insert(
            0,
            ConversationThread(
                conversation: incoming.conversation,
                messages: existing.messages,
                summary: existing.summary));
        state = state.copyWith(threads: threads);
      }
    } catch (_) {
      // Malformed realtime payloads are ignored; explicit refresh recovers.
    }
  }

  void markLocalRead(String ticketId) {
    final threads = [
      for (final t in state.threads)
        if (t.conversation.id == ticketId)
          ConversationThread(
              conversation: t.conversation.copyWith(unreadCount: 0),
              messages: t.messages,
              summary: t.summary)
        else
          t
    ];
    state = state.copyWith(threads: threads);
  }
}

final whatsAppThreadsProvider = NotifierProvider<WhatsAppThreadController,
    Map<String, WhatsAppThreadState>>(WhatsAppThreadController.new);

class WhatsAppThreadController
    extends Notifier<Map<String, WhatsAppThreadState>> {
  final _polling = <String>{};
  final _realtimeSubs = <String, StreamSubscription<RealtimeEvent>>{};
  final _lastTypingAt = <String, DateTime>{};

  @override
  Map<String, WhatsAppThreadState> build() {
    ref.onDispose(() {
      for (final sub in _realtimeSubs.values) {
        unawaited(sub.cancel());
      }
    });
    return {};
  }

  WhatsAppThreadState? byId(String id) => state[id];

  void _set(String id, WhatsAppThreadState value) {
    state = {...state, id: value};
  }

  Future<void> load(String id) async {
    final previous = state[id];
    _set(id,
        WhatsAppThreadState(thread: previous?.thread, loading: true, sending: previous?.sending ?? false, live: previous?.live ?? false));
    try {
      final thread = await ref.read(whatsAppRepositoryProvider).thread(id);
      if (!ref.mounted) return;
      _set(id,
          WhatsAppThreadState(thread: thread, live: previous?.live ?? false));
      unawaited(_attachRealtime(id));
      unawaited(ref.read(whatsAppRepositoryProvider).markRead(id));
      ref.read(whatsAppInboxProvider.notifier).markLocalRead(id);
      unawaited(flushOutbox(id));
    } catch (error) {
      if (!ref.mounted) return;
      _set(id,
          WhatsAppThreadState(thread: previous?.thread, sending: previous?.sending ?? false, error: error));
    }
  }

  /// Room lifecycle hook: subscribes the ticket to realtime updates.
  /// There is no periodic polling — updates arrive over the socket and the
  /// timeline refreshes on explicit user action (open / send / retry).
  void startPolling(String id) {
    unawaited(_attachRealtime(id));
  }

  void stopPolling(String id) {
    unawaited(detachRealtime(id));
  }

  Future<void> detachRealtime(String id) async {
    await _realtimeSubs.remove(id)?.cancel();
    try {
      await ref.read(realtimeServiceProvider).unwatchTicket(id);
    } catch (_) {}
    if (!ref.mounted) return;
    final current = state[id];
    if (current == null) return;
    if (current.thread == null) {
      // Never leave a thread-less entry behind (e.g. popped mid-load):
      // it would read as a dead state on the next open.
      state = {...state}..remove(id);
      return;
    }
    _set(id,
        WhatsAppThreadState(thread: current.thread, sending: current.sending, error: current.error, live: false, degraded: true));
  }

  Future<void> _attachRealtime(String id) async {
    if (_realtimeSubs.containsKey(id)) return;
    final service = ref.read(realtimeServiceProvider);
    if (!service.isEnabled) return;
    await service.watchTicket(id);
    final sub = service.events.listen((event) => _onRealtime(id, event));
    _realtimeSubs[id] = sub;
    sub.onDone(() => _realtimeSubs.remove(id));
    if (!ref.mounted) return;
    final current = state[id];
    if (current != null) {
      _set(id,
          WhatsAppThreadState(thread: current.thread, sending: current.sending, error: current.error, live: true));
    }
  }

  Future<void> _onRealtime(String id, RealtimeEvent event) async {
    if (!ref.mounted) return;
    if (event is! TicketMessageEvent) return;
    if (event.ticketId != null && event.ticketId != id) return;
    // Full payload with a timeline row merges instantly; thin stubs trigger
    // a precise `since_id` fetch (no full reload).
    final payload = event.payload;
    final hasRow = payload['description'] is String ||
        payload['media_url'] is String ||
        payload['timeline_id'] != null;
    if (hasRow && event.timelineId != null) {
      try {
        final mapper = const WhatsAppMessageMapper();
        final row = Map<String, dynamic>.of(payload);
        row.putIfAbsent('id', () => event.timelineId);
        final message = mapper.fromTimeline(row);
        _append(id, [message]);
        return;
      } catch (_) {
        // Fall through to refetch.
      }
    }
    await _poll(id);
  }

  void _append(String id, List<ConversationMessage> incoming) {
    final current = state[id]?.thread;
    if (current == null || incoming.isEmpty) return;
    // Reconcile the realtime race: a server-confirmed agent message that
    // matches a pending optimistic bubble means our send landed — drop the
    // optimistic twin so the message never appears twice (failed bubbles
    // are kept for tap-to-retry).
    final confirmed = {
      for (final m in incoming)
        if (m.sender == MessageSender.agent && !m.id.startsWith('local-'))
          conversationMessagePreview(m.content)
    };
    final base = confirmed.isEmpty
        ? current.messages
        : current.messages.where((m) {
            if (!m.id.startsWith('local-') ||
                m.sender != MessageSender.agent ||
                m.delivery == MessageDelivery.failed) {
              return true;
            }
            return !confirmed.contains(conversationMessagePreview(m.content));
          }).toList();
    final known = base.map((m) => m.id).toSet();
    final fresh = incoming.where((m) => known.add(m.id)).toList();
    if (fresh.isEmpty && base.length == current.messages.length) return;
    final merged = [...base, ...fresh]
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final last = merged.last;
    _set(id,
        WhatsAppThreadState(thread: current.copyWith(messages: merged, conversation: current.conversation.copyWith(preview: conversationMessagePreview(last.content), time: DateFormat.Hm().format(last.sentAt.toLocal()), unreadCount: 0)), live: state[id]?.live ?? false));
    unawaited(ref.read(whatsAppRepositoryProvider).markRead(id).catchError((_) {}));
  }

  Future<void> _poll(String id) async {
    if (!_polling.add(id)) return;
    try {
      final thread = state[id]?.thread;
      if (thread == null) return;
      if (thread.conversation.status == ChatConversationStatus.resolved) {
        return;
      }
      final last = thread.messages.fold<int>(0, (max, item) {
        final value = int.tryParse(item.id) ?? 0;
        return value > max ? value : max;
      });
      if (last == 0) return;
      final newer = await ref.read(whatsAppRepositoryProvider).newer(id, last);
      if (!ref.mounted) return;
      final existing = state[id]?.thread;
      if (newer.isEmpty || existing == null) return;
      final knownIds = existing.messages.map((item) => item.id).toSet();
      final confirmed = newer.where((item) => knownIds.add(item.id)).toList();
      if (confirmed.isNotEmpty) {
        // Server truth supersedes pending optimistic bubbles, but failed
        // ones are kept so tap-to-retry stays available.
        final withoutOptimistic = existing.messages
            .where((m) =>
                !m.id.startsWith('local-') ||
                m.delivery == MessageDelivery.failed)
            .toList();
        final merged = [...withoutOptimistic, ...confirmed]
          ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
        final lastMsg = merged.last;
        _set(id,
            WhatsAppThreadState(thread: existing.copyWith(messages: merged, conversation: existing.conversation.copyWith(preview: conversationMessagePreview(lastMsg.content), time: DateFormat.Hm().format(lastMsg.sentAt.toLocal()))), live: state[id]?.live ?? false));
      }
    } catch (_) {
      // Polling is best effort.
    } finally {
      _polling.remove(id);
    }
  }

  Future<void> sendTyping(String id) async {
    final now = DateTime.now();
    final last = _lastTypingAt[id];
    if (last != null && now.difference(last) < const Duration(seconds: 4)) {
      return;
    }
    _lastTypingAt[id] = now;
    unawaited(
        ref.read(whatsAppRepositoryProvider).typing(id).catchError((_) {}));
  }

  Future<void> send(
    String id,
    String text, {
    String? replyToId,
    File? attachment,
    int? durationSecs,
    void Function(int sent, int total)? onProgress,
  }) async {
    final previous = state[id];
    final thread = previous?.thread;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachment == null) return;

    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = _optimisticMessage(
      localId: localId,
      text: trimmed,
      replyToId: replyToId,
      attachment: attachment,
      durationSecs: durationSecs,
    );
    if (thread != null) {
      _set(id,
          WhatsAppThreadState(thread: thread.copyWith(messages: [...thread.messages, optimistic], conversation: thread.conversation.copyWith(preview: trimmed.isEmpty ? 'Attachment' : trimmed, time: DateFormat.Hm().format(DateTime.now()))), sending: true, live: previous?.live ?? false));
    } else {
      _set(id, const WhatsAppThreadState(sending: true));
    }

    // Durable enqueue first so airplane-mode sends survive.
    final outbox = ref.read(whatsAppOutboxProvider);
    await outbox.enqueue(WhatsAppOutboxEntry(
      localId: localId,
      ticketId: id,
      text: trimmed.isEmpty ? null : trimmed,
      replyToId: replyToId,
      filePath: attachment?.path,
      mimeType: attachment == null ? null : _mimeFor(attachment.path),
      fileName: attachment?.uri.pathSegments.last,
      durationSecs: durationSecs,
      attempts: 0,
      createdAt: DateTime.now(),
      status: 'pending',
    ));

    try {
      await _deliver(localId, onProgress: onProgress);
    } catch (_) {
      // _deliver marks failed + keeps optimistic bubble for retry.
    }
    if (!ref.mounted) return;
    final refreshed = state[id];
    _set(id,
        WhatsAppThreadState(thread: refreshed?.thread, error: refreshed?.error, live: refreshed?.live ?? false));
    unawaited(_poll(id));
  }

  ConversationMessage _optimisticMessage({
    required String localId,
    required String text,
    String? replyToId,
    File? attachment,
    int? durationSecs,
  }) {
    ConversationMessageContent content;
    if (attachment != null) {
      final lower = attachment.path.toLowerCase();
      if (lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg')) {
        content = ImageMessageContent(
            assetPath: attachment.path,
            caption: text.isEmpty ? null : text);
      } else if (lower.endsWith('.mp4')) {
        content = VideoMessageContent(
            assetPath: attachment.path,
            thumbnailAssetPath: attachment.path,
            duration: Duration(seconds: durationSecs ?? 0),
            caption: text.isEmpty ? null : text);
      } else if (lower.endsWith('.ogg') ||
          lower.endsWith('.opus') ||
          lower.endsWith('.m4a') ||
          lower.endsWith('.mp3')) {
        content = AudioMessageContent(
            assetPath: attachment.path,
            duration: Duration(seconds: durationSecs ?? 0),
            waveform: const [.3, .55, .4, .7, .5]);
      } else {
        content = DocumentMessageContent(
            assetPath: attachment.path,
            fileName: attachment.uri.pathSegments.last,
            mimeType: _mimeFor(attachment.path),
            sizeLabel: 'Sending…');
      }
    } else {
      content = TextMessageContent(text);
    }
    return ConversationMessage(
      id: localId,
      sender: MessageSender.agent,
      sentAt: DateTime.now(),
      content: content,
      delivery: MessageDelivery.sending,
      replyToId: replyToId,
    );
  }

  String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  Future<void> _deliver(String localId,
      {void Function(int sent, int total)? onProgress}) async {
    final outbox = ref.read(whatsAppOutboxProvider);
    final all = await outbox.pending();
    final entry = all.where((e) => e.localId == localId).firstOrNull ??
        (all.isNotEmpty ? all.first : null);
    if (entry == null) return;
    await outbox.markSending(entry.localId);
    // Surface progress on the optimistic bubble.
    void progress(int sent, int total) {
      onProgress?.call(sent, total);
      final current = state[entry.ticketId]?.thread;
      if (current == null) return;
      final messages = [
        for (final m in current.messages)
          if (m.id == entry.localId)
            m.copyWith(
                uploadProgress: total <= 0 ? null : sent / total)
          else
            m
      ];
      _set(entry.ticketId,
          WhatsAppThreadState(thread: current.copyWith(messages: messages), sending: true, live: state[entry.ticketId]?.live ?? false));
    }

    try {
      await ref.read(whatsAppRepositoryProvider).send(
            entry.ticketId,
            message: entry.text,
            replyToId: entry.replyToId,
            attachment:
                entry.filePath == null ? null : File(entry.filePath!),
            durationSecs: entry.durationSecs,
            onProgress: entry.filePath == null ? null : progress,
          );
      await outbox.remove(entry.localId);
      // Remove optimistic bubble; server truth arrives via realtime/poll.
      final current = state[entry.ticketId]?.thread;
      if (current != null) {
        final pruned = current.messages
            .where((m) => m.id != entry.localId)
            .toList();
        _set(entry.ticketId,
            WhatsAppThreadState(thread: current.copyWith(messages: pruned), sending: false, live: state[entry.ticketId]?.live ?? false));
      }
    } catch (_) {
      final remaining = await outbox.pending(ticketId: entry.ticketId);
      final match = remaining
          .where((e) => e.localId == entry.localId)
          .firstOrNull;
      await outbox.markFailed(entry.localId, (match?.attempts ?? 0) + 1);
      final current = state[entry.ticketId]?.thread;
      if (current != null) {
        final messages = [
          for (final m in current.messages)
            if (m.id == entry.localId)
              m.copyWith(
                  delivery: MessageDelivery.failed, clearUploadProgress: true)
            else
              m
        ];
        _set(entry.ticketId,
            WhatsAppThreadState(thread: current.copyWith(messages: messages), sending: false, live: state[entry.ticketId]?.live ?? false));
      }
      rethrow;
    }
  }

  /// Retries a failed optimistic bubble (tap-to-retry in the room).
  Future<void> retry(String ticketId, String localId) async {
    final current = state[ticketId]?.thread;
    if (current != null) {
      final messages = [
        for (final m in current.messages)
          if (m.id == localId) m.copyWith(delivery: MessageDelivery.sending) else m
      ];
      _set(ticketId,
          WhatsAppThreadState(thread: current.copyWith(messages: messages), sending: true, live: state[ticketId]?.live ?? false));
    }
    try {
      await _deliver(localId);
    } catch (_) {}
    if (!ref.mounted) return;
    final refreshed = state[ticketId];
    _set(ticketId,
        WhatsAppThreadState(thread: refreshed?.thread, error: refreshed?.error, live: refreshed?.live ?? false));
    unawaited(_poll(ticketId));
  }

  /// Flushes all queued sends for a ticket (called on open + reconnect).
  Future<void> flushOutbox(String ticketId) async {
    final pending =
        await ref.read(whatsAppOutboxProvider).pending(ticketId: ticketId);
    // Ensure optimistic bubbles exist for entries enqueued while the room
    // was closed (e.g. previous process run).
    final current = state[ticketId]?.thread;
    if (current != null && pending.isNotEmpty) {
      final known = current.messages.map((m) => m.id).toSet();
      final missing = pending
          .where((e) => !known.contains(e.localId))
          .map((e) => _optimisticMessage(
                localId: e.localId,
                text: e.text ?? '',
                replyToId: e.replyToId,
                attachment:
                    e.filePath == null ? null : File(e.filePath!),
                durationSecs: e.durationSecs,
              ))
          .toList();
      if (missing.isNotEmpty) {
        _set(ticketId,
            WhatsAppThreadState(thread: current.copyWith(messages: [...current.messages, ...missing]), sending: true, live: state[ticketId]?.live ?? false));
      }
    }
    for (final entry in pending) {
      if (!ref.mounted) return;
      final wait = WhatsAppOutbox.backoffForAttempt(entry.attempts);
      if (entry.attempts > 0 && entry.attempts < 5) {
        await Future.delayed(
            wait > const Duration(seconds: 5) ? const Duration(seconds: 5) : wait);
      }
      try {
        await _deliver(entry.localId);
      } catch (_) {
        // Leave failed entries for manual retry.
      }
    }
    if (ref.mounted) unawaited(_poll(ticketId));
  }

  Future<void> status(String id, String value,
      {String? reason, String? pendingReason}) async {
    await ref
        .read(whatsAppRepositoryProvider)
        .status(id, value, reason: reason, pendingReason: pendingReason);
    await load(id);
  }

  Future<List<WhatsAppTemplate>> templates() =>
      ref.read(whatsAppRepositoryProvider).templates();

  Future<List<GroupChatAgent>> groupAgents(String id) =>
      ref.read(whatsAppRepositoryProvider).groupAgents(id);

  Future<void> addGroupAgent(String ticketId, String userId) =>
      ref.read(whatsAppRepositoryProvider).addGroupAgent(ticketId, userId);

  Future<void> removeGroupAgent(String ticketId, String userId) =>
      ref.read(whatsAppRepositoryProvider).removeGroupAgent(ticketId, userId);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
