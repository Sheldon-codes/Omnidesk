import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/api_service.dart';
import '../../services/auth_session_controller.dart';
import '../../services/response_cache.dart';
import 'notifications_models.dart';

part 'notifications_repository.g.dart';

class NotificationsRepository {
  NotificationsRepository(this._api, {this.cache, this.readScope});
  final ApiService _api;
  final ResponseCache? cache;
  final ResponseCacheScope? Function()? readScope;

  Future<NotificationFeed> feed({
    int limit = 30,
    CancelToken? cancelToken,
    void Function(NotificationFeed value)? onCached,
    void Function()? onCacheMiss,
  }) async {
    final scope = readScope?.call();
    if (cache != null && scope != null) {
      return (await CacheFirstJsonLoader(cache!).load(
        scope: scope,
        module: 'notifications',
        key: 'feed:$limit',
        expectedEpoch: cache!.writeEpoch,
        fetch: () => _api.get(
          '/notifications/feed',
          queryParameters: {'limit': limit},
          cancelToken: cancelToken,
        ),
        decode: NotificationFeed.fromJson,
        onCached: onCached ?? (_) {},
        onFresh: (_) {},
        onCacheMiss: onCacheMiss,
      ))
          .value;
    }
    return NotificationFeed.fromJson(
      await _api.get(
        '/notifications/feed',
        queryParameters: {'limit': limit},
        cancelToken: cancelToken,
      ),
    );
  }

  Future<void> markRead({DateTime? readAt}) => _api.post(
        '/notifications/mark-read',
        {if (readAt != null) 'read_at': readAt.toUtc().toIso8601String()},
      );

  Future<void> dismiss(String id) =>
      _api.post('/notifications/delete', {'id': id});

  Future<void> persist(NotificationFeed value, {int limit = 30}) async {
    final scope = readScope?.call();
    if (cache == null || scope == null) return;
    await cache!.write(
      scope: scope,
      module: 'notifications',
      key: 'feed:$limit',
      payload: value.toJson(),
    );
  }
}

@Riverpod(keepAlive: true)
NotificationsRepository notificationsRepository(Ref ref) {
  final user = ref.watch(authSessionControllerProvider).session?.user;
  return NotificationsRepository(
    ref.read(apiServiceProvider),
    cache: ref.watch(responseCacheProvider),
    readScope: user == null ? null : () => ResponseCacheScope.fromUser(user),
  );
}
