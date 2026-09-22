import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Shared SQLCipher database for response cache and durable local queues/drafts.
/// The encryption key never leaves platform secure storage except while opening
/// the database and is not included in logs or database metadata.
class AppLocalDatabase {
  AppLocalDatabase({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _keyName = 'omnidesk_local_database_key_v1';
  final FlutterSecureStorage _secureStorage;
  Future<Database>? _opening;

  Future<Database> get database {
    final current = _opening;
    if (current != null) return current;
    final next = _open().catchError((Object error, StackTrace stackTrace) {
      // A transient secure-storage/filesystem failure must not poison this
      // provider for the remainder of the process. Permit an explicit retry.
      _opening = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _opening = next;
    return next;
  }

  Future<Database> _open() async {
    final directory = await getDatabasesPath();
    final databasePath = path.join(directory, 'omnidesk_secure_local.db');
    var key = await _secureStorage.read(key: _keyName);
    if (key == null) {
      // Secure-storage restore can be independent from app-data restore. A
      // SQLCipher file without its key is unrecoverable; discard only this
      // database (not the legacy draft/outbox sources) and create a fresh key.
      if (await databaseExists(databasePath)) {
        await deleteDatabase(databasePath);
      }
      key = await _createKey();
    }
    final db = await openDatabase(
      databasePath,
      password: key,
      version: 2,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE server_cache (
            user_id TEXT NOT NULL,
            workspace_id TEXT NOT NULL,
            module TEXT NOT NULL,
            cache_key TEXT NOT NULL,
            payload TEXT NOT NULL,
            fetched_at INTEGER NOT NULL,
            schema_version INTEGER NOT NULL,
            PRIMARY KEY (user_id, workspace_id, module, cache_key)
          )
        ''');
        await database.execute('''
          CREATE TABLE email_drafts (
            draft_key TEXT PRIMARY KEY,
            thread_id TEXT,
            mode TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE outbox (
            local_id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL DEFAULT '',
            workspace_id TEXT NOT NULL DEFAULT '',
            ticket_id TEXT NOT NULL,
            text TEXT,
            reply_to_id TEXT,
            file_path TEXT,
            mime_type TEXT,
            file_name TEXT,
            duration_secs INTEGER,
            attempts INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
        await database.execute(
            'CREATE INDEX idx_outbox_scope_ticket ON outbox(user_id, workspace_id, ticket_id, status)');
        await database.execute('''
          CREATE TABLE local_migrations (
            migration_id TEXT PRIMARY KEY,
            completed_at INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
              "ALTER TABLE outbox ADD COLUMN user_id TEXT NOT NULL DEFAULT ''");
          await database.execute(
              "ALTER TABLE outbox ADD COLUMN workspace_id TEXT NOT NULL DEFAULT ''");
          await database.execute(
              'CREATE INDEX idx_outbox_scope_ticket ON outbox(user_id, workspace_id, ticket_id, status)');
        }
      },
    );
    await _migrateLegacyDatabases(db, directory);
    return db;
  }

  Future<String> _createKey() async {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await _secureStorage.write(key: _keyName, value: key);
    return key;
  }

  Future<void> _migrateLegacyDatabases(
      Database encrypted, String databaseDir) async {
    final support = await getApplicationSupportDirectory();
    await _copyLegacyTable(
      encrypted: encrypted,
      migrationId: 'email_drafts_v1',
      legacyPath: path.join(support.path, 'omnidesk_email_drafts.db'),
      table: 'email_drafts',
      columns: const [
        'draft_key',
        'thread_id',
        'mode',
        'payload',
        'updated_at'
      ],
    );
    await _copyLegacyTable(
      encrypted: encrypted,
      migrationId: 'whatsapp_outbox_v1',
      legacyPath: path.join(databaseDir, 'whatsapp_outbox.db'),
      table: 'outbox',
      columns: const [
        'local_id',
        'ticket_id',
        'text',
        'reply_to_id',
        'file_path',
        'mime_type',
        'file_name',
        'duration_secs',
        'attempts',
        'created_at',
        'status',
      ],
    );
  }

  Future<void> _copyLegacyTable({
    required Database encrypted,
    required String migrationId,
    required String legacyPath,
    required String table,
    required List<String> columns,
  }) async {
    final completed = await encrypted.query('local_migrations',
        where: 'migration_id = ?', whereArgs: [migrationId], limit: 1);
    if (completed.isNotEmpty) return;
    if (!await databaseExists(legacyPath)) {
      await _markMigration(encrypted, migrationId);
      return;
    }

    Database? legacy;
    try {
      // Existing databases are opened without a key only for one-time import.
      // They are deleted only after a successful transactional copy.
      legacy = await openDatabase(legacyPath, readOnly: true);
      final exists = await legacy.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [table]);
      if (exists.isNotEmpty) {
        final rows = await legacy.query(table);
        await encrypted.transaction((transaction) async {
          for (final row in rows) {
            final values = <String, Object?>{
              for (final column in columns)
                if (row.containsKey(column)) column: row[column],
            };
            await transaction.insert(table, values,
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          await transaction.insert(
            'local_migrations',
            {
              'migration_id': migrationId,
              'completed_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        });
      } else {
        await _markMigration(encrypted, migrationId);
      }
      await legacy.close();
      legacy = null;
      await deleteDatabase(legacyPath);
    } catch (_) {
      await legacy?.close();
      // Retain the original database and retry migration on the next open.
    }
  }

  Future<void> _markMigration(Database db, String id) => db.insert(
        'local_migrations',
        {
          'migration_id': id,
          'completed_at': DateTime.now().millisecondsSinceEpoch
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
}

final appLocalDatabaseProvider = Provider<AppLocalDatabase>(
  (ref) => AppLocalDatabase(),
);
