import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../services/realtime/realtime_event.dart';
import '../../services/realtime/realtime_service.dart';
import '../../services/realtime/whatsapp_message_mapper.dart';
import 'conversation_room_page_model.dart';

/// Production data source for website-widget tickets. It deliberately uses
/// the same ticket/timeline protocol as WhatsApp, while only exposing the
/// text capabilities available on the widget endpoint.
class WidgetChatRepository {
  WidgetChatRepository(this._api);
  final ApiService _api;
  final _mapper = const WhatsAppMessageMapper();

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, item) => MapEntry('$key', item))
      : <String, dynamic>{};

  Future<
          ({
            List<ConversationThread> threads,
            int page,
            int lastPage,
            int total
          })>
      inbox(
          {required ChatConversationStatus status,
          required String query,
          required int page}) async {
    final result = _map(await _api.get('/tickets', queryParameters: {
      'source': 'widget',
      'page': page,
      'per_page': 20,
      if (status != ChatConversationStatus.all)
        'status': switch (status) {
          ChatConversationStatus.open => 'open',
          ChatConversationStatus.inProgress => 'in_progress',
          ChatConversationStatus.resolved => 'resolved',
          ChatConversationStatus.all => '',
        },
      if (query.trim().isNotEmpty) 'search': query.trim(),
    }));
    final meta = _map(result['meta']);
    final rows = result['data'];
    return (
      threads: rows is List
          ? rows
              .whereType<Map>()
              .map((row) => _mapper.summaryToThread(_map(row),
                  channel: ChatChannel.widgetChat))
              .toList()
          : const <ConversationThread>[],
      page: (meta['current_page'] as num?)?.toInt() ?? page,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? 1,
      total: (meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<ConversationThread> thread(String id) async {
    final ticketResult = _map(await _api.get('/tickets/$id'));
    final ticket = _map(ticketResult['ticket']).isEmpty
        ? ticketResult
        : _map(ticketResult['ticket']);
    final timelineResult = _map(await _api.get('/tickets/$id/timeline'));
    final summary =
        _mapper.summaryToThread(ticket, channel: ChatChannel.widgetChat);
    final rows = timelineResult['timeline'];
    final messages = rows is List
        ? rows
            .whereType<Map>()
            .map((row) => _mapper.fromTimeline(_map(row)))
            .toList()
        : const <ConversationMessage>[];
    if (messages.isEmpty) return summary;
    final last = messages.last;
    return summary.copyWith(
      messages: messages,
      conversation: summary.conversation.copyWith(
        preview: conversationMessagePreview(last.content),
        time: DateFormat.Hm().format(last.sentAt.toLocal()),
      ),
    );
  }

  Future<List<ConversationMessage>> newer(String id, int sinceId) async {
    final result = _map(await _api
        .get('/tickets/$id/timeline', queryParameters: {'since_id': sinceId}));
    final rows = result['timeline'];
    return rows is List
        ? rows
            .whereType<Map>()
            .map((row) => _mapper.fromTimeline(_map(row)))
            .toList()
        : const [];
  }

  Future<void> send(String id, String message) => _api
      .post('/tickets/$id/reply', {'channel': 'widget', 'message': message});
  Future<void> typing(String id) =>
      _api.post('/tickets/$id/typing', {'is_typing': true});
  Future<void> status(String id, String value) =>
      _api.post('/tickets/$id/status', {'status': value});
}

final widgetChatRepositoryProvider = Provider<WidgetChatRepository>(
    (ref) => WidgetChatRepository(ref.read(apiServiceProvider)));

class WidgetChatInboxState {
  const WidgetChatInboxState(
      {this.threads = const [],
      this.loading = false,
      this.refreshing = false,
      this.loadingMore = false,
      this.error,
      this.page = 0,
      this.lastPage = 1,
      this.total = 0,
      this.query = '',
      this.status = ChatConversationStatus.all,
      this.live = false});
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
  WidgetChatInboxState copyWith(
          {List<ConversationThread>? threads,
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
          bool? live}) =>
      WidgetChatInboxState(
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
          live: live ?? this.live);
}

final widgetChatInboxProvider =
    NotifierProvider<WidgetChatInboxController, WidgetChatInboxState>(
        WidgetChatInboxController.new);

class WidgetChatInboxController extends Notifier<WidgetChatInboxState> {
  int _request = 0;
  StreamSubscription<RealtimeEvent>? _events;
  @override
  WidgetChatInboxState build() {
    ref.onDispose(() => unawaited(_events?.cancel()));
    return const WidgetChatInboxState();
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
          .read(widgetChatRepositoryProvider)
          .inbox(status: status, query: query, page: 1);
      if (!ref.mounted || request != _request) {
        return;
      }
      state = WidgetChatInboxState(
          threads: result.threads,
          page: result.page,
          lastPage: result.lastPage,
          total: result.total,
          query: query,
          status: status,
          live: state.live);
      await _watch();
    } catch (error) {
      if (ref.mounted && request == _request) {
        state = state.copyWith(loading: false, refreshing: false, error: error);
      }
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final result = await ref.read(widgetChatRepositoryProvider).inbox(
          status: state.status, query: state.query, page: state.page + 1);
      if (!ref.mounted) return;
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
      if (ref.mounted) state = state.copyWith(loadingMore: false, error: error);
    }
  }

  Future<void> _watch() async {
    if (_events != null) return;
    final service = ref.read(realtimeServiceProvider);
    if (!service.isEnabled) return;
    await service.watchInbox();
    _events = service.events.listen(_onEvent);
    if (ref.mounted) state = state.copyWith(live: true, clearError: true);
  }

  bool _isWidget(Map<String, dynamic> data) =>
      data['source'] == null || '${data['source']}'.toLowerCase() == 'widget';
  void _onEvent(RealtimeEvent event) {
    if (!ref.mounted) return;
    if (event is TicketMessageEvent) {
      final id = event.ticketId ?? '${event.payload['ticket_id'] ?? ''}';
      final index =
          state.threads.indexWhere((item) => item.conversation.id == id);
      if (index < 0 || !_isWidget(event.payload)) return;
      final current = state.threads[index];
      final preview =
          '${event.payload['description'] ?? event.payload['body'] ?? current.conversation.preview}';
      final updated = current.conversation.copyWith(
          preview: preview,
          time: DateFormat.Hm().format(DateTime.now()),
          unreadCount: current.conversation.unreadCount + 1);
      final rows = List<ConversationThread>.of(state.threads)..removeAt(index);
      state = state.copyWith(threads: [
        ConversationThread(
            conversation: updated,
            messages: current.messages,
            summary: current.summary),
        ...rows
      ]);
    } else if (event is InboxUpdateEvent && _isWidget(event.payload)) {
      final row = event.payload['ticket'] is Map
          ? Map<String, dynamic>.from(event.payload['ticket'] as Map)
          : event.payload;
      if (row['id'] == null || !_isWidget(row)) return;
      final incoming = const WhatsAppMessageMapper()
          .summaryToThread(row, channel: ChatChannel.widgetChat);
      final rows = List<ConversationThread>.of(state.threads);
      final index = rows.indexWhere(
          (item) => item.conversation.id == incoming.conversation.id);
      if (index >= 0) {
        rows.removeAt(index);
      } else if (state.status != ChatConversationStatus.all &&
          incoming.conversation.status != state.status) {
        return;
      }
      state = state.copyWith(
          threads: [incoming, ...rows],
          total: index < 0 ? state.total + 1 : state.total);
    }
  }

  void markLocalRead(String id) => state = state.copyWith(threads: [
        for (final item in state.threads)
          if (item.conversation.id == id)
            ConversationThread(
                conversation: item.conversation.copyWith(unreadCount: 0),
                messages: item.messages,
                summary: item.summary)
          else
            item
      ]);
}

class WidgetChatThreadState {
  const WidgetChatThreadState(
      {this.thread,
      this.loading = false,
      this.sending = false,
      this.error,
      this.live = false,
      this.degraded = false});
  final ConversationThread? thread;
  final bool loading;
  final bool sending;
  final Object? error;
  final bool live;
  final bool degraded;
}

final widgetChatThreadsProvider = NotifierProvider<WidgetChatThreadController,
    Map<String, WidgetChatThreadState>>(WidgetChatThreadController.new);

class WidgetChatThreadController
    extends Notifier<Map<String, WidgetChatThreadState>> {
  final _subs = <String, StreamSubscription<RealtimeEvent>>{};
  final _typing = <String, DateTime>{};
  final _polling = <String>{};
  @override
  Map<String, WidgetChatThreadState> build() {
    ref.onDispose(() {
      for (final sub in _subs.values) {
        unawaited(sub.cancel());
      }
    });
    return {};
  }

  void _set(String id, WidgetChatThreadState value) =>
      state = {...state, id: value};
  Future<void> load(String id) async {
    final before = state[id];
    _set(
        id,
        WidgetChatThreadState(
            thread: before?.thread,
            loading: true,
            sending: before?.sending ?? false,
            live: before?.live ?? false));
    try {
      final thread = await ref.read(widgetChatRepositoryProvider).thread(id);
      if (!ref.mounted) return;
      _set(id,
          WidgetChatThreadState(thread: thread, live: before?.live ?? false));
      unawaited(_attach(id));
      ref.read(widgetChatInboxProvider.notifier).markLocalRead(id);
    } catch (error) {
      if (ref.mounted) {
        _set(id, WidgetChatThreadState(thread: before?.thread, error: error));
      }
    }
  }

  void startPolling(String id) => unawaited(_attach(id));
  void stopPolling(String id) => unawaited(detachRealtime(id));
  Future<void> detachRealtime(String id) async {
    await _subs.remove(id)?.cancel();
    try {
      await ref.read(realtimeServiceProvider).unwatchTicket(id);
    } catch (_) {}
  }

  Future<void> _attach(String id) async {
    if (_subs.containsKey(id)) return;
    final service = ref.read(realtimeServiceProvider);
    if (!service.isEnabled) return;
    await service.watchTicket(id);
    _subs[id] = service.events.listen((event) => _onEvent(id, event));
    if (!ref.mounted) return;
    final current = state[id];
    if (current != null) {
      _set(
          id,
          WidgetChatThreadState(
              thread: current.thread, sending: current.sending, live: true));
    }
  }

  Future<void> _onEvent(String id, RealtimeEvent event) async {
    if (event is! TicketMessageEvent || !ref.mounted) return;
    if (event.ticketId != null && event.ticketId != id) return;
    final payload = event.payload;
    if (payload['source'] != null && '${payload['source']}' != 'widget') return;
    if (event.timelineId != null &&
        (payload['description'] is String || payload['body'] is String)) {
      final row = Map<String, dynamic>.of(payload)
        ..putIfAbsent('id', () => event.timelineId);
      _append(id, [const WhatsAppMessageMapper().fromTimeline(row)]);
    } else {
      await _poll(id);
    }
  }

  void _append(String id, List<ConversationMessage> incoming) {
    final thread = state[id]?.thread;
    if (thread == null) return;
    final ids = thread.messages.map((m) => m.id).toSet();
    final fresh = incoming.where((m) => ids.add(m.id)).toList();
    if (fresh.isEmpty) return;
    final messages = [...thread.messages, ...fresh]
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final last = messages.last;
    _set(
        id,
        WidgetChatThreadState(
            thread: thread.copyWith(
                messages: messages,
                conversation: thread.conversation.copyWith(
                    preview: conversationMessagePreview(last.content),
                    time: DateFormat.Hm().format(last.sentAt.toLocal()))),
            live: state[id]?.live ?? false));
  }

  Future<void> _poll(String id) async {
    if (!_polling.add(id)) return;
    try {
      final thread = state[id]?.thread;
      if (thread == null) return;
      final last = thread.messages
          .map((m) => int.tryParse(m.id) ?? 0)
          .fold(0, (a, b) => a > b ? a : b);
      if (last > 0) {
        _append(
            id, await ref.read(widgetChatRepositoryProvider).newer(id, last));
      }
    } catch (_) {
    } finally {
      _polling.remove(id);
    }
  }

  Future<void> sendTyping(String id) async {
    final now = DateTime.now();
    if (_typing[id]?.add(const Duration(seconds: 4)).isAfter(now) ?? false) {
      return;
    }
    _typing[id] = now;
    try {
      await ref.read(widgetChatRepositoryProvider).typing(id);
    } catch (_) {}
  }

  Future<void> send(String id, String text) async {
    final thread = state[id]?.thread;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final local = ConversationMessage(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        sender: MessageSender.agent,
        sentAt: DateTime.now(),
        content: TextMessageContent(trimmed),
        delivery: MessageDelivery.sending);
    if (thread != null) {
      _set(
          id,
          WidgetChatThreadState(
              thread: thread.copyWith(
                  messages: [...thread.messages, local],
                  conversation: thread.conversation.copyWith(
                      preview: trimmed,
                      time: DateFormat.Hm().format(DateTime.now()))),
              sending: true,
              live: state[id]?.live ?? false));
    }
    try {
      await ref.read(widgetChatRepositoryProvider).send(id, trimmed);
      final current = state[id]?.thread;
      if (current != null) {
        _set(
            id,
            WidgetChatThreadState(
                thread: current.copyWith(
                    messages: current.messages
                        .where((m) => m.id != local.id)
                        .toList()),
                live: state[id]?.live ?? false));
      }
      await _poll(id);
    } catch (_) {
      final current = state[id]?.thread;
      if (current != null) {
        _set(
            id,
            WidgetChatThreadState(
                thread: current.copyWith(messages: [
                  for (final m in current.messages)
                    if (m.id == local.id)
                      m.copyWith(delivery: MessageDelivery.failed)
                    else
                      m
                ]),
                live: state[id]?.live ?? false));
      }
      rethrow;
    }
  }

  Future<void> retry(String id, String localId) async {
    final message =
        state[id]?.thread?.messages.where((m) => m.id == localId).firstOrNull;
    if (message?.content case TextMessageContent(:final text)) {
      await send(id, text);
    }
  }

  Future<void> status(String id, String value) async {
    await ref.read(widgetChatRepositoryProvider).status(id, value);
    await load(id);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
