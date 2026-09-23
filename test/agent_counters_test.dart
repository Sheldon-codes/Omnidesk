import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/services/agent_counters.dart';

void main() {
  test('maps documented counters and keeps Chats separate from Email', () {
    final counters = AgentCounters.fromJson({
      'open_tickets': 6,
      'missed_calls': 2,
      'unread_chats': {
        'whatsapp': 3,
        'email': 1,
        'widget': 2,
        'total': 6,
      },
    });

    expect(counters.openTickets, 6);
    expect(counters.missedCalls, 2);
    expect(counters.whatsAppUnread, 3);
    expect(counters.widgetUnread, 2);
    expect(counters.emailUnread, 1);
    // The Chats destination represents WhatsApp + Widget only. The API total
    // also includes Email and therefore is intentionally not used here.
    expect(counters.chatUnread, 5);
  });

  test('treats malformed and negative counter values as zero', () {
    final counters = AgentCounters.fromJson({
      'open_tickets': -1,
      'missed_calls': 'not-a-number',
      'unread_chats': {'whatsapp': '-2', 'email': 4},
    });

    expect(counters.openTickets, 0);
    expect(counters.missedCalls, 0);
    expect(counters.whatsAppUnread, 0);
    expect(counters.emailUnread, 4);
    expect(counters.widgetUnread, 0);
  });
}
