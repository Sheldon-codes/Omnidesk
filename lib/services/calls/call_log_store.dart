import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_api.dart';
import 'call_models.dart';

/// Server-backed call history. This owns paging and refresh lifecycle; Phone
/// only projects these typed records into its existing row UI.
class CallLogState {
  const CallLogState({
    this.records = const [],
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.page = 0,
    this.hasMore = true,
  });

  final List<CallLogRecord> records;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final int page;
  final bool hasMore;

  CallLogState copyWith({
    List<CallLogRecord>? records,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    Object? error = _keep,
    int? page,
    bool? hasMore,
  }) =>
      CallLogState(
        records: records ?? this.records,
        loading: loading ?? this.loading,
        refreshing: refreshing ?? this.refreshing,
        loadingMore: loadingMore ?? this.loadingMore,
        error: identical(error, _keep) ? this.error : error as String?,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
      );

  static const _keep = Object();
}

final callLogStoreProvider =
    NotifierProvider<CallLogStore, CallLogState>(CallLogStore.new);

class CallLogStore extends Notifier<CallLogState> {
  var _generation = 0;

  @override
  CallLogState build() {
    unawaited(Future<void>.delayed(Duration.zero, refresh));
    return const CallLogState(loading: true);
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    state = state.copyWith(
      loading: state.records.isEmpty,
      refreshing: state.records.isNotEmpty,
      error: null,
    );
    try {
      final result = await ref.read(callApiProvider).getCallLogs(page: 1);
      if (!ref.mounted || generation != _generation) return;
      state = CallLogState(
        records: result.records,
        page: result.page,
        hasMore: result.hasMore,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: _messageFor(error),
      );
    }
  }

  Future<void> loadMore() async {
    if (!ref.mounted) return;
    if (state.loading ||
        state.refreshing ||
        state.loadingMore ||
        !state.hasMore) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(loadingMore: true, error: null);
    try {
      final result =
          await ref.read(callApiProvider).getCallLogs(page: state.page + 1);
      if (!ref.mounted || generation != _generation) return;
      final ids = state.records.map((record) => record.id).toSet();
      state = state.copyWith(
        records: [
          ...state.records,
          ...result.records.where((record) => ids.add(record.id)),
        ],
        page: result.page,
        hasMore: result.hasMore,
        loadingMore: false,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(loadingMore: false, error: _messageFor(error));
    }
  }

  String _messageFor(Object error) => error is CallApiException
      ? error.message
      : error is FormatException
          ? 'The call history service returned invalid data. Please try again.'
          : 'Unable to load recent calls. Please try again.';
}
