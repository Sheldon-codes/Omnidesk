import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
        createdAt:
            DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
        status: '${m['status'] ?? 'pending'}',
      );
}

class WhatsAppOutbox {
  WhatsAppOutbox({Database? db, Future<Database> Function()? opener})
      : _db = db,
        _opener = opener;

  Database? _db;
  final Future<Database> Function()? _opener;

  Future<Database> _ready() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    if (_opener != null) {
      _db = await _opener!();
      return _db!;
    }
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'whatsapp_outbox.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE outbox(
            local_id TEXT PRIMARY KEY,
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
        await db.execute(
            'CREATE INDEX idx_outbox_ticket ON outbox(ticket_id, status)');
      },
    );
    return _db!;
  }

  Future<void> enqueue(WhatsAppOutboxEntry entry) async {
    final db = await _ready();
    await db.insert('outbox', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<WhatsAppOutboxEntry>> pending({String? ticketId}) async {
    final db = await _ready();
    final rows = ticketId == null
        ? await db.query('outbox',
            where: 'status != ?',
            whereArgs: ['sent'],
            orderBy: 'created_at ASC',
            limit: 100)
        : await db.query('outbox',
            where: 'ticket_id = ? AND status != ?',
            whereArgs: [ticketId, 'sent'],
            orderBy: 'created_at ASC',
            limit: 100);
    return rows.map(WhatsAppOutboxEntry.fromMap).toList();
  }

  Future<void> markSending(String localId) async {
    final db = await _ready();
    await db.update('outbox', {'status': 'sending'},
        where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<void> markFailed(String localId, int attempts) async {
    final db = await _ready();
    await db.update('outbox', {'status': 'failed', 'attempts': attempts},
        where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<void> remove(String localId) async {
    final db = await _ready();
    await db.delete('outbox', where: 'local_id = ?', whereArgs: [localId]);
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

  String exportDiagnostics(List<WhatsAppOutboxEntry> entries) => jsonEncode(
      entries.map((e) => {'localId': e.localId, 'ticket': e.ticketId}).toList());
}

final whatsAppOutboxProvider = Provider<WhatsAppOutbox>((ref) {
  final outbox = WhatsAppOutbox();
  ref.onDispose(() {});
  return outbox;
});
