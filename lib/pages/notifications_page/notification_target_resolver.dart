import 'notifications_models.dart';

String notificationRoute(AppNotification notification) {
  final id = notification.ticketId;
  final type = notification.type.toLowerCase();
  if (type == 'ticket_assigned' ||
      type == 'assignment' ||
      type == 'sla_breach') {
    return id == null ? '/tickets' : '/tickets/$id';
  }
  switch (notification.source) {
    case 'whatsapp':
      return id == null ? '/chats' : '/chats/whatsapp/$id';
    case 'email':
      return id == null ? '/email' : '/email/$id';
    case 'phone':
      return '/phone';
    default:
      return id == null ? '/tickets' : '/tickets/$id';
  }
}
