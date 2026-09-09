import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/conversation_room_page/conversation_room_page_model.dart';
import 'package:omnidesk_agent/services/realtime/whatsapp_message_mapper.dart';

void main() {
  const mapper = WhatsAppMessageMapper();

  test('maps text customer message with delivery none', () {
    final m = mapper.fromTimeline({
      'id': 501,
      'event_type': 'customer_message',
      'description': 'Hello',
      'is_from_customer': true,
      'created_at': '2026-08-31T07:38:00Z',
    });
    expect(m.id, '501');
    expect(m.sender, MessageSender.customer);
    expect(m.content, isA<TextMessageContent>());
    expect(m.delivery, MessageDelivery.none);
    expect(m.replyToId, isNull);
  });

  test('maps agent reply with quote + read receipt', () {
    final m = mapper.fromTimeline({
      'id': 502,
      'event_type': 'agent_reply',
      'description': 'We can help',
      'is_from_customer': false,
      'message_status': 'read',
      'quoted_message_text': 'Hello',
      'quoted_sender_name': 'David',
      'parent_id': 501,
      'created_at': '2026-08-31T07:39:15Z',
    });
    expect(m.sender, MessageSender.agent);
    expect(m.delivery, MessageDelivery.read);
    expect(m.replyToId, '501');
    expect(m.quotedText, 'Hello');
    expect(m.quotedSenderName, 'David');
  });

  test('maps image / voice / pdf / video media types', () {
    final image = mapper.fromTimeline({
      'id': 503,
      'event_type': 'customer_message',
      'description': 'ID photo',
      'is_from_customer': true,
      'media_url': 'https://x/id.jpg',
      'media_type': 'image/jpeg',
      'media_filename': 'id.jpg',
      'created_at': '2026-08-31T07:41:00Z',
    });
    expect(image.content, isA<ImageMessageContent>());

    final voice = mapper.fromTimeline({
      'id': 504,
      'event_type': 'customer_message',
      'description': '',
      'is_from_customer': true,
      'media_url': 'https://x/v.ogg',
      'media_type': 'audio/ogg; codecs=opus',
      'media_filename': 'v.ogg',
      'duration': 14,
      'created_at': '2026-08-31T07:42:10Z',
    });
    final audio = voice.content as AudioMessageContent;
    expect(audio.duration, const Duration(seconds: 14));
    expect(audio.waveform.length, 14);
    expect(voice.fallbackLabel, contains('0:14'));

    final pdf = mapper.fromTimeline({
      'id': 505,
      'event_type': 'agent_reply',
      'description': 'Form attached',
      'is_from_customer': false,
      'media_url': 'https://x/f.pdf',
      'media_type': 'application/pdf',
      'media_filename': 'f.pdf',
      'created_at': '2026-08-31T07:43:00Z',
    });
    expect(pdf.content, isA<DocumentMessageContent>());

    final video = mapper.fromTimeline({
      'id': 507,
      'event_type': 'customer_message',
      'description': 'clip',
      'is_from_customer': true,
      'media_url': 'https://x/c.mp4',
      'media_type': 'video/mp4',
      'media_filename': 'c.mp4',
      'created_at': '2026-08-31T07:44:50Z',
    });
    expect(video.content, isA<VideoMessageContent>());
  });

  test('maps internal note to system content', () {
    final m = mapper.fromTimeline({
      'id': 508,
      'event_type': 'note',
      'description': 'Internal Note: verified',
      'is_from_customer': false,
      'created_at': '2026-08-31T07:45:00Z',
    });
    expect(m.sender, MessageSender.system);
    expect(m.content, isA<SystemMessageContent>());
  });

  test('maps lifecycle rows to system content, not chat bubbles', () {
    for (final type in ['agent_notified', 'assigned', 'status_changed']) {
      final m = mapper.fromTimeline({
        'id': 900,
        'event_type': type,
        'description': type == 'agent_notified' ? 'agent_notified:5' : 'Reassigned to Alice Agent. SLA clock reset.',
        'is_from_customer': false,
        'created_at': '2026-09-03T12:29:12+03:00',
      });
      expect(m.sender, MessageSender.system, reason: type);
      expect(m.content, isA<SystemMessageContent>(), reason: type);
    }
  });

  test('summary prefers latest_message + unread + avatar', () {
    final thread = mapper.summaryToThread({
      'id': 14,
      'subject': 'WhatsApp: Account',
      'status': 'open',
      'display_number': '#TKT-14',
      'updated_at': '2026-08-31T07:45:12Z',
      'customer': {
        'id': 88,
        'name': 'David Mwangi',
        'phone_number': '+254700000000',
        'avatar_url': 'https://x/a.jpg',
      },
      'latest_message': {'body': 'How much?'},
      'unread_messages_count': 3,
    });
    expect(thread.conversation.preview, 'How much?');
    expect(thread.conversation.unreadCount, 3);
    expect(thread.conversation.avatarUrl, 'https://x/a.jpg');
    expect(thread.conversation.ticketId, '#TKT-14');
  });
}
