import 'dart:async';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/auth_session_controller.dart';
import 'ticket_api_repository.dart';
import 'ticket_store.dart';

export 'ticket_api_repository.dart';
export 'ticket_store.dart';

part 'tickets_page_model.g.dart';

class TicketsPageState {
  const TicketsPageState({
    this.filterOptions = const TicketFilterOptions(),
    this.tickets = const [],
    this.selectedStatus,
    this.selectedSource,
    this.selectedPriority,
    this.selectedDepartmentId,
    this.selectedCategoryId,
    this.selectedAssignment = 'me',
    this.period,
    this.fromDate,
    this.toDate,
    this.searchActive = false,
    this.query = '',
    this.page = 0,
    this.lastPage = 1,
    this.total = 0,
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.hasLoaded = false,
    this.filterError,
  });

  final TicketFilterOptions filterOptions;
  final List<TicketRecord> tickets;
  final String? selectedStatus;
  final String? selectedSource;
  final String? selectedPriority;
  final String? selectedDepartmentId;
  final String? selectedCategoryId;
  final String? selectedAssignment;
  final String? period;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool searchActive;
  final String query;
  final int page;
  final int lastPage;
  final int total;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final bool hasLoaded;
  final String? filterError;

  bool get hasMore => page < lastPage;
  bool get isEmpty => hasLoaded && tickets.isEmpty && error == null;
  String subtitleFor(List<TicketRecord> _) =>
      loading && tickets.isEmpty ? 'Loading tickets' : '$total tickets';
  bool get filtersActive =>
      selectedStatus != null ||
      selectedSource != null ||
      selectedPriority != null ||
      selectedDepartmentId != null ||
      selectedCategoryId != null ||
      selectedAssignment != null && selectedAssignment != 'me' ||
      (period != null && period != 'all') ||
      fromDate != null ||
      toDate != null;

  TicketsPageState copyWith({
    TicketFilterOptions? filterOptions,
    List<TicketRecord>? tickets,
    Object? selectedStatus = _keep,
    Object? selectedSource = _keep,
    Object? selectedPriority = _keep,
    Object? selectedDepartmentId = _keep,
    Object? selectedCategoryId = _keep,
    Object? selectedAssignment = _keep,
    Object? period = _keep,
    Object? fromDate = _keep,
    Object? toDate = _keep,
    bool? searchActive,
    String? query,
    int? page,
    int? lastPage,
    int? total,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    Object? error = _keep,
    bool? hasLoaded,
    Object? filterError = _keep,
  }) =>
      TicketsPageState(
        filterOptions: filterOptions ?? this.filterOptions,
        tickets: tickets ?? this.tickets,
        selectedStatus: identical(selectedStatus, _keep)
            ? this.selectedStatus
            : selectedStatus as String?,
        selectedSource: identical(selectedSource, _keep)
            ? this.selectedSource
            : selectedSource as String?,
        selectedPriority: identical(selectedPriority, _keep)
            ? this.selectedPriority
            : selectedPriority as String?,
        selectedDepartmentId: identical(selectedDepartmentId, _keep)
            ? this.selectedDepartmentId
            : selectedDepartmentId as String?,
        selectedCategoryId: identical(selectedCategoryId, _keep)
            ? this.selectedCategoryId
            : selectedCategoryId as String?,
        selectedAssignment: identical(selectedAssignment, _keep)
            ? this.selectedAssignment
            : selectedAssignment as String?,
        period: identical(period, _keep) ? this.period : period as String?,
        fromDate:
            identical(fromDate, _keep) ? this.fromDate : fromDate as DateTime?,
        toDate: identical(toDate, _keep) ? this.toDate : toDate as DateTime?,
        searchActive: searchActive ?? this.searchActive,
        query: query ?? this.query,
        page: page ?? this.page,
        lastPage: lastPage ?? this.lastPage,
        total: total ?? this.total,
        loading: loading ?? this.loading,
        refreshing: refreshing ?? this.refreshing,
        loadingMore: loadingMore ?? this.loadingMore,
        error: identical(error, _keep) ? this.error : error as String?,
        hasLoaded: hasLoaded ?? this.hasLoaded,
        filterError: identical(filterError, _keep)
            ? this.filterError
            : filterError as String?,
      );

  static const _keep = Object();
}

@Riverpod(keepAlive: true)
class TicketsPageNotifier extends _$TicketsPageNotifier {
  static const pageSize = 20;
  int _generation = 0;
  CancelToken? _activeRequest;
  Timer? _searchDebounce;
  String? _sessionScope;

  @override
  TicketsPageState build() {
    final auth = ref.watch(authSessionControllerProvider);
    final scope =
        '${auth.session?.user.id ?? 'anonymous'}:${auth.session?.user.activeWorkspace?.id ?? 'none'}';
    if (_sessionScope != null && _sessionScope != scope) {
      _generation++;
      _activeRequest?.cancel('Ticket workspace changed.');
      _searchDebounce?.cancel();
    }
    _sessionScope = scope;
    ref.onDispose(() {
      _searchDebounce?.cancel();
      _activeRequest?.cancel('Tickets page disposed.');
    });
    return const TicketsPageState();
  }

  Future<void> load() async {
    if (state.loading || state.hasLoaded) return;
    final generation = ++_generation;
    state = state.copyWith(loading: true, error: null, filterError: null);
    try {
      final filters = await ref.read(ticketsRepositoryProvider).filters(
        onCached: (cached) {
          if (generation == _generation) {
            state = state.copyWith(filterOptions: cached);
          }
        },
      );
      if (generation != _generation) return;
      final defaultStatus = filters.statuses.any((item) => item.value == 'open')
          ? 'open'
          : filters.statuses.isEmpty
              ? null
              : filters.statuses.first.value;
      state =
          state.copyWith(filterOptions: filters, selectedStatus: defaultStatus);
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(filterError: _message(error));
    }
    try {
      final page = await ref.read(ticketsRepositoryProvider).list(
        _query(page: 1),
        onCached: (cached) {
          if (generation == _generation) _publishPage(cached, replace: true);
        },
      );
      if (generation != _generation) return;
      _publishPage(page, replace: true);
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        loadingMore: false,
        hasLoaded: true,
        error: _message(error),
      );
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(
      refreshing: state.tickets.isNotEmpty,
      loading: state.tickets.isEmpty,
      error: null,
    );
    await _fetch(page: 1, replace: true);
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, error: null);
    await _fetch(page: state.page + 1, replace: false);
  }

  Future<void> retry() => state.hasLoaded ? refresh() : load();

  void setSearchQuery(String value) {
    state = state.copyWith(query: value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_applyQuery());
    });
  }

  void openSearch() => state = state.copyWith(searchActive: true);
  void closeSearch() {
    state = state.copyWith(searchActive: false, query: '');
    unawaited(_applyQuery());
  }

  void selectStatus(String? value) {
    state = state.copyWith(selectedStatus: value);
    unawaited(_applyQuery());
  }

  Future<void> applyFilters({
    String? status,
    String? source,
    String? priority,
    String? departmentId,
    String? categoryId,
    String? assignment,
    String? period,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearDates = false,
  }) async {
    state = state.copyWith(
      selectedStatus: status,
      selectedSource: source,
      selectedPriority: priority,
      selectedDepartmentId: departmentId,
      selectedCategoryId: categoryId,
      selectedAssignment: assignment,
      period: period,
      fromDate: clearDates ? null : fromDate,
      toDate: clearDates ? null : toDate,
    );
    await _applyQuery();
  }

  void clearFilters() {
    state = state.copyWith(
      selectedStatus: null,
      selectedSource: null,
      selectedPriority: null,
      selectedDepartmentId: null,
      selectedCategoryId: null,
      selectedAssignment: 'me',
      period: null,
      fromDate: null,
      toDate: null,
    );
    unawaited(_applyQuery());
  }

  Future<void> changeStatus(String ticketId, String status) async {
    try {
      await ref.read(ticketsRepositoryProvider).updateStatus(ticketId, status);
      await refresh();
    } catch (error) {
      state = state.copyWith(error: _message(error));
      rethrow;
    }
  }

  Future<void> _applyQuery() async {
    state = state.copyWith(
      loading: state.tickets.isEmpty,
      refreshing: state.tickets.isNotEmpty,
      error: null,
    );
    await _fetch(page: 1, replace: true);
  }

  Future<void> _fetch({required int page, required bool replace}) async {
    _activeRequest?.cancel('Superseded by a newer ticket query.');
    final token = CancelToken();
    _activeRequest = token;
    final generation = ++_generation;
    try {
      final result = await ref.read(ticketsRepositoryProvider).list(
        _query(page: page),
        cancelToken: token,
        onCacheMiss: () {
          if (generation == _generation && state.tickets.isEmpty) {
            state = state.copyWith(loading: true);
          }
        },
        onCached: (cached) {
          if (generation == _generation) {
            _publishPage(cached, replace: replace, cached: true);
          }
        },
      );
      if (generation != _generation) return;
      _publishPage(result, replace: replace);
    } catch (error) {
      if (error is DioException && CancelToken.isCancel(error)) return;
      if (generation != _generation) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        loadingMore: false,
        error: _message(error),
        hasLoaded: true,
      );
    }
  }

  void _publishPage(TicketPageResult result,
      {required bool replace, bool cached = false}) {
    final rows = switch (state.selectedStatus) {
      'overdue' => result.tickets
          .where((ticket) => ticket.isOverdue || ticket.statusRaw == 'overdue')
          .toList(growable: false),
      'escalated' => result.tickets
          .where((ticket) => ticket.statusRaw == 'escalated')
          .toList(growable: false),
      _ => result.tickets,
    };
    state = state.copyWith(
      tickets: replace ? rows : _merge(state.tickets, rows),
      page: result.page,
      lastPage: result.lastPage,
      total: state.selectedStatus == 'overdue' ||
              state.selectedStatus == 'escalated'
          ? rows.length
          : result.total,
      loading: false,
      refreshing: cached,
      loadingMore: false,
      error: null,
      hasLoaded: true,
    );
  }

  TicketQuery _query({required int page}) => TicketQuery(
        search: state.query,
        status: state.selectedStatus == 'overdue' ||
                state.selectedStatus == 'escalated'
            ? null
            : state.selectedStatus,
        source: state.selectedSource,
        priority: state.selectedPriority,
        categoryId: state.selectedCategoryId,
        departmentId: state.selectedDepartmentId,
        assignment: state.selectedAssignment,
        period: state.period,
        fromDate: state.fromDate,
        toDate: state.toDate,
        page: page,
        perPage: pageSize,
      );

  List<TicketRecord> _merge(
      List<TicketRecord> current, List<TicketRecord> next) {
    final byId = <String, TicketRecord>{for (final t in current) t.id: t};
    for (final ticket in next) {
      byId[ticket.id] = ticket;
    }
    return byId.values.toList(growable: false);
  }

  String _message(Object error) => error is FormatException
      ? 'The server returned ticket data in an unexpected format.'
      : error.toString().replaceFirst('Exception: ', '');
}
