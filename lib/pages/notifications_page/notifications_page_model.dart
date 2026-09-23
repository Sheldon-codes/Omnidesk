import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/fcm_service.dart';
import 'notifications_models.dart';
import 'notifications_repository.dart';

final notificationsPageProvider =
    NotifierProvider<NotificationsPageNotifier, NotificationsPageState>(
  NotificationsPageNotifier.new,
);

class NotificationsPageState {
  const NotificationsPageState({
    this.items = const [],
    this.unreadCount = 0,
    this.loading = false,
    this.refreshing = false,
    this.error,
    this.hasLoaded = false,
  });
  final List<AppNotification> items;
  final int unreadCount;
  final bool loading;
  final bool refreshing;
  final Object? error;
  final bool hasLoaded;
}

class NotificationsPageNotifier extends Notifier<NotificationsPageState> {
  StreamSubscription<AppNotification>? _subscription;

  @override
  NotificationsPageState build() {
    state = const NotificationsPageState();
    _subscription = ref
        .read(fcmServiceProvider)
        .notificationEvents
        .listen((item) => applyIncoming(item));
    unawaited(load());
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return state;
  }

  Future<void> load() async {
    try {
      final cached = await ref.read(notificationsRepositoryProvider).feed(
            onCached: (value) => state = NotificationsPageState(
              items: value.items,
              unreadCount: value.unreadCount,
              hasLoaded: true,
              refreshing: true,
            ),
            onCacheMiss: () {
              if (state.items.isEmpty) {
                state = const NotificationsPageState(loading: true);
              }
            },
          );
      state = NotificationsPageState(
        items: cached.items,
        unreadCount: cached.unreadCount,
        hasLoaded: true,
      );
    } catch (error) {
      if (state.items.isEmpty) {
        state = NotificationsPageState(error: error, hasLoaded: true);
      }
    }
  }

  Future<void> refresh() async {
    state = NotificationsPageState(
      items: state.items,
      unreadCount: state.unreadCount,
      hasLoaded: state.hasLoaded,
      refreshing: true,
    );
    try {
      await load();
    } catch (error) {
      if (state.items.isNotEmpty) {
        state = NotificationsPageState(
          items: state.items,
          unreadCount: state.unreadCount,
          hasLoaded: true,
        );
      } else {
        state = NotificationsPageState(error: error, hasLoaded: true);
      }
    }
  }

  Future<void> markRead(AppNotification item) async {
    if (item.isRead) return;
    final updated = item.copyWith(isRead: true);
    _replace(updated);
    try {
      await ref
          .read(notificationsRepositoryProvider)
          .markRead(readAt: item.createdAt ?? DateTime.now());
    } catch (_) {
      _replace(item);
    }
  }

  Future<void> markAllRead() async {
    final previous = state;
    state = NotificationsPageState(
      items: [for (final item in state.items) item.copyWith(isRead: true)],
      unreadCount: 0,
      hasLoaded: true,
    );
    try {
      await ref.read(notificationsRepositoryProvider).markRead();
    } catch (_) {
      state = previous;
    }
  }

  Future<void> dismiss(AppNotification item) async {
    final previous = state;
    state = NotificationsPageState(
      items: state.items.where((value) => value.id != item.id).toList(),
      unreadCount: item.isRead ? state.unreadCount : state.unreadCount - 1,
      hasLoaded: true,
    );
    try {
      await ref.read(notificationsRepositoryProvider).dismiss(item.id);
    } catch (_) {
      state = previous;
    }
  }

  void applyIncoming(AppNotification item) {
    final items = [item, ...state.items.where((value) => value.id != item.id)];
    state = NotificationsPageState(
      items: items,
      unreadCount: item.isRead
          ? state.unreadCount
          : state.unreadCount +
              (state.items.any((n) => n.id == item.id) ? 0 : 1),
      hasLoaded: true,
    );
    unawaited(
      ref.read(notificationsRepositoryProvider).persist(
            NotificationFeed(items: items, unreadCount: state.unreadCount),
          ),
    );
  }

  void _replace(AppNotification item) {
    state = NotificationsPageState(
      items: [
        for (final value in state.items) value.id == item.id ? item : value,
      ],
      unreadCount: state.items.where((value) => !value.isRead).length,
      hasLoaded: state.hasLoaded,
    );
  }
}
