import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/services/app_local_database.dart';
import 'package:omnidesk_agent/services/response_cache.dart';

class _MemoryResponseCache extends ResponseCache {
  _MemoryResponseCache() : super(AppLocalDatabase());

  final values = <String, CachedResponse>{};
  final clearedScopes = <ResponseCacheScope>[];
  var writes = 0;
  var epoch = 0;

  String _key(ResponseCacheScope scope, String module, String key) =>
      '${scope.userId}/${scope.workspaceId}/$module/$key';

  @override
  int get writeEpoch => epoch;

  @override
  Future<CachedResponse?> read({
    required ResponseCacheScope scope,
    required String module,
    required String key,
  }) async =>
      values[_key(scope, module, key)];

  @override
  Future<bool> write({
    required ResponseCacheScope scope,
    required String module,
    required String key,
    required Object? payload,
    int? expectedEpoch,
  }) async {
    if (expectedEpoch != null && expectedEpoch != epoch) return false;
    writes++;
    values[_key(scope, module, key)] = CachedResponse(
      payload: payload,
      fetchedAt: DateTime.now().toUtc(),
      schemaVersion: responseCacheSchemaVersion,
    );
    return true;
  }

  @override
  Future<void> clearAllServerData() async {
    epoch++;
    values.clear();
  }

  @override
  Future<void> clearScope(ResponseCacheScope scope) async {
    epoch++;
    clearedScopes.add(scope);
  }
}

void main() {
  const scope =
      ResponseCacheScope(userId: 'agent-1', workspaceId: 'workspace-1');

  test('cache-first publishes the persisted snapshot before refreshing',
      () async {
    final cache = _MemoryResponseCache()
      ..values['agent-1/workspace-1/home/dashboard'] = CachedResponse(
        payload: {'value': 'cached'},
        fetchedAt: DateTime.utc(2026),
        schemaVersion: responseCacheSchemaVersion,
      );
    final published = <String>[];
    final network = Completer<Object?>();
    final response = CacheFirstJsonLoader(cache).load<String>(
      scope: scope,
      module: 'home',
      key: 'dashboard',
      expectedEpoch: cache.writeEpoch,
      fetch: () => network.future,
      decode: (payload) => (payload as Map)['value']! as String,
      onCached: published.add,
      onFresh: published.add,
    );

    await Future<void>.delayed(Duration.zero);
    expect(published, ['cached']);
    network.complete({'value': 'fresh'});
    expect((await response).value, 'fresh');
    expect(published, ['cached', 'fresh']);
    expect(cache.writes, 1);
  });

  test('refresh failure is silent after a usable cache hit', () async {
    final cache = _MemoryResponseCache()
      ..values['agent-1/workspace-1/customers/profile:88'] = CachedResponse(
        payload: {'id': '88'},
        fetchedAt: DateTime.utc(2026),
        schemaVersion: responseCacheSchemaVersion,
      );
    final rendered = <String>[];
    final result = await CacheFirstJsonLoader(cache).load<String>(
      scope: scope,
      module: 'customers',
      key: 'profile:88',
      expectedEpoch: cache.writeEpoch,
      fetch: () async => throw StateError('offline'),
      decode: (payload) => (payload as Map)['id']! as String,
      onCached: rendered.add,
      onFresh: rendered.add,
    );

    expect(result.value, '88');
    expect(result.hadCachedValue, isTrue);
    expect(result.refreshed, isFalse);
    expect(rendered, ['88']);
  });

  test('cold cache failure still surfaces to the screen', () async {
    final cache = _MemoryResponseCache();
    await expectLater(
      CacheFirstJsonLoader(cache).load<String>(
        scope: scope,
        module: 'tickets',
        key: 'list',
        expectedEpoch: cache.writeEpoch,
        fetch: () async => throw StateError('offline'),
        decode: (payload) => '$payload',
        onCached: (_) {},
        onFresh: (_) {},
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('account cache invalidation blocks a late network response write',
      () async {
    final cache = _MemoryResponseCache();
    final pending = Completer<Object?>();
    final future = CacheFirstJsonLoader(cache).load<String>(
      scope: scope,
      module: 'email',
      key: 'folder:inbox',
      expectedEpoch: cache.writeEpoch,
      fetch: () => pending.future,
      decode: (payload) => (payload as Map)['value']! as String,
      onCached: (_) {},
      onFresh: (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    await cache.clearAllServerData();
    pending.complete({'value': 'late'});
    final result = await future;

    expect(result.refreshed, isFalse);
    expect(cache.values, isEmpty);
  });

  test('query keys are deterministic regardless of map insertion order', () {
    expect(
      stableCacheQueryKey({'page': 2, 'status': 'open'}),
      stableCacheQueryKey({'status': 'open', 'page': 2}),
    );
  });
}
