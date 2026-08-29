import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../customer_editor_page/customer_editor_page_model.dart';
import '../tickets_page/tickets_page_model.dart';

part 'customer_details_page_model.g.dart';

enum CustomerActivityChannel { call, chat, email, ticket }

class CustomerDetailTicket {
  const CustomerDetailTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    required this.department,
    this.category,
  });

  final String id;
  final String subject;
  final TicketStatus status;
  final TicketPriority priority;
  final String department;
  final String? category;
}

class CustomerActivity {
  const CustomerActivity({
    required this.channel,
    required this.title,
    required this.timestamp,
    this.preview,
    this.duration,
    this.ticketId,
  });

  final CustomerActivityChannel channel;
  final String title;
  final String timestamp;
  final String? preview;
  final String? duration;
  final String? ticketId;
}

class CustomerDetailState {
  const CustomerDetailState({
    required this.customerId,
    this.customer,
    this.tickets = const [],
    this.activities = const [],
    this.loading = false,
  });

  final String customerId;
  final CustomerRecord? customer;
  final List<CustomerDetailTicket> tickets;
  final List<CustomerActivity> activities;
  final bool loading;

  bool get notFound => !loading && customer == null;
}

@riverpod
class CustomerDetailNotifier extends _$CustomerDetailNotifier {
  @override
  CustomerDetailState build({required String customerId}) {
    final customer = ref
        .watch(customersStoreProvider)
        .where((item) => item.id == customerId)
        .firstOrNull;
    return CustomerDetailState(
      customerId: customerId,
      customer: customer,
      tickets: _ticketFixtures[customerId] ?? const [],
      activities: _activityFixtures[customerId] ?? const [],
    );
  }
}

const _ticketFixtures = <String, List<CustomerDetailTicket>>{
  'nana': [
    CustomerDetailTicket(
      id: 'DGKSL-376',
      subject: 'Good morning Hillary',
      status: TicketStatus.open,
      priority: TicketPriority.low,
      department: 'General',
      category: 'Technical support',
    ),
  ],
  'caller-1967': [
    CustomerDetailTicket(
      id: 'DGKSL-378',
      subject: 'Technical support call from caller 1967',
      status: TicketStatus.overdue,
      priority: TicketPriority.medium,
      department: 'General',
      category: 'Technical support',
    ),
  ],
};

const _activityFixtures = <String, List<CustomerActivity>>{
  'nana': [
    CustomerActivity(
      channel: CustomerActivityChannel.call,
      title: 'Incoming call',
      timestamp: 'Today · 10:42',
      duration: '3m 24s',
    ),
    CustomerActivity(
      channel: CustomerActivityChannel.chat,
      title: 'WhatsApp',
      preview: 'Good morning Hillary',
      timestamp: 'Today · 09:31',
      ticketId: 'DGKSL-376',
    ),
    CustomerActivity(
      channel: CustomerActivityChannel.email,
      title: 'Requisition approval required',
      timestamp: 'Yesterday · 16:20',
    ),
  ],
  'caller-1967': [
    CustomerActivity(
      channel: CustomerActivityChannel.call,
      title: 'Missed call',
      timestamp: 'Today · 09:50',
      ticketId: 'DGKSL-378',
    ),
  ],
};
