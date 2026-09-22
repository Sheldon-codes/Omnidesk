import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/auth/auth_models.dart';
import 'app_local_database.dart';

const responseCacheSchemaVersion = 1;

class ResponseCacheScope {
  const ResponseCacheScope({required this.userId, required this.workspaceId});

  final String userId;
  final String workspaceId;

  @override
  bool operator ==(Object other) =>
      other is ResponseCacheScope &&
      other.userId == userId &&
      other.workspaceId == workspaceId;

  @override
  int get hashCode => Object.hash(userId, workspaceId);

  factory ResponseCacheScope.fromUser(AuthUser user) => ResponseCacheScope(
        userId: user.id,
        workspaceId: user.activeWorkspace?.id ?? 'no-workspace',
      );
}

class CachedResponse {
  const CachedResponse({
    required this.payload,
    required this.fetchedAt,
    required this.schemaVersion,
  });

  final Object? payload;
  final DateTime fetchedAt;
  final int schemaVersion;
}

/// Persists backend response snapshots only. Callers own typed decoding and
/// request-generation guards so cache reads and network responses follow the
/// same repository mapping path.
class ResponseCache {
  ResponseCache(this._database);

  final AppLocalDatabase _database;
  int _writeEpoch = 0;

  int get writeEpoch => _writeEpoch;

  Future<CachedResponse?> read({
    required ResponseCacheScope scope,
    required String module,
    required String key,
  }) async {
    final rows = await (await _database.database).query(
      'server_cache',
      columns: ['payload', 'fetched_at', 'schema_version'],
      where:
          'user_id = ? AND workspace_id = ? AND module = ? AND cache_key = ?',
      whereArgs: [scope.userId, scope.workspaceId, module, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    try {
      final decoded = jsonDecode(row['payload']! as String);
      return CachedResponse(
        payload: decoded,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
            row['fetched_at']! as int,
            isUtc: true),
        schemaVersion: row['schema_version']! as int,
      );
    } on Object {
      // Bad or interrupted rows are treated as misses and removed, never
      // surfaced as cached content.
      await (await _database.database).delete(
        'server_cache',
        where:
            'user_id = ? AND workspace_id = ? AND module = ? AND cache_key = ?',
        whereArgs: [scope.userId, scope.workspaceId, module, key],
      );
      return null;
    }
  }

  Future<bool> write({
    required ResponseCacheScope scope,
    required String module,
    required String key,
    required Object? payload,
    int? expectedEpoch,
  }) async {
    if (expectedEpoch != null && expectedEpoch != _writeEpoch) return false;
    final encoded = jsonEncode(payload);
    final db = await _database.database;
    await db.transaction((txn) async {
      if (expectedEpoch != null && expectedEpoch != _writeEpoch) return;
      await txn.insert(
        'server_cache',
        {
          'user_id': scope.userId,
          'workspace_id': scope.workspaceId,
          'module': module,
          'cache_key': key,
          'payload': encoded,
          'fetched_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          'schema_version': responseCacheSchemaVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return expectedEpoch == null || expectedEpoch == _writeEpoch;
  }

  Future<void> writeBatch(
    List<
            ({
              ResponseCacheScope scope,
              String module,
              String key,
              Object? payload,
            })>
        entries, {
    int? expectedEpoch,
  }) async {
    if (expectedEpoch != null && expectedEpoch != _writeEpoch) return;
    final db = await _database.database;
    await db.transaction((txn) async {
      for (final entry in entries) {
        if (expectedEpoch != null && expectedEpoch != _writeEpoch) return;
        await txn.insert(
          'server_cache',
          {
            'user_id': entry.scope.userId,
            'workspace_id': entry.scope.workspaceId,
            'module': entry.module,
            'cache_key': entry.key,
            'payload': jsonEncode(entry.payload),
            'fetched_at': DateTime.now().toUtc().millisecondsSinceEpoch,
            'schema_version': responseCacheSchemaVersion,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<bool> updateJson({
    required ResponseCacheScope scope,
    required String module,
    required String key,
    required Object? Function(Object? current) update,
    int? expectedEpoch,
  }) async {
    if (expectedEpoch != null && expectedEpoch != _writeEpoch) return false;
    final db = await _database.database;
    var didWrite = false;
    await db.transaction((txn) async {
      if (expectedEpoch != null && expectedEpoch != _writeEpoch) return;
      final rows = await txn.query(
        'server_cache',
        columns: ['payload'],
        where:
            'user_id = ? AND workspace_id = ? AND module = ? AND cache_key = ?',
        whereArgs: [scope.userId, scope.workspaceId, module, key],
        limit: 1,
      );
      Object? current;
      if (rows.isNotEmpty) {
        try {
          current = jsonDecode(rows.single['payload']! as String);
        } on Object {
          current = null;
        }
      }
      final next = update(current);
      if (expectedEpoch != null && expectedEpoch != _writeEpoch) return;
      await txn.insert(
        'server_cache',
        {
          'user_id': scope.userId,
          'workspace_id': scope.workspaceId,
          'module': module,
          'cache_key': key,
          'payload': jsonEncode(next),
          'fetched_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          'schema_version': responseCacheSchemaVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      didWrite = true;
    });
    return didWrite;
  }

  /// Applies a JSON transformation to every cached snapshot in a module for
  /// the active user/workspace. This is used after confirmed mutations so
  /// cached list pages and detail snapshots do not regress to stale values.
  Future<void> updateModuleJson({
    required ResponseCacheScope scope,
    required String module,
    required Object? Function(String key, Object? current) update,
    int? expectedEpoch,
  }) async {
    if (expectedEpoch != null && expectedEpoch != _writeEpoch) return;
    final db = await _database.database;
    await db.transaction((txn) async {
      if (expectedEpoch != null && expectedEpoch != _writeEpoch) return;
      final rows = await txn.query(
        'server_cache',
        columns: ['cache_key', 'payload'],
        where: 'user_id = ? AND workspace_id = ? AND module = ?',
        whereArgs: [scope.userId, scope.workspaceId, module],
      );
      for (final row in rows) {
        if (expectedEpoch != null && expectedEpoch != _writeEpoch) return;
        final key = row['cache_key']! as String;
        Object? current;
        try {
          current = jsonDecode(row['payload']! as String);
        } on Object {
          continue;
        }
        final next = update(key, current);
        if (identical(next, current)) continue;
        await txn.update(
          'server_cache',
          {
            'payload': jsonEncode(next),
            'fetched_at': DateTime.now().toUtc().millisecondsSinceEpoch,
            'schema_version': responseCacheSchemaVersion,
          },
          where:
              'user_id = ? AND workspace_id = ? AND module = ? AND cache_key = ?',
          whereArgs: [scope.userId, scope.workspaceId, module, key],
        );
      }
    });
  }

  Future<void> clearAllServerData() async {
    // Increment before waiting for SQLite. Network responses holding an older
    // epoch cannot repopulate the just-cleared account cache.
    _writeEpoch++;
    await (await _database.database).delete('server_cache');
  }

  Future<void> clearScope(ResponseCacheScope scope) async {
    _writeEpoch++;
    await (await _database.database).delete(
      'server_cache',
      where: 'user_id = ? AND workspace_id = ?',
      whereArgs: [scope.userId, scope.workspaceId],
    );
  }
}

class CacheFirstResult<T> {
  const CacheFirstResult({
    required this.value,
    required this.hadCachedValue,
    required this.refreshed,
  });

  final T value;
  final bool hadCachedValue;
  final bool refreshed;
}

/// Reads a cached server response first, publishes it through [onCached],
/// then refreshes it. A failed refresh is silent when a cache value was
/// published; a cache miss still propagates the error for normal retry UI.
class CacheFirstJsonLoader {
  const CacheFirstJsonLoader(this._cache);
  final ResponseCache _cache;

  Future<CacheFirstResult<T>> load<T>({
    required ResponseCacheScope scope,
    required String module,
    required String key,
    required int expectedEpoch,
    required Future<Object?> Function() fetch,
    required T Function(Object? payload) decode,
    required void Function(T value) onCached,
    required void Function(T value) onFresh,
    void Function()? onCacheMiss,
  }) async {
    T? cachedValue;
    var hadCachedValue = false;
    try {
      final snapshot = await _cache.read(
        scope: scope,
        module: module,
        key: key,
      );
      if (snapshot != null &&
          snapshot.schemaVersion == responseCacheSchemaVersion) {
        cachedValue = decode(snapshot.payload);
        hadCachedValue = true;
        onCached(cachedValue as T);
      }
    } on Object {
      // A stale decoder/schema row is a cache miss; the authoritative API
      // request below can repopulate it.
    }
    if (!hadCachedValue) onCacheMiss?.call();

    try {
      final payload = await fetch();
      final freshValue = decode(payload);
      var persisted = false;
      try {
        persisted = await _cache.write(
          scope: scope,
          module: module,
          key: key,
          payload: payload,
          expectedEpoch: expectedEpoch,
        );
      } on Object {
        // A successful API response is still authoritative for this session
        // even if local storage is temporarily unavailable.
      }
      if (expectedEpoch == _cache.writeEpoch) onFresh(freshValue);
      return CacheFirstResult(
        value: freshValue,
        hadCachedValue: hadCachedValue,
        refreshed: persisted,
      );
    } on Object {
      if (hadCachedValue) {
        return CacheFirstResult(
          value: cachedValue as T,
          hadCachedValue: true,
          refreshed: false,
        );
      }
      rethrow;
    }
  }
}

String stableCacheQueryKey(Map<String, Object?> values) {
  final entries = values.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return Uri(queryParameters: {
    for (final entry in entries)
      if (entry.value != null) entry.key: '${entry.value}',
  }).query;
}

final responseCacheProvider = Provider<ResponseCache>(
  (ref) => ResponseCache(ref.watch(appLocalDatabaseProvider)),
);
