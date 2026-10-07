import 'dart:async';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/auth_session_controller.dart';
import '../customer_editor_page/customer_editor_page_model.dart';
import 'customer_repository.dart';

part 'customers_page_model.g.dart';

class CustomersPageState {
  const CustomersPageState({
    this.customers = const [],
    this.search = '',
    this.page = 0,
    this.lastPage = 1,
    this.total = 0,
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.hasLoaded = false,
  });

  final List<CustomerRecord> customers;
  final String search;
  final int page;
  final int lastPage;
  final int total;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final bool hasLoaded;

  bool get hasMore => page < lastPage;
  bool get isEmpty => hasLoaded && customers.isEmpty && error == null;

  CustomersPageState copyWith({
    List<CustomerRecord>? customers,
    String? search,
    int? page,
    int? lastPage,
    int? total,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    Object? error = _keep,
    bool? hasLoaded,
  }) =>
      CustomersPageState(
        customers: customers ?? this.customers,
        search: search ?? this.search,
        page: page ?? this.page,
        lastPage: lastPage ?? this.lastPage,
        total: total ?? this.total,
        loading: loading ?? this.loading,
        refreshing: refreshing ?? this.refreshing,
        loadingMore: loadingMore ?? this.loadingMore,
        error: identical(error, _keep) ? this.error : error as String?,
        hasLoaded: hasLoaded ?? this.hasLoaded,
      );

  static const _keep = Object();
}

@Riverpod(keepAlive: true)
class CustomersPageNotifier extends _$CustomersPageNotifier {
  static const pageSize = 20;
  int _generation = 0;
  CancelToken? _activeRequest;
  String? _sessionScope;

  @override
  CustomersPageState build() {
    final auth = ref.read(authSessionControllerProvider);
    _sessionScope = _scopeFor(auth);
    ref.listen<AuthState>(authSessionControllerProvider, (_, next) {
      Future.microtask(() {
        if (ref.mounted) _handleScopeChange(next);
      });
    });
    ref.onDispose(() => _activeRequest?.cancel('Customer page disposed.'));
    // Keep the initial state idle: the page's post-frame load() starts the
    // request. Marking this true here makes load() mistake an unstarted fetch
    // for an in-flight one when auth was already restored at provider build.
    return const CustomersPageState();
  }

  void _handleScopeChange(AuthState auth) {
    final scope = _scopeFor(auth);
    if (scope == _sessionScope) return;
    final query = state.search;
    _sessionScope = scope;
    _generation++;
    _activeRequest?.cancel('Customer workspace changed.');
    state = CustomersPageState(search: query);
    if (auth.isAuthenticated) {
      unawaited(_fetch(page: 1, replace: true, initial: true));
    }
  }

  String _scopeFor(AuthState auth) =>
      '${auth.session?.user.id ?? 'anonymous'}:${auth.session?.user.activeWorkspace?.id ?? 'none'}';

  Future<void> load() async {
    if (state.loading || state.hasLoaded) return;
    await _fetch(page: 1, replace: true, initial: true);
  }

  Future<void> search(String value) async {
    final query = value.trim();
    if (query == state.search) return;
    state = state.copyWith(
      search: query,
      loading: state.customers.isEmpty,
      refreshing: state.customers.isNotEmpty,
      error: null,
    );
    await _fetch(page: 1, replace: true, initial: state.customers.isEmpty);
  }

  Future<void> refresh() async {
    state = state.copyWith(
        refreshing: state.customers.isNotEmpty,
        loading: state.customers.isEmpty,
        error: null);
    await _fetch(page: 1, replace: true, initial: state.customers.isEmpty);
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, error: null);
    await _fetch(page: state.page + 1, replace: false, initial: false);
  }

  Future<void> retry() => state.hasLoaded ? refresh() : load();

  void applyConfirmedUpdate(CustomerRecord customer) {
    if (!state.customers.any((item) => item.id == customer.id)) return;
    // A GET started before the PUT confirmation must not publish an older
    // version over the newly confirmed record.
    _generation++;
    _activeRequest?.cancel('Customer was updated.');
    state = state.copyWith(
      customers: [
        for (final item in state.customers)
          if (item.id == customer.id) customer else item,
      ],
    );
  }

  Future<void> _fetch(
      {required int page, required bool replace, required bool initial}) async {
    _activeRequest?.cancel('Superseded by a newer customer query.');
    final cancelToken = CancelToken();
    _activeRequest = cancelToken;
    final requestGeneration = ++_generation;
    final query = state.search;
    if (initial) {
      state = state.copyWith(
        loading: state.customers.isEmpty,
        refreshing: state.customers.isNotEmpty,
        error: null,
      );
    }
    try {
      final result = await ref.read(customerRepositoryProvider).list(
            search: query,
            page: page,
            perPage: pageSize,
            cancelToken: cancelToken,
            onCacheMiss: () {
              if (requestGeneration == _generation &&
                  query == state.search &&
                  state.customers.isEmpty) {
                state = state.copyWith(loading: true, error: null);
              }
            },
            onCached: (cached) {
              if (requestGeneration != _generation || query != state.search) {
                return;
              }
              ref
                  .read(customersStoreProvider.notifier)
                  .upsertAll(cached.customers);
              state = state.copyWith(
                customers: replace
                    ? cached.customers
                    : _merge(state.customers, cached.customers),
                page: cached.page,
                lastPage: cached.lastPage,
                total: cached.total,
                loading: false,
                refreshing: true,
                loadingMore: false,
                error: null,
                hasLoaded: true,
              );
            },
          );
      if (requestGeneration != _generation || query != state.search) return;
      final rows = replace
          ? result.customers
          : _merge(state.customers, result.customers);
      ref.read(customersStoreProvider.notifier).upsertAll(result.customers);
      state = state.copyWith(
        customers: rows,
        page: result.page,
        lastPage: result.lastPage,
        total: result.total,
        loading: false,
        refreshing: false,
        loadingMore: false,
        error: null,
        hasLoaded: true,
      );
    } catch (error) {
      if (error is DioException && CancelToken.isCancel(error)) return;
      if (requestGeneration != _generation) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        loadingMore: false,
        error: _message(error),
        hasLoaded: true,
      );
    }
  }

  List<CustomerRecord> _merge(
      List<CustomerRecord> current, List<CustomerRecord> next) {
    final rows = <String, CustomerRecord>{
      for (final row in current) row.id: row
    };
    for (final row in next) {
      rows[row.id] = row;
    }
    return rows.values.toList(growable: false);
  }

  String _message(Object error) => error is FormatException
      ? 'The server returned customer data in an unexpected format.'
      : error.toString().replaceFirst('Exception: ', '');
}
