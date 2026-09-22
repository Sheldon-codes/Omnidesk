import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_api.dart';
import 'call_models.dart';
import '../auth_session_controller.dart';
import '../response_cache.dart';

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
  String? _scopeKey;

  @override
  CallLogState build() {
    ref.listen(authSessionControllerProvider, (_, next) {
      Future.microtask(() {
        if (ref.mounted) _handleScopeChange(next);
      });
    }, fireImmediately: true);
    return const CallLogState(loading: true);
  }

  void _handleScopeChange(AuthState auth) {
    final next = auth.session == null
        ? 'anonymous'
        : '${auth.session!.user.id}:${auth.session!.user.activeWorkspace?.id ?? 'none'}';
    if (next == _scopeKey) return;
    final hadScope = _scopeKey != null;
    _scopeKey = next;
    _generation++;
    state = CallLogState(loading: auth.isAuthenticated);
    if (auth.isAuthenticated && (hadScope || state.records.isEmpty)) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final requestScope = _scopeKey;
    final cache = ref.read(responseCacheProvider);
    final user = ref.read(authSessionControllerProvider).session?.user;
    final scope = user == null ? null : ResponseCacheScope.fromUser(user);
    var hadCached = false;
    state = state.copyWith(
      loading: state.records.isEmpty,
      refreshing: state.records.isNotEmpty,
      error: null,
    );
    if (scope != null) {
      try {
        final cached = await cache.read(
          scope: scope,
          module: 'calls',
          key: 'history:${stableCacheQueryKey({'page': 1, 'per_page': 20})}',
        );
        if (cached?.schemaVersion == responseCacheSchemaVersion &&
            cached?.payload is Map) {
          final page = CallLogPage.fromJson(cached!.payload, requestedPage: 1);
          if (!ref.mounted ||
              generation != _generation ||
              requestScope != _scopeKey) {
            return;
          }
          hadCached = true;
          state = CallLogState(
            records: page.records,
            page: page.page,
            hasMore: page.hasMore,
            refreshing: true,
          );
        }
      } catch (_) {}
    }
    try {
      final result = await ref.read(callApiProvider).getCallLogs(page: 1);
      if (!ref.mounted ||
          generation != _generation ||
          requestScope != _scopeKey) {
        return;
      }
      state = CallLogState(
        records: result.records,
        page: result.page,
        hasMore: result.hasMore,
      );
      if (scope != null) {
        unawaited(cache.write(
          scope: scope,
          module: 'calls',
          key: 'history:${stableCacheQueryKey({'page': 1, 'per_page': 20})}',
          payload: _pageJson(result),
          expectedEpoch: cache.writeEpoch,
        ));
      }
    } catch (error) {
      if (!ref.mounted ||
          generation != _generation ||
          requestScope != _scopeKey) {
        return;
      }
      if (hadCached) {
        state = state.copyWith(loading: false, refreshing: false, error: null);
        return;
      }
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
      final user = ref.read(authSessionControllerProvider).session?.user;
      if (user != null) {
        final scope = ResponseCacheScope.fromUser(user);
        unawaited(ref.read(responseCacheProvider).write(
              scope: scope,
              module: 'calls',
              key: 'history:${stableCacheQueryKey({
                    'page': result.page,
                    'per_page': 20
                  })}',
              payload: _pageJson(result),
            ));
      }
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

  Map<String, Object?> _pageJson(CallLogPage page) => {
        'data': [
          for (final record in page.records)
            {
              'call_id': record.id,
              'direction': record.direction.name,
              'status': record.status.name,
              'customer_phone': record.phoneNumber,
              'created_at': record.occurredAt.toIso8601String(),
              'customer_id': record.customerId,
              'customer_name': record.customerName,
              'duration': record.duration.inSeconds,
              'formatted_duration': record.formattedDuration,
              'ticket_number': record.ticketNumber,
              'ticket_subject': record.ticketSubject,
              'agent_name': record.agentName,
              'transcript': record.transcript,
              'recording_url': record.recordingUrl,
            }
        ],
        'meta': {
          'current_page': page.page,
          'last_page': page.hasMore ? page.page + 1 : page.page
        },
      };
}
