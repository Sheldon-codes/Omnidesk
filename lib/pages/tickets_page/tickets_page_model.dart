import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tickets_page_model.g.dart';

enum TicketStatus { open, inProgress, overdue, escalated, resolved }

enum TicketPriority { low, medium, high }

enum TicketSource { widget, call, whatsapp, email }

class TicketRecord {
  const TicketRecord({
    required this.id,
    required this.subject,
    required this.customer,
    required this.source,
    required this.status,
    required this.priority,
    required this.department,
    this.category,
    this.sla,
    this.contactIdentifier,
  });

  final String id;
  final String subject;
  final String customer;
  final TicketSource source;
  final TicketStatus status;
  final TicketPriority priority;
  final String department;
  final String? category;
  final String? sla;
  final String? contactIdentifier;
}

class TicketsPageState {
  const TicketsPageState({
    this.selectedStatus = TicketStatus.open,
    this.priorities = const {},
    this.departments = const {},
    this.categories = const {},
    this.searchActive = false,
    this.query = '',
    this.tickets = _ticketFixtures,
  });

  final TicketStatus? selectedStatus;
  final Set<TicketPriority> priorities;
  final Set<String> departments;
  final Set<String> categories;
  final bool searchActive;
  final String query;
  final List<TicketRecord> tickets;

  String get subtitle => '7 open · 2 overdue';
  bool get filtersActive =>
      selectedStatus != TicketStatus.open ||
      priorities.isNotEmpty ||
      departments.isNotEmpty ||
      categories.isNotEmpty;

  List<TicketRecord> get filteredTickets {
    final normalized = query.trim().toLowerCase();
    return tickets.where((ticket) {
      if (selectedStatus != null && ticket.status != selectedStatus) {
        return false;
      }
      if (priorities.isNotEmpty && !priorities.contains(ticket.priority)) {
        return false;
      }
      if (departments.isNotEmpty && !departments.contains(ticket.department)) {
        return false;
      }
      if (categories.isNotEmpty &&
          !categories.contains(ticket.category ?? '')) {
        return false;
      }
      if (normalized.isEmpty) return true;
      return [
        ticket.id,
        ticket.subject,
        ticket.customer,
        ticket.contactIdentifier ?? '',
        ticket.department,
        ticket.category ?? '',
        ticket.sla ?? '',
        ticket.source.name
      ].any((value) => value.toLowerCase().contains(normalized));
    }).toList(growable: false);
  }

  TicketsPageState copyWith({
    Object? selectedStatus = _keep,
    Set<TicketPriority>? priorities,
    Set<String>? departments,
    Set<String>? categories,
    bool? searchActive,
    String? query,
  }) =>
      TicketsPageState(
        selectedStatus: identical(selectedStatus, _keep)
            ? this.selectedStatus
            : selectedStatus as TicketStatus?,
        priorities: priorities ?? this.priorities,
        departments: departments ?? this.departments,
        categories: categories ?? this.categories,
        searchActive: searchActive ?? this.searchActive,
        query: query ?? this.query,
        tickets: tickets,
      );

  static const _keep = Object();
}

const _ticketFixtures = <TicketRecord>[
  TicketRecord(
      id: 'DGKSL-392',
      subject: 'Widget AI: How do I create a payroll',
      customer: 'Phyllis',
      source: TicketSource.widget,
      status: TicketStatus.open,
      priority: TicketPriority.low,
      department: 'General',
      category: 'Accounting',
      sla: 'SLA 2h 10m',
      contactIdentifier: 'phyllis@example.com'),
  TicketRecord(
      id: 'DGKSL-388',
      subject: 'Billing-and-payments call from +254…',
      customer: 'Sharon Dreams Mosop',
      source: TicketSource.call,
      status: TicketStatus.inProgress,
      priority: TicketPriority.medium,
      department: 'Finance',
      category: 'Billing and payments',
      sla: 'SLA 17h',
      contactIdentifier: '+254722161652'),
  TicketRecord(
      id: 'DGKSL-378',
      subject: 'Technical-support call from +254…',
      customer: 'Deborah Hekima',
      source: TicketSource.call,
      status: TicketStatus.overdue,
      priority: TicketPriority.medium,
      department: 'General',
      category: 'Technical support',
      sla: 'Overdue by 35m',
      contactIdentifier: '+254720261967'),
  TicketRecord(
      id: 'DGKSL-376',
      subject: 'Good morning Hillary',
      customer: 'Raphael Sunshine',
      source: TicketSource.whatsapp,
      status: TicketStatus.open,
      priority: TicketPriority.low,
      department: 'General',
      contactIdentifier: '+254719106280'),
  TicketRecord(
      id: 'DGKSL-373',
      subject: 'Fee balances are not showing',
      customer: 'Nana Betterstream',
      source: TicketSource.whatsapp,
      status: TicketStatus.escalated,
      priority: TicketPriority.high,
      department: 'Finance',
      category: 'Accounting',
      sla: 'SLA 1h 20m',
      contactIdentifier: '+254719106280'),
  TicketRecord(
      id: 'DGKSL-360',
      subject: 'Requisition approval required',
      customer: 'MOI HIGH SCHOOL-KABARAK',
      source: TicketSource.email,
      status: TicketStatus.resolved,
      priority: TicketPriority.high,
      department: 'Finance',
      category: 'Billing and payments',
      contactIdentifier: 'accounts@bigbrainz.co.ke'),
  TicketRecord(
      id: 'DGKSL-356',
      subject: 'Teacher accounts for Sunshine Primary',
      customer: 'Tony Kirui Sunshine',
      source: TicketSource.email,
      status: TicketStatus.resolved,
      priority: TicketPriority.medium,
      department: 'General',
      contactIdentifier: 'kirui-mac@gmail.com'),
];

@riverpod
class TicketsPageNotifier extends _$TicketsPageNotifier {
  @override
  TicketsPageState build() => const TicketsPageState();
  void selectStatus(TicketStatus? status) =>
      state = state.copyWith(selectedStatus: status);
  void openSearch() => state = state.copyWith(searchActive: true);
  void closeSearch() => state = state.copyWith(searchActive: false, query: '');
  void setSearchQuery(String value) => state = state.copyWith(query: value);
  void applyFilters(
          {TicketStatus? status,
          Set<TicketPriority>? priorities,
          Set<String>? departments,
          Set<String>? categories}) =>
      state = state.copyWith(
          selectedStatus: status,
          priorities: priorities,
          departments: departments,
          categories: categories);
  void clearFilters() => state = state.copyWith(
      selectedStatus: null,
      priorities: <TicketPriority>{},
      departments: <String>{},
      categories: <String>{});
}
