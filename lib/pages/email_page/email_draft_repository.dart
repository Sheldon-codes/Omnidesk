import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../services/app_local_database.dart';
import 'email_page_model.dart';

abstract class EmailDraftRepository {
  Future<EmailDraft?> load(String key);
  Future<void> save(EmailDraft draft);
  Future<void> delete(String key);
}

class SqliteEmailDraftRepository implements EmailDraftRepository {
  SqliteEmailDraftRepository({
    AppLocalDatabase? localDatabase,
    required String scopeKey,
  })  : _localDatabase = localDatabase ?? AppLocalDatabase(),
        _scopeKey = Uri.encodeComponent(scopeKey);

  final AppLocalDatabase _localDatabase;
  final String _scopeKey;

  String _storageKey(String key) => '$_scopeKey::$key';

  Future<Database> get _db => _localDatabase.database;

  @override
  Future<EmailDraft?> load(String key) async {
    final db = await _db;
    final scopedKey = _storageKey(key);
    var rows = await db.query(
      'email_drafts',
      where: 'draft_key = ?',
      whereArgs: [scopedKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      // One-time adoption of drafts created before account/workspace scoping.
      // The old format was device-local and single-account; move it atomically
      // into the currently authenticated partition on first use.
      rows = await db.query(
        'email_drafts',
        where: 'draft_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await db.transaction((transaction) async {
          final row = Map<String, Object?>.from(rows.single)
            ..['draft_key'] = scopedKey;
          await transaction.insert('email_drafts', row,
              conflictAlgorithm: ConflictAlgorithm.ignore);
          await transaction
              .delete('email_drafts', where: 'draft_key = ?', whereArgs: [key]);
        });
      }
    }
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
        'draft_key': _storageKey(draft.key),
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
      whereArgs: [_storageKey(key)],
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
