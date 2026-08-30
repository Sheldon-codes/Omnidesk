import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'email_page_model.dart';

abstract class EmailDraftRepository {
  Future<EmailDraft?> load(String key);
  Future<void> save(EmailDraft draft);
  Future<void> delete(String key);
}

class SqliteEmailDraftRepository implements EmailDraftRepository {
  Database? _database;

  Future<Database> get _db async {
    if (_database case final existing?) return existing;
    final directory = await getApplicationSupportDirectory();
    _database = await openDatabase(
      path.join(directory.path, 'omnidesk_email_drafts.db'),
      version: 1,
      onCreate: (database, _) => database.execute('''
        CREATE TABLE email_drafts (
          draft_key TEXT PRIMARY KEY,
          thread_id TEXT,
          mode TEXT NOT NULL,
          payload TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      '''),
    );
    return _database!;
  }

  @override
  Future<EmailDraft?> load(String key) async {
    final rows = await (await _db).query(
      'email_drafts',
      where: 'draft_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromPayload(
      key,
      rows.single['thread_id'] as String?,
      rows.single['mode']! as String,
      rows.single['payload']! as String,
      rows.single['updated_at']! as int,
    );
  }

  @override
  Future<void> save(EmailDraft draft) async {
    await (await _db).insert(
      'email_drafts',
      {
        'draft_key': draft.key,
        'thread_id': draft.threadId,
        'mode': draft.mode.name,
        'payload': jsonEncode(_payload(draft)),
        'updated_at': draft.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String key) async {
    await (await _db).delete(
      'email_drafts',
      where: 'draft_key = ?',
      whereArgs: [key],
    );
  }

  Map<String, Object?> _payload(EmailDraft draft) => {
        'deltaJson': draft.deltaJson,
        'to': draft.to.map((item) => item.toJson()).toList(),
        'cc': draft.cc.map((item) => item.toJson()).toList(),
        'bcc': draft.bcc.map((item) => item.toJson()).toList(),
        'subject': draft.subject,
        'attachments': draft.attachments.map((item) => item.toJson()).toList(),
        'showQuotedHistory': draft.showQuotedHistory,
      };

  EmailDraft _fromPayload(
    String key,
    String? threadId,
    String mode,
    String payload,
    int updatedAt,
  ) {
    final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    List<EmailAddress> addresses(String field) => (data[field] as List)
        .map((item) =>
            EmailAddress.fromJson(Map<String, Object?>.from(item as Map)))
        .toList(growable: false);
    return EmailDraft(
      key: key,
      threadId: threadId,
      mode: EmailComposerMode.values.byName(mode),
      deltaJson: (data['deltaJson'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
      to: addresses('to'),
      cc: addresses('cc'),
      bcc: addresses('bcc'),
      subject: data['subject'] as String,
      attachments: (data['attachments'] as List)
          .map((item) =>
              EmailAttachment.fromJson(Map<String, Object?>.from(item as Map)))
          .toList(growable: false),
      showQuotedHistory: data['showQuotedHistory'] as bool,
    );
  }
}

class InMemoryEmailDraftRepository implements EmailDraftRepository {
  final _drafts = <String, EmailDraft>{};
  @override
  Future<EmailDraft?> load(String key) async => _drafts[key];
  @override
  Future<void> save(EmailDraft draft) async => _drafts[draft.key] = draft;
  @override
  Future<void> delete(String key) async => _drafts.remove(key);
}
