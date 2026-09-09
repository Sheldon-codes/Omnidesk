import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'realtime_event.dart';
import 'realtime_service.dart';

/// Per-ticket typing presence with natural expiry.
///
/// The backend rebroadcasts typing pings every few seconds while composing;
/// if pings stop, the indicator clears locally after [expiry] without needing
/// an explicit `is_typing=false` event.
class TypingPresence {
  const TypingPresence({this.who, this.displayName, this.expiresAt});
  final String? who;
  final String? displayName;
  final DateTime? expiresAt;

  bool get isTyping =>
      who != null && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  static const none = TypingPresence();
}

class TypingPresenceController extends Notifier<Map<String, TypingPresence>> {
  TypingPresenceController(this.ticketId);
  final String ticketId;

  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _sweeper;

  static const expiry = Duration(seconds: 6);

  @override
  Map<String, TypingPresence> build() {
    final service = ref.watch(realtimeServiceProvider);
    _sub ??= service.events.listen((event) {
      if (event is! TicketTypingEvent || event.ticketId != ticketId) return;
      final current = Map<String, TypingPresence>.of(state);
      if (event.isTyping) {
        current[event.who] = TypingPresence(
          who: event.who,
          displayName: event.displayName,
          expiresAt: DateTime.now().add(expiry),
        );
      } else {
        current.remove(event.who);
      }
      state = current;
    });
    _sweeper ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (!ref.mounted) return;
      final now = DateTime.now();
      final pruned = Map<String, TypingPresence>.of(state)
        ..removeWhere(
            (_, v) => v.expiresAt != null && !v.expiresAt!.isAfter(now));
      if (pruned.length != state.length) state = pruned;
    });
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _sweeper?.cancel();
    });
    return {};
  }

  /// Any active typist (customer preferred for the UI label).
  TypingPresence get active {
    final customer = state['customer'];
    if (customer != null && customer.isTyping) return customer;
    for (final entry in state.values) {
      if (entry.isTyping) return entry;
    }
    return TypingPresence.none;
  }
}

final typingPresenceProvider = NotifierProvider.family<
    TypingPresenceController, Map<String, TypingPresence>, String>(
  (ticketId) => TypingPresenceController(ticketId),
);
