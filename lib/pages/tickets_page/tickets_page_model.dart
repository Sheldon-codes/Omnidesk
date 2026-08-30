import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'ticket_store.dart';

export 'ticket_store.dart';

part 'tickets_page_model.g.dart';

class TicketsPageState {
  TicketsPageState({
    this.selectedStatus = TicketStatus.open,
    this.priorities = const {},
    this.departments = const {},
    this.categories = const {},
    this.searchActive = false,
    this.query = '',
    List<TicketRecord>? tickets,
  }) : tickets = tickets ?? ticketFixtures;

  final TicketStatus? selectedStatus;
  final Set<TicketPriority> priorities;
  final Set<String> departments;
  final Set<String> categories;
  final bool searchActive;
  final String query;
  final List<TicketRecord> tickets;

  String subtitleFor(List<TicketRecord> tickets) => '7 open · 2 overdue';

  bool get filtersActive =>
      selectedStatus != TicketStatus.open ||
      priorities.isNotEmpty ||
      departments.isNotEmpty ||
      categories.isNotEmpty;

  List<TicketRecord> filteredTicketsFor(List<TicketRecord> tickets) {
    final normalized = query.trim().toLowerCase();
    return tickets.where((ticket) {
      if (ticket.deleted ||
          (selectedStatus != null && ticket.status != selectedStatus)) {
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
        ticket.customerLabel,
        ticket.sourceActor,
        ticket.contactIdentifier ?? '',
        ticket.department,
        ticket.category ?? '',
        ticket.sla ?? '',
        ticket.source.label,
      ].any((value) => value.toLowerCase().contains(normalized));
    }).toList(growable: false);
  }

  List<TicketRecord> get filteredTickets => filteredTicketsFor(tickets);

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

@riverpod
class TicketsPageNotifier extends _$TicketsPageNotifier {
  @override
  TicketsPageState build() => TicketsPageState();
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
