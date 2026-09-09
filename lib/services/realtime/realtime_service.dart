import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'realtime_config.dart';
import 'realtime_event.dart';
import 'realtime_transport.dart';
import 'reverb_transport.dart';

/// Central WebSocket facade for the whole app.
///
/// Responsibilities:
/// * own the single transport connection (lazy, ref-counted channels)
/// * decode raw envelopes into typed [RealtimeEvent]s
/// * exponential-backoff reconnect with jitter
/// * expose per-ticket and inbox streams so stores stay thin
///
/// Future channels only need a new [subscribe] call + decoder entry in
/// [_decode]; no transport changes.
class RealtimeService {
  RealtimeService({
    required RealtimeTransport transport,
    required RealtimeConfig config,
  })  : _transport = transport,
        _config = config {
    _transportSub = _transport.events.listen(_route, onError: (_) {});
    _stateSub = _transport.connectionState.listen((state) {
      _connection.add(state);
      if (state == RealtimeConnectionState.connected) {
        _retryAttempt = 0;
        unawaited((_transport is ReverbTransport)
            ? (_transport as ReverbTransport).resubscribeAll()
            : Future.value());
      } else if (state == RealtimeConnectionState.disconnected) {
        _scheduleReconnect();
      }
    });
  }

  final RealtimeTransport _transport;
  final RealtimeConfig _config;

  final _typed = StreamController<RealtimeEvent>.broadcast();
  final _connection =
      StreamController<RealtimeConnectionState>.broadcast();
  final _channels = <String, int>{};
  final _seenTimelineIds = <String>{};

  StreamSubscription<TransportEnvelope>? _transportSub;
  StreamSubscription<RealtimeConnectionState>? _stateSub;
  Timer? _reconnectTimer;
  int _retryAttempt = 0;
  bool _disposed = false;
  bool _started = false;

  Stream<RealtimeEvent> get events => _typed.stream;
  Stream<RealtimeConnectionState> get connection => _connection.stream;
  RealtimeConnectionState get currentState => _transport.currentState;
  bool get isEnabled => _config.enabled;

  /// Ensure the underlying socket is up. Safe to call repeatedly.
  Future<void> ensureConnected() async {
    if (_disposed || !_config.enabled) return;
    if (!_started) {
      _started = true;
      _connection.add(RealtimeConnectionState.connecting);
    }
    if (_transport.currentState == RealtimeConnectionState.connected ||
        _transport.currentState == RealtimeConnectionState.connecting) {
      return;
    }
    await _transport.connect();
  }

  Future<void> notifyBackground() async {
    // Keep subscriptions but let the OS suspend the socket; reconnect on
    // foreground via [notifyForeground].
  }

  Future<void> notifyForeground() async {
    if (_disposed || !_config.enabled) return;
    if (_channels.isNotEmpty) await ensureConnected();
  }

  String ticketChannel(String ticketId) => 'ticket.$ticketId';
  String tenantChannel(String tenantId) => 'tenant.$tenantId';

  Future<void> watchTicket(String ticketId) async {
    await _retain(ticketChannel(ticketId));
  }

  Future<void> unwatchTicket(String ticketId) async {
    await _release(ticketChannel(ticketId));
  }

  Future<void> watchInbox({String? tenantId}) async {
    // Backend today broadcasts on `tickets` (+ per-ticket rooms); tenant
    // rooms are forward-compatible for badge counts.
    await _retain('tickets');
    if (tenantId != null && tenantId.isNotEmpty) {
      await _retain(tenantChannel(tenantId));
    }
  }

  Future<void> unwatchInbox({String? tenantId}) async {
    await _release('tickets');
    if (tenantId != null && tenantId.isNotEmpty) {
      await _release(tenantChannel(tenantId));
    }
  }

  /// Generic future-proof subscription for upcoming channels
  /// (`call.*`, `widget.*`, ...).
  Future<void> subscribe(String channel) => _retain(channel);
  Future<void> unsubscribe(String channel) => _release(channel);

  Future<void> _retain(String channel) async {
    if (_disposed || !_config.enabled) return;
    _channels.update(channel, (v) => v + 1, ifAbsent: () => 1);
    if (_channels[channel]! > 1) return;
    await ensureConnected();
    try {
      await _transport.subscribe(channel);
    } catch (error) {
      developer.log('retain $channel failed: $error', name: 'RealtimeService');
    }
  }

  Future<void> _release(String channel) async {
    final count = (_channels[channel] ?? 0) - 1;
    if (count > 0) {
      _channels[channel] = count;
      return;
    }
    _channels.remove(channel);
    try {
      await _transport.unsubscribe(channel);
    } catch (_) {}
  }

  void _route(TransportEnvelope envelope) {
    if (_disposed) return;
    try {
      final decoded = _decode(envelope);
      if (decoded == null) return;
      final event = decoded.event;
      // Cross-message dedupe: identical timeline ids arriving via both
      // `ticket.{id}` and `tickets` fan-out collapse to one emission.
      if (event is TicketMessageEvent && event.timelineId != null) {
        if (!_seenTimelineIds.add('${event.ticketId}:${event.timelineId}')) {
          return;
        }
        if (_seenTimelineIds.length > 500) _seenTimelineIds.clear();
      }
      _typed.add(event);
    } catch (error) {
      developer.log('decode failed: $error', name: 'RealtimeService');
    }
  }

  DecodedRealtimeEvent? _decode(TransportEnvelope envelope) {
    final name = envelope.eventName.trim();
    final normalized = name.startsWith('.') ? name.substring(1) : name;
    final lower = normalized.toLowerCase();
    final data = envelope.data;
    final channel = envelope.channel;

    String? ticketIdFromChannel() {
      if (channel.startsWith('ticket.')) {
        return channel.substring('ticket.'.length);
      }
      for (final key in const ['ticket_id', 'ticketId', 'id']) {
        final v = data[key];
        if (v != null && '$v'.isNotEmpty) return '$v';
      }
      return null;
    }

    if (lower == 'ticket.message' ||
        lower == 'newticketmessage' ||
        lower == 'new_ticket_message' ||
        lower == 'apptestevents\\newticketmessage' ||
        lower.endsWith('newticketmessage')) {
      final ticketId = ticketIdFromChannel();
      String? timelineId;
      for (final key in const ['timeline_id', 'timelineId', 'timeline-id']) {
        final v = data[key];
        if (v != null && '$v'.isNotEmpty) {
          timelineId = '$v';
          break;
        }
      }
      // Some broadcasts send only `{ticket: {...}}`; still emit so stores
      // can trigger a `since_id` refetch.
      timelineId ??= data['id'] is num || data['id'] is String
          ? '${data['id']}'
          : null;
      return DecodedRealtimeEvent(
        event: TicketMessageEvent(
          channel: channel,
          payload: data,
          ticketId: ticketId,
          timelineId: timelineId,
        ),
        ticketId: ticketId,
      );
    }

    if (lower == 'ticket.typing' ||
        lower == 'tickettyping' ||
        lower == 'typing' && channel.startsWith('ticket.')) {
      final ticketId =
          ticketIdFromChannel() ?? '${data['ticket_id'] ?? data['ticketId'] ?? ''}';
      if (ticketId.isEmpty) return null;
      final who = '${data['who'] ?? data['side'] ?? 'customer'}';
      final isTyping = data['is_typing'] is bool
          ? data['is_typing'] as bool
          : data['isTyping'] is bool
              ? data['isTyping'] as bool
              : data['typing'] is bool
                  ? data['typing'] as bool
                  : true;
      return DecodedRealtimeEvent(
        event: TicketTypingEvent(
          ticketId: ticketId,
          who: who,
          isTyping: isTyping,
          displayName: data['name']?.toString() ?? data['display_name']?.toString(),
        ),
        ticketId: ticketId,
      );
    }

    if (channel == 'tickets' ||
        channel.startsWith('tenant.') ||
        lower.contains('inbox') ||
        lower.contains('ticket.created') ||
        lower.contains('ticket.updated')) {
      return DecodedRealtimeEvent(
        event: InboxUpdateEvent(payload: data),
        ticketId: ticketIdFromChannel(),
      );
    }

    return null;
  }

  void _scheduleReconnect() {
    if (_disposed || !_config.enabled || _channels.isEmpty) return;
    _reconnectTimer?.cancel();
    _retryAttempt = (_retryAttempt + 1).clamp(1, 6);
    final baseMs = 1000 * pow(2, _retryAttempt - 1).toInt();
    final jitter = Random().nextInt(750);
    final delay = Duration(milliseconds: (baseMs + jitter).clamp(1000, 45000));
    _connection.add(RealtimeConnectionState.degraded);
    _reconnectTimer = Timer(delay, () {
      if (_disposed) return;
      unawaited(ensureConnected());
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _transportSub?.cancel();
    await _stateSub?.cancel();
    await _typed.close();
    await _connection.close();
    await _transport.dispose();
  }
}

final realtimeConfigProvider = Provider<RealtimeConfig>((ref) {
  return RealtimeConfig.fromEnv();
});

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final config = ref.watch(realtimeConfigProvider);
  final transport = ReverbTransport(config);
  final service = RealtimeService(transport: transport, config: config);
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// Filtered per-ticket stream for room widgets.
final ticketRealtimeProvider =
    StreamProvider.family<RealtimeEvent, String>((ref, ticketId) {
  final service = ref.watch(realtimeServiceProvider);
  return service.events.where((event) {
    if (event is TicketMessageEvent) return event.ticketId == ticketId;
    if (event is TicketTypingEvent) return event.ticketId == ticketId;
    return false;
  });
});

final realtimeConnectionProvider =
    StreamProvider<RealtimeConnectionState>((ref) {
  final service = ref.watch(realtimeServiceProvider);
  return service.connection;
});
