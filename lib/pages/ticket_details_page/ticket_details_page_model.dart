import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../tickets_page/ticket_store.dart';

part 'ticket_details_page_model.g.dart';

class TicketDetailsState {
  const TicketDetailsState({
    this.ticket,
    this.loading = true,
    this.failure,
    this.activity = const [],
    this.nextActivityCursor,
    this.loadingMore = false,
  });
  final TicketRecord? ticket;
  final bool loading;
  final Object? failure;
  final List<TicketActivity> activity;
  final String? nextActivityCursor;
  final bool loadingMore;
  bool get notFound => !loading && failure == null && ticket == null;
  TicketDetailsState copyWith(
          {TicketRecord? ticket,
          bool? loading,
          Object? failure,
          List<TicketActivity>? activity,
          Object? nextActivityCursor = _keep,
          bool? loadingMore}) =>
      TicketDetailsState(
          ticket: ticket ?? this.ticket,
          loading: loading ?? this.loading,
          failure: failure,
          activity: activity ?? this.activity,
          nextActivityCursor: identical(nextActivityCursor, _keep)
              ? this.nextActivityCursor
              : nextActivityCursor as String?,
          loadingMore: loadingMore ?? this.loadingMore);
  static const _keep = Object();
}

@riverpod
class TicketDetailsNotifier extends _$TicketDetailsNotifier {
  @override
  TicketDetailsState build({required String ticketId}) {
    ref.listen(ticketStoreProvider, (_, next) {
      final ticket = next.findById(ticketId);
      if (ticket != null && state.ticket != ticket) {
        state = state.copyWith(ticket: ticket, loading: false, failure: null);
      }
    });
    Future<void>(() => load());
    return const TicketDetailsState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, failure: null);
    try {
      final ticket = ref.read(ticketStoreProvider).findById(ticketId);
      if (ticket == null) {
        state = const TicketDetailsState(loading: false);
        return;
      }
      final page =
          await ref.read(ticketStoreProvider.notifier).loadActivity(ticketId);
      state = TicketDetailsState(
          ticket: ticket,
          loading: false,
          activity: page.items,
          nextActivityCursor: page.nextCursor);
    } catch (error) {
      state = state.copyWith(loading: false, failure: error);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.nextActivityCursor == null) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(ticketStoreProvider.notifier)
          .loadActivity(ticketId, cursor: state.nextActivityCursor);
      state = state.copyWith(
          activity: [...state.activity, ...page.items],
          nextActivityCursor: page.nextCursor,
          loadingMore: false);
    } catch (error) {
      state = state.copyWith(loadingMore: false, failure: error);
    }
  }
}
