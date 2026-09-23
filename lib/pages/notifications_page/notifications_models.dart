class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    required this.isRead,
    this.ticketId,
    this.source,
    this.priority,
    this.createdAt,
    this.timeAgo,
  });

  final String id;
  final String type;
  final String severity;
  final String title;
  final String body;
  final bool isRead;
  final String? ticketId;
  final String? source;
  final String? priority;
  final DateTime? createdAt;
  final String? timeAgo;

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        severity: severity,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        ticketId: ticketId,
        source: source,
        priority: priority,
        createdAt: createdAt,
        timeAgo: timeAgo,
      );

  factory AppNotification.fromJson(dynamic raw) {
    final json = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final id = '${json['id'] ?? ''}'.trim();
    if (id.isEmpty) throw const FormatException('Notification id missing.');
    return AppNotification(
      id: id,
      type: '${json['type'] ?? 'system'}',
      severity: '${json['severity'] ?? 'info'}',
      title: '${json['title'] ?? 'Notification'}',
      body: '${json['body'] ?? ''}',
      isRead: json['is_read'] == true || json['isRead'] == true,
      ticketId: json['ticket_id']?.toString(),
      source: json['source']?.toString(),
      priority: json['priority']?.toString(),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toUtc(),
      timeAgo: json['time_ago']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'severity': severity,
        'title': title,
        'body': body,
        'is_read': isRead,
        if (ticketId != null) 'ticket_id': ticketId,
        if (source != null) 'source': source,
        if (priority != null) 'priority': priority,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (timeAgo != null) 'time_ago': timeAgo,
      };
}

class NotificationFeed {
  const NotificationFeed({required this.items, required this.unreadCount});
  final List<AppNotification> items;
  final int unreadCount;

  Map<String, dynamic> toJson() => {
        'notifications': items.map((item) => item.toJson()).toList(),
        'unread_count': unreadCount,
      };

  factory NotificationFeed.fromJson(dynamic raw) {
    final json = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final values = json['notifications'];
    final items = values is List
        ? values.map(AppNotification.fromJson).toList(growable: false)
        : const <AppNotification>[];
    return NotificationFeed(
      items: items,
      unreadCount: int.tryParse('${json['unread_count'] ?? 0}') ?? 0,
    );
  }
}
