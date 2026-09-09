/// Typed realtime events. The transport layer emits raw maps; the service
/// layer decodes them into these sealed types so UI code never parses JSON.
sealed class RealtimeEvent {
  const RealtimeEvent();
}

/// Connection lifecycle broadcast to every listener.
class RealtimeConnectionEvent extends RealtimeEvent {
  const RealtimeConnectionEvent(this.state);
  final RealtimeConnectionState state;
}

enum RealtimeConnectionState {
  disconnected,
  connecting,
  connected,
  degraded, // WS down, polling fallback active
}

/// A new / updated timeline entry for a ticket.
///
/// Payloads from Laravel Reverb are inconsistent (sometimes the full
/// timeline row, sometimes a thin ticket stub). [payload] always holds the
/// raw map so the mapper can decide whether a `since_id` refetch is needed.
/// When the payload already contains a usable `timeline_id`/`id`, [timelineId]
/// is populated and UI can optimistically merge without a fetch.
class TicketMessageEvent extends RealtimeEvent {
  const TicketMessageEvent({
    required this.channel,
    required this.payload,
    this.ticketId,
    this.timelineId,
  });

  final String channel;
  final Map<String, dynamic> payload;
  final String? ticketId;
  final String? timelineId;
}

/// Typing indicator for a ticket room.
class TicketTypingEvent extends RealtimeEvent {
  const TicketTypingEvent({
    required this.ticketId,
    required this.who,
    required this.isTyping,
    this.displayName,
  });

  final String ticketId;
  final String who; // 'customer' | 'agent'
  final bool isTyping;
  final String? displayName;
}

/// Workspace-level inbox hint (badge counts, preview snippet, new ticket).
class InboxUpdateEvent extends RealtimeEvent {
  const InboxUpdateEvent({required this.payload});
  final Map<String, dynamic> payload;
}

/// Decoded event routing result used by [RealtimeService].
class DecodedRealtimeEvent {
  const DecodedRealtimeEvent({required this.event, required this.ticketId});
  final RealtimeEvent event;
  final String? ticketId;
}
