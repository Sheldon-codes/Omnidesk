import 'dart:async';

import 'realtime_event.dart';

/// Abstract WebSocket transport. UI and stores depend on this contract, never
/// on `pusher_channels_flutter` directly, so future transports (raw
/// WebSocket, Centrifugo, Ably) can be swapped without touching call sites.
abstract class RealtimeTransport {
  /// Broadcast of connection lifecycle changes.
  Stream<RealtimeConnectionState> get connectionState;

  RealtimeConnectionState get currentState;

  /// Raw decoded events from all subscribed channels.
  Stream<TransportEnvelope> get events;

  Future<void> connect();
  Future<void> disconnect();

  /// Idempotent subscribe. Multiple callers may subscribe to the same
  /// channel; the transport keeps an internal ref-count.
  Future<void> subscribe(String channelName);

  /// Decrements the ref-count; actually unsubscribes at zero.
  Future<void> unsubscribe(String channelName);

  Future<void> dispose();
}

/// Raw event envelope emitted by the transport before typed decoding.
class TransportEnvelope {
  const TransportEnvelope({
    required this.channel,
    required this.eventName,
    required this.data,
  });

  final String channel;
  final String eventName;
  final Map<String, dynamic> data;
}
