import 'package:intl/intl.dart';

import '../../../pages/conversation_room_page/conversation_room_page_model.dart';

/// Full-fidelity mapping from backend timeline rows to UI messages.
///
/// Covers the production contract: quoted replies (`quoted_message_text`,
/// `parent_id`), media (`media_url/type/filename`), voice-note `duration`,
/// agent attribution (`user`), read/delivery (`message_status`),
/// and customer avatar. Realtime payloads are often partial — every accessor
/// degrades gracefully to text/unsupported.
class WhatsAppMessageMapper {
  const WhatsAppMessageMapper();

  ConversationMessage fromTimeline(Map<String, dynamic> value) {
    final fromCustomer = value['is_from_customer'] == true;
    final eventType = str(value['event_type'], fallback: 'customer_message');
    final rawId = value['timeline_id'] ?? value['id'] ?? '';
    final id = '$rawId';
    final createdAt = _parseDate(value['created_at']) ?? DateTime.now();

    final mediaUrl = strOrNull(value['media_url']);
    final mediaType = str(value['media_type']).toLowerCase();
    final mediaFilename = str(value['media_filename'], fallback: 'Attachment');
    final text = str(value['description']);
    final quotedText = strOrNull(value['quoted_message_text']);
    final quotedSender = strOrNull(value['quoted_sender_name']);
    final parentRaw = value['parent_id'];
    final parentId = parentRaw == null ? null : '$parentRaw';
    final agentName = _agentName(value);
    final avatarUrl = strOrNull(value['customer_avatar_url']);
    final durationSecs = _durationSeconds(value);

    ConversationMessageContent content;
    if (eventType == 'note' || _isSystemEvent(eventType)) {
      content = SystemMessageContent(
        _systemLabel(eventType, text),
        emphasized: eventType != 'note',
      );
    } else if (mediaUrl == null || mediaUrl.isEmpty) {
      content = text.isEmpty
          ? const UnsupportedMessageContent(
              'Message content is unavailable for this entry.')
          : TextMessageContent(text);
    } else if (mediaType.startsWith('image/')) {
      content = ImageMessageContent(
        assetPath: mediaUrl,
        caption: text.isEmpty ? null : text,
      );
    } else if (mediaType.startsWith('video/')) {
      content = VideoMessageContent(
        assetPath: mediaUrl,
        thumbnailAssetPath: mediaUrl,
        duration: Duration(seconds: durationSecs ?? 0),
        caption: text.isEmpty ? null : text,
      );
    } else if (mediaType.startsWith('audio/')) {
      final label = text.isEmpty
          ? 'Voice message (${_formatDuration(durationSecs)})'
          : text;
      content = AudioMessageContent(
        assetPath: mediaUrl,
        duration: Duration(seconds: durationSecs ?? 0),
        waveform: _waveformFor(id, durationSecs),
      );
      return ConversationMessage(
        id: id.isEmpty ? 'unknown' : id,
        sender: fromCustomer ? MessageSender.customer : MessageSender.agent,
        sentAt: createdAt,
        content: content,
        delivery: _delivery(value, fromCustomer),
        replyToId: parentId,
        quotedText: quotedText,
        quotedSenderName: quotedSender,
        agentName: agentName,
        customerAvatarUrl: avatarUrl,
        fallbackLabel: label,
      );
    } else {
      content = DocumentMessageContent(
        assetPath: mediaUrl,
        fileName: mediaFilename,
        mimeType: mediaType.isEmpty ? 'file' : mediaType,
        sizeLabel: str(value['size_label'], fallback: _sizeLabelFor(mediaType)),
      );
    }

    return ConversationMessage(
      id: id.isEmpty ? 'unknown' : id,
      sender: eventType == 'note' || _isSystemEvent(eventType)
          ? MessageSender.system
          : (fromCustomer ? MessageSender.customer : MessageSender.agent),
      sentAt: createdAt,
      content: content,
      delivery: _delivery(value, fromCustomer),
      replyToId: parentId,
      quotedText: quotedText,
      quotedSenderName: quotedSender,
      agentName: agentName,
      customerAvatarUrl: avatarUrl,
    );
  }

  /// Inbox row -> thread summary. Prefers `latest_message` + unread counters
  /// when the backend supplies them; falls back to subject/category.
  ConversationThread summaryToThread(Map<String, dynamic> value) {
    final customer = _map(value['customer']);
    final rawStatus = str(value['status'], fallback: 'open');
    final customerName = str(customer['name'], fallback: 'Customer');
    final updated = _parseDate(value['updated_at']) ??
        _parseDate(value['created_at']) ??
        DateTime.now();
    final subject = str(value['subject'], fallback: 'No messages yet');
    final latest = _map(value['latest_message']);
    final preview =
        latest.isNotEmpty ? str(latest['body'], fallback: subject) : subject;
    final unread = _int(value['unread_messages_count']) ??
        _int(value['unread_count']) ??
        0;
    // `display_id` is the user-facing ticket reference (for example
    // `DGKSL-439`). Keep `display_number` only as a backwards-compatible
    // fallback for older API responses.
    final displayNumber =
        strOrNull(value['display_id']) ?? strOrNull(value['display_number']);

    final conversation = ChatConversation(
      id: '${value['id']}',
      channel: ChatChannel.whatsapp,
      type: _isGroup(value)
          ? ChatConversationType.groups
          : ChatConversationType.dms,
      status: rawStatus == 'resolved' || rawStatus == 'closed'
          ? ChatConversationStatus.resolved
          : ChatConversationStatus.open,
      name: customerName,
      preview: preview,
      time: DateFormat.Hm().format(updated.toLocal()),
      avatar: customerName.isEmpty ? null : customerName[0].toUpperCase(),
      avatarUrl: strOrNull(customer['avatar_url']),
      customerId: customer['id']?.toString(),
      contactIdentifier: strOrNull(customer['phone_number']),
      unreadCount: unread,
      ticketId: displayNumber,
    );
    return ConversationThread(
      conversation: conversation,
      messages: const [],
      summary: str(value['description'], fallback: str(value['category'])),
    );
  }

  String? _agentName(Map<String, dynamic> value) {
    final user = value['user'];
    if (user is Map) {
      final name = strOrNull(user['name']);
      if (name != null) return name;
    }
    return null;
  }

  bool _isGroup(Map<String, dynamic> value) {
    final explicit = value['is_group'] ?? value['isGroup'];
    if (explicit is bool) return explicit;
    final subject = str(value['subject']).toLowerCase();
    final category = str(value['category']).toLowerCase();
    return subject.contains('group:') ||
        subject.startsWith('whatsapp group') ||
        category == 'group';
  }

  MessageDelivery _delivery(Map<String, dynamic> value, bool fromCustomer) {
    if (fromCustomer) return MessageDelivery.none;
    final status = str(value['message_status']).toLowerCase();
    return switch (status) {
      'read' => MessageDelivery.read,
      'delivered' => MessageDelivery.delivered,
      'sent' => MessageDelivery.sent,
      'failed' => MessageDelivery.failed,
      _ => str(value['event_type']) == 'note' ||
              _isSystemEvent(str(value['event_type']))
          ? MessageDelivery.none
          : MessageDelivery.sent,
    };
  }

  /// Backend emits lifecycle rows (`agent_notified`, `assigned`,
  /// `status_changed`, …) that are not chat content — render them as
  /// centered system rows instead of customer/agent bubbles.
  static bool _isSystemEvent(String eventType) => switch (eventType) {
        'customer_message' || 'agent_reply' || 'note' || '' => false,
        _ => true,
      };

  static String _systemLabel(String eventType, String text) {
    if (text.trim().isNotEmpty) {
      if (eventType == 'agent_notified') return 'Agent notified';
      return text;
    }
    return switch (eventType) {
      'agent_notified' => 'Agent notified',
      'assigned' => 'Ticket reassigned',
      _ => 'Timeline updated',
    };
  }

  int? _durationSeconds(Map<String, dynamic> value) {
    for (final key in ['duration', 'duration_seconds', 'audio_duration']) {
      final parsed = _int(value[key]);
      if (parsed != null) return parsed;
    }
    final metadata = value['metadata'];
    if (metadata is Map) {
      final parsed = _int(metadata['duration']);
      if (parsed != null) return parsed;
    }
    final formatted = value['formatted_duration'];
    if (formatted is String && formatted.contains(':')) {
      final parts = formatted.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0].trim()) ?? 0;
        final s = int.tryParse(parts[1].trim()) ?? 0;
        return m * 60 + s;
      }
    }
    return null;
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '0:00';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  List<double> _waveformFor(String id, int? durationSecs) {
    var seed = id.hashCode.abs();
    final length = (durationSecs ?? 8).clamp(8, 32);
    return List<double>.generate(length, (_) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return 0.2 + (seed % 80) / 100.0;
    });
  }

  String _sizeLabelFor(String mediaType) {
    if (mediaType.startsWith('audio/')) return 'Voice note';
    if (mediaType.startsWith('image/')) return 'Image';
    if (mediaType.startsWith('video/')) return 'Video';
    if (mediaType.contains('pdf')) return 'PDF';
    return 'Attachment';
  }

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, item) => MapEntry('$key', item))
      : <String, dynamic>{};

  static String str(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final s = '$value'.trim();
    if (s.isEmpty || s == 'null') return fallback;
    return s;
  }

  static String? strOrNull(dynamic value) {
    if (value == null) return null;
    final s = '$value'.trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }

  static int? _int(dynamic value) {
    if (value is num) return value.toInt();
    if (value == null) return null;
    return int.tryParse('$value'.trim());
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse('$value');
  }
}
