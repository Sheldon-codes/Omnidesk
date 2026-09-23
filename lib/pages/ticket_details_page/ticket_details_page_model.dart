import 'dart:async';

import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/auth_session_controller.dart';
import '../../services/agent_counters.dart';
import '../tickets_page/tickets_page_model.dart';

part 'ticket_details_page_model.g.dart';

class TicketDetailsState {
  const TicketDetailsState({
    this.ticket,
    this.loading = true,
    this.failure,
    this.activity = const [],
    this.loadingMore = false,
    this.hasLoadedDetail = false,
    this.mutating = false,
  });
  final TicketRecord? ticket;
  final bool loading;
  final Object? failure;
  final List<TicketActivity> activity;
  final bool loadingMore;
  final bool hasLoadedDetail;
  final bool mutating;
  bool get notFound => !loading && failure == null && ticket == null;

  TicketDetailsState copyWith({
    TicketRecord? ticket,
    bool? loading,
    Object? failure = _keep,
    List<TicketActivity>? activity,
    bool? loadingMore,
    bool? hasLoadedDetail,
    bool? mutating,
  }) =>
      TicketDetailsState(
        ticket: ticket ?? this.ticket,
        loading: loading ?? this.loading,
        failure: identical(failure, _keep) ? this.failure : failure,
        activity: activity ?? this.activity,
        loadingMore: loadingMore ?? this.loadingMore,
        hasLoadedDetail: hasLoadedDetail ?? this.hasLoadedDetail,
        mutating: mutating ?? this.mutating,
      );

  static const _keep = Object();
}

@riverpod
class TicketDetailsNotifier extends _$TicketDetailsNotifier {
  CancelToken? _cancelToken;
  int _generation = 0;
  String? _sessionScope;

  @override
  TicketDetailsState build({required String ticketId}) {
    final auth = ref.watch(authSessionControllerProvider);
    final scope =
        '${auth.session?.user.id ?? 'anonymous'}:${auth.session?.user.activeWorkspace?.id ?? 'none'}';
    if (_sessionScope != null && _sessionScope != scope) {
      _generation++;
      _cancelToken?.cancel('Ticket workspace changed.');
    }
    _sessionScope = scope;
    final cached = ref
        .read(ticketsPageProvider)
        .tickets
        .where((ticket) => ticket.id == ticketId)
        .firstOrNull;
    ref.listen(ticketsPageProvider, (_, next) {
      final summary =
          next.tickets.where((ticket) => ticket.id == ticketId).firstOrNull;
      if (summary != null && !state.hasLoadedDetail) {
        state = state.copyWith(ticket: summary);
      }
    });
    ref.onDispose(() => _cancelToken?.cancel('Ticket detail disposed.'));
    Future<void>(() => load());
    return TicketDetailsState(ticket: cached);
  }

  Future<void> load() async {
    _cancelToken?.cancel('Superseded by a newer ticket detail request.');
    final token = CancelToken();
    _cancelToken = token;
    final generation = ++_generation;
    state = state.copyWith(
      loading: true,
      failure: null,
    );
    try {
      final result = await ref.read(ticketsRepositoryProvider).detail(
        ticketId,
        cancelToken: token,
        onCacheMiss: () {
          if (generation == _generation && state.ticket == null) {
            state = state.copyWith(loading: true);
          }
        },
        onCached: (cached) {
          if (generation != _generation) return;
          state = TicketDetailsState(
            ticket: cached.ticket,
            loading: true,
            activity: cached.activity,
            hasLoadedDetail: true,
          );
        },
      );
      if (generation != _generation) return;
      state = TicketDetailsState(
        ticket: result.ticket,
        loading: false,
        activity: result.activity,
        hasLoadedDetail: true,
      );
    } catch (error) {
      if (error is DioException && CancelToken.isCancel(error)) return;
      if (generation != _generation) return;
      if (error is DioException && error.response?.statusCode == 404) {
        state = TicketDetailsState(
          ticket: null,
          loading: false,
          activity: const [],
          hasLoadedDetail: true,
        );
        return;
      }
      state = state.copyWith(
        loading: false,
        failure: _message(error),
      );
    }
  }

  Future<void> loadMore() async {}

  Future<void> resolve(String note) => _changeStatus('resolved', reason: note);
  Future<void> reopen() => _changeStatus('open');

  Future<void> _changeStatus(String status, {String? reason}) async {
    if (state.mutating) return;
    state = state.copyWith(mutating: true, failure: null);
    try {
      await ref
          .read(ticketsRepositoryProvider)
          .updateStatus(ticketId, status, reason: reason);
      state = state.copyWith(mutating: false);
      await load();
      await ref.read(ticketsPageProvider.notifier).refresh();
      unawaited(ref.read(agentCountersProvider.notifier).refresh());
    } catch (error) {
      state = state.copyWith(mutating: false, failure: _message(error));
      rethrow;
    }
  }

  String _message(Object error) => error is FormatException
      ? 'The server returned ticket data in an unexpected format.'
      : error.toString().replaceFirst('Exception: ', '');
}
