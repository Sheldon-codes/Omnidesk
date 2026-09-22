import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../app_local_database.dart';
import '../auth_session_controller.dart';

/// Durable offline outbox for WhatsApp sends.
///
/// Every `send()` first lands here with `status=pending`, then a flusher
/// attempts delivery with exponential backoff. The queue survives process
/// death via sqflite, so airplane-mode sends are retried on reconnect.
class WhatsAppOutboxEntry {
  const WhatsAppOutboxEntry({
    required this.localId,
    required this.ticketId,
    this.text,
    this.replyToId,
    this.filePath,
    this.mimeType,
    this.fileName,
    this.durationSecs,
    required this.attempts,
    required this.createdAt,
    required this.status,
  });

  final String localId;
  final String ticketId;
  final String? text;
  final String? replyToId;
  final String? filePath;
  final String? mimeType;
  final String? fileName;
  final int? durationSecs;
  final int attempts;
  final DateTime createdAt;
  final String status; // pending | sending | failed

  Map<String, dynamic> toMap() => {
        'local_id': localId,
        'ticket_id': ticketId,
        'text': text,
        'reply_to_id': replyToId,
        'file_path': filePath,
        'mime_type': mimeType,
        'file_name': fileName,
        'duration_secs': durationSecs,
        'attempts': attempts,
        'created_at': createdAt.toIso8601String(),
        'status': status,
      };

  static WhatsAppOutboxEntry fromMap(Map<String, dynamic> m) =>
      WhatsAppOutboxEntry(
        localId: '${m['local_id']}',
        ticketId: '${m['ticket_id']}',
        text: m['text']?.toString(),
        replyToId: m['reply_to_id']?.toString(),
        filePath: m['file_path']?.toString(),
        mimeType: m['mime_type']?.toString(),
        fileName: m['file_name']?.toString(),
        durationSecs: m['duration_secs'] is num
            ? (m['duration_secs'] as num).toInt()
            : int.tryParse('${m['duration_secs'] ?? ''}'),
        attempts: (m['attempts'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
        status: '${m['status'] ?? 'pending'}',
      );
}

class WhatsAppOutbox {
  WhatsAppOutbox({
    Database? db,
    Future<Database> Function()? opener,
    required this.userId,
    required this.workspaceId,
  })  : _db = db,
        _opener = opener;

  final String userId;
  final String workspaceId;
  Database? _db;
  final Future<Database> Function()? _opener;
  Future<void>? _adoptingLegacyRows;

  Future<Database> _ready() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    if (_opener != null) {
      _db = await _opener!();
    } else {
      _db = await AppLocalDatabase().database;
    }
    await _adoptLegacyRows(_db!);
    return _db!;
  }

  Future<void> _adoptLegacyRows(Database db) {
    if (userId == 'anonymous') return Future.value();
    return _adoptingLegacyRows ??= db
        .update(
          'outbox',
          {'user_id': userId, 'workspace_id': workspaceId},
          where: "user_id = '' AND workspace_id = ''",
        )
        .then((_) {});
  }

  Future<void> enqueue(WhatsAppOutboxEntry entry) async {
    final db = await _ready();
    await db.insert(
        'outbox',
        {
          ...entry.toMap(),
          'user_id': userId,
          'workspace_id': workspaceId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<WhatsAppOutboxEntry>> pending({String? ticketId}) async {
    final db = await _ready();
    final rows = await db.query(
      'outbox',
      where: ticketId == null
          ? 'user_id = ? AND workspace_id = ? AND status != ?'
          : 'user_id = ? AND workspace_id = ? AND ticket_id = ? AND status != ?',
      whereArgs: ticketId == null
          ? [userId, workspaceId, 'sent']
          : [userId, workspaceId, ticketId, 'sent'],
      orderBy: 'created_at ASC',
      limit: 100,
    );
    return rows.map(WhatsAppOutboxEntry.fromMap).toList();
  }

  Future<void> markSending(String localId) async {
    final db = await _ready();
    await db.update('outbox', {'status': 'sending'},
        where: 'local_id = ? AND user_id = ? AND workspace_id = ?',
        whereArgs: [localId, userId, workspaceId]);
  }

  Future<void> markFailed(String localId, int attempts) async {
    final db = await _ready();
    await db.update('outbox', {'status': 'failed', 'attempts': attempts},
        where: 'local_id = ? AND user_id = ? AND workspace_id = ?',
        whereArgs: [localId, userId, workspaceId]);
  }

  Future<void> remove(String localId) async {
    final db = await _ready();
    await db.delete(
      'outbox',
      where: 'local_id = ? AND user_id = ? AND workspace_id = ?',
      whereArgs: [localId, userId, workspaceId],
    );
  }

  /// Backoff schedule: 2s, 8s, 30s, 2m, capped at 5 attempts before manual.
  static Duration backoffForAttempt(int attempts) {
    const schedule = [
      Duration(seconds: 2),
      Duration(seconds: 8),
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 10),
    ];
    if (attempts < 0) return schedule.first;
    if (attempts >= schedule.length) return schedule.last;
    return schedule[attempts];
  }

  String exportDiagnostics(List<WhatsAppOutboxEntry> entries) =>
      jsonEncode(entries
          .map((e) => {'localId': e.localId, 'ticket': e.ticketId})
          .toList());
}

final whatsAppOutboxProvider = Provider<WhatsAppOutbox>((ref) {
  final localDatabase = ref.watch(appLocalDatabaseProvider);
  final user = ref.watch(authSessionControllerProvider).session?.user;
  return WhatsAppOutbox(
    opener: () => localDatabase.database,
    userId: user?.id ?? 'anonymous',
    workspaceId: user?.activeWorkspace?.id ?? 'no-workspace',
  );
});
