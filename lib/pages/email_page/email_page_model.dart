import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/api_service.dart';

part 'email_page_model.g.dart';

const agentMailbox = 'support@omnidesk.africa';

enum EmailFolder { inbox, pending, sent, starred, archived }

enum EmailDirection { inbound, outbound }

enum EmailAttachmentDisposition { attachment, inline }

enum EmailAttachmentSecurity { safe, blocked, unsupported }

enum EmailAttachmentUploadState {
  localReady,
  preparing,
  uploading,
  failed,
  uploaded
}

enum EmailComposerMode { newMessage, reply, replyAll, forward }

class EmailAddress {
  const EmailAddress({required this.address, this.name});
  final String address;
  final String? name;
  String get normalized => address.trim().toLowerCase();
  String get label => name == null || name!.trim().isEmpty ? address : name!;
  bool get isValid =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized);
  Map<String, Object?> toJson() => {'address': address, 'name': name};
  factory EmailAddress.fromJson(Map<String, Object?> json) => EmailAddress(
        address: json['address']! as String,
        name: json['name'] as String?,
      );
}

class EmailBody {
  const EmailBody({
    required this.plainText,
    this.html,
    this.direction = TextDirection.ltr,
    this.forwarded = false,
  });
  final String plainText;
  final String? html;
  final TextDirection direction;
  final bool forwarded;
}

class EmailAttachment {
  const EmailAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.byteCount,
    this.disposition = EmailAttachmentDisposition.attachment,
    this.security = EmailAttachmentSecurity.safe,
    this.uploadState = EmailAttachmentUploadState.localReady,
    this.localPath,
    this.contentId,
    this.previewAssetPath,
    this.failureMessage,
  });
  final String id;
  final String filename;
  final String mimeType;
  final int byteCount;
  final EmailAttachmentDisposition disposition;
  final EmailAttachmentSecurity security;
  final EmailAttachmentUploadState uploadState;
  final String? localPath;
  final String? contentId;
  final String? previewAssetPath;
  final String? failureMessage;
  bool get isImage => mimeType.startsWith('image/');
  bool get isBlocked => security != EmailAttachmentSecurity.safe;
  EmailAttachment copyWith(
          {EmailAttachmentUploadState? uploadState, String? failureMessage}) =>
      EmailAttachment(
        id: id,
        filename: filename,
        mimeType: mimeType,
        byteCount: byteCount,
        disposition: disposition,
        security: security,
        uploadState: uploadState ?? this.uploadState,
        localPath: localPath,
        contentId: contentId,
        previewAssetPath: previewAssetPath,
        failureMessage: failureMessage ?? this.failureMessage,
      );
  Map<String, Object?> toJson() => {
        'id': id,
        'filename': filename,
        'mimeType': mimeType,
        'byteCount': byteCount,
        'disposition': disposition.name,
        'security': security.name,
        'uploadState': uploadState.name,
        'localPath': localPath,
        'contentId': contentId,
        'previewAssetPath': previewAssetPath,
        'failureMessage': failureMessage,
      };
  factory EmailAttachment.fromJson(Map<String, Object?> json) =>
      EmailAttachment(
        id: json['id']! as String,
        filename: json['filename']! as String,
        mimeType: json['mimeType']! as String,
        byteCount: json['byteCount']! as int,
        disposition: EmailAttachmentDisposition.values
            .byName(json['disposition']! as String),
        security:
            EmailAttachmentSecurity.values.byName(json['security']! as String),
        uploadState: EmailAttachmentUploadState.values
            .byName(json['uploadState']! as String),
        localPath: json['localPath'] as String?,
        contentId: json['contentId'] as String?,
        previewAssetPath: json['previewAssetPath'] as String?,
        failureMessage: json['failureMessage'] as String?,
      );
}

class EmailThreadMessage {
  const EmailThreadMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.sentAt,
    required this.direction,
    required this.body,
    this.replyTo,
    this.cc = const [],
    this.bcc = const [],
    this.attachments = const [],
    this.messageId,
  });
  final String id;
  final EmailAddress from;
  final List<EmailAddress> to;
  final List<EmailAddress> cc;
  final List<EmailAddress> bcc;
  final EmailAddress? replyTo;
  final DateTime sentAt;
  final EmailDirection direction;
  final EmailBody body;
  final List<EmailAttachment> attachments;
  final String? messageId;
}

class EmailThread {
  const EmailThread({
    required this.id,
    required this.subject,
    required this.messages,
    required this.folders,
    this.ticketId,
    this.customerId,
    this.unread = false,
    this.starred = false,
    this.deleted = false,
    this.pendingContext,
  });
  final String id;
  final String subject;
  final List<EmailThreadMessage> messages;
  final Set<EmailFolder> folders;
  final String? ticketId;
  final String? customerId;
  final bool unread;
  final bool starred;
  final bool deleted;
  final String? pendingContext;
  EmailThreadMessage get latestMessage => messages.last;
  String get sender => latestMessage.from.label;
  String get preview =>
      latestMessage.body.plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
  String get timeLabel => _relativeTime(latestMessage.sentAt);
  EmailThread copyWith({
    List<EmailThreadMessage>? messages,
    Set<EmailFolder>? folders,
    bool? unread,
    bool? starred,
    bool? deleted,
  }) =>
      EmailThread(
        id: id,
        subject: subject,
        messages: messages ?? this.messages,
        folders: folders ?? this.folders,
        ticketId: ticketId,
        customerId: customerId,
        unread: unread ?? this.unread,
        starred: starred ?? this.starred,
        deleted: deleted ?? this.deleted,
        pendingContext: pendingContext,
      );
}

class EmailDraft {
  const EmailDraft({
    required this.key,
    required this.mode,
    required this.deltaJson,
    required this.updatedAt,
    this.threadId,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.attachments = const [],
    this.showQuotedHistory = false,
  });
  final String key;
  final String? threadId;
  final EmailComposerMode mode;
  final List<Map<String, dynamic>> deltaJson;
  final DateTime updatedAt;
  final List<EmailAddress> to;
  final List<EmailAddress> cc;
  final List<EmailAddress> bcc;
  final String subject;
  final List<EmailAttachment> attachments;
  final bool showQuotedHistory;
  EmailDraft copyWith({
    List<Map<String, dynamic>>? deltaJson,
    List<EmailAddress>? to,
    List<EmailAddress>? cc,
    List<EmailAddress>? bcc,
    String? subject,
    List<EmailAttachment>? attachments,
    bool? showQuotedHistory,
    DateTime? updatedAt,
  }) =>
      EmailDraft(
          key: key,
          threadId: threadId,
          mode: mode,
          deltaJson: deltaJson ?? this.deltaJson,
          updatedAt: updatedAt ?? this.updatedAt,
          to: to ?? this.to,
          cc: cc ?? this.cc,
          bcc: bcc ?? this.bcc,
          subject: subject ?? this.subject,
          attachments: attachments ?? this.attachments,
          showQuotedHistory: showQuotedHistory ?? this.showQuotedHistory);
}

abstract class EmailRepository {
  Future<List<EmailThread>> loadFolder(EmailFolder folder,
      {String query = '', int page = 1, int perPage = 20});
  Future<EmailThread> loadThread(String id);
  Future<void> markRead(String id);
  Future<void> reply(String id, String message, {EmailAttachment? attachment});
  Future<EmailThread> create(
      {required String to,
      String? customerName,
      required String subject,
      required String message});
  Future<void> updateStatus(String id, String status);
}

class LocalEmailRepository implements EmailRepository {
  const LocalEmailRepository();
  @override
  Future<List<EmailThread>> loadFolder(EmailFolder folder,
          {String query = '', int page = 1, int perPage = 20}) async =>
      _emailFixtures.where((t) => t.folders.contains(folder)).toList();
  @override
  Future<EmailThread> loadThread(String id) async =>
      _emailFixtures.firstWhere((t) => t.id == id);
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> reply(String id, String message,
      {EmailAttachment? attachment}) async {}
  @override
  Future<EmailThread> create(
          {required String to,
          String? customerName,
          required String subject,
          required String message}) async =>
      _emailFixtures.first;
  @override
  Future<void> updateStatus(String id, String status) async {}
}

class RemoteEmailRepository implements EmailRepository {
  RemoteEmailRepository(this._api);
  final ApiService _api;

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, val) => MapEntry(key.toString(), val))
      : <String, dynamic>{};

  @override
  Future<List<EmailThread>> loadFolder(EmailFolder folder,
      {String query = '', int page = 1, int perPage = 20}) async {
    final statuses = switch (folder) {
      EmailFolder.inbox => const ['open'],
      EmailFolder.pending => const ['pending'],
      EmailFolder.sent => const ['in_progress', 'resolved'],
      EmailFolder.archived => const ['closed'],
      EmailFolder.starred => const [null],
    };
    final results = <EmailThread>[];
    for (final status in statuses) {
      final response = await _api.get('/tickets', queryParameters: {
        'source': 'email',
        'assigned': 'me',
        'per_page': perPage,
        'page': page,
        if (status != null) 'status': status,
        if (folder == EmailFolder.starred) 'priority': 'urgent',
        if (query.trim().isNotEmpty) 'search': query.trim(),
      });
      final data = response is Map ? response['data'] : null;
      if (data is List) {
        results.addAll(
            data.whereType<Map>().map((item) => _summary(_map(item), folder)));
      }
    }
    final deduped = <String, EmailThread>{
      for (final item in results) item.id: item
    };
    return deduped.values.toList(growable: false);
  }

  EmailThread _summary(Map<String, dynamic> item, EmailFolder folder) {
    final customer = _map(item['customer']);
    final id = (item['id'] ?? item['display_number']).toString();
    final subject = (item['subject'] ?? '(No subject)').toString();
    final address = (customer['email'] ?? '').toString();
    final sentAt = DateTime.tryParse(
            (item['updated_at'] ?? item['created_at'] ?? '').toString()) ??
        DateTime.now();
    final message = EmailThreadMessage(
        id: '$id-summary',
        from: EmailAddress(
            address: address.isEmpty ? 'unknown@example.com' : address,
            name: customer['name']?.toString()),
        to: const [EmailAddress(address: agentMailbox)],
        sentAt: sentAt,
        direction: EmailDirection.inbound,
        body: EmailBody(plainText: subject));
    final folders = <EmailFolder>{folder};
    if (folder == EmailFolder.inbox && item['status'] == 'open') {
      folders.add(EmailFolder.inbox);
    }
    return EmailThread(
        id: id,
        subject: subject,
        messages: [message],
        folders: folders,
        ticketId: item['display_number']?.toString(),
        customerId: customer['id']?.toString(),
        unread: item['unread'] == true || item['agent_seen'] == false,
        starred: folder == EmailFolder.starred);
  }

  @override
  Future<EmailThread> loadThread(String id) async {
    final ticketResponse = await _api.get('/tickets/$id');
    final ticket =
        _map(ticketResponse is Map ? ticketResponse['ticket'] : null);
    final timelineResponse = await _api.get('/tickets/$id/timeline');
    final timeline =
        timelineResponse is Map ? timelineResponse['timeline'] : null;
    final base =
        _summary(ticket, _folderForStatus(ticket['status']?.toString()));
    final messages = timeline is List
        ? timeline.whereType<Map>().map(_timelineMessage).toList()
        : <EmailThreadMessage>[];
    return base.copyWith(messages: messages.isEmpty ? base.messages : messages);
  }

  EmailFolder _folderForStatus(String? status) => status == 'closed'
      ? EmailFolder.archived
      : status == 'pending'
          ? EmailFolder.pending
          : EmailFolder.inbox;
  EmailThreadMessage _timelineMessage(Map raw) {
    final item = _map(raw);
    final fromCustomer = item['is_from_customer'] == true;
    final text = (item['description'] ?? '').toString();
    final at = DateTime.tryParse((item['created_at'] ?? '').toString()) ??
        DateTime.now();
    return EmailThreadMessage(
        id: (item['id'] ?? at.microsecondsSinceEpoch).toString(),
        from: EmailAddress(
            address: fromCustomer ? 'customer@example.com' : agentMailbox,
            name: fromCustomer ? 'Customer' : 'OmniDesk Support'),
        to: const [EmailAddress(address: agentMailbox)],
        sentAt: at,
        direction:
            fromCustomer ? EmailDirection.inbound : EmailDirection.outbound,
        body: EmailBody(plainText: text),
        attachments: item['media_url'] == null
            ? const []
            : [
                EmailAttachment(
                    id: 'media-${item['id']}',
                    filename:
                        (item['media_filename'] ?? 'attachment').toString(),
                    mimeType: (item['media_type'] ?? 'application/octet-stream')
                        .toString(),
                    byteCount: 0)
              ]);
  }

  @override
  Future<void> markRead(String id) async {
    await _api.post('/tickets/$id/mark-read', {});
  }

  @override
  Future<void> reply(String id, String message,
      {EmailAttachment? attachment}) async {
    final payload = <String, dynamic>{'channel': 'email', 'message': message};
    if (attachment != null) {
      final path = attachment.localPath;
      if (path == null || path.isEmpty) {
        throw StateError('The selected attachment is not available locally.');
      }
      final file = File(path);
      if (!await file.exists()) {
        throw StateError('The selected attachment could not be found.');
      }
      payload.addAll({
        'media_data': base64Encode(await file.readAsBytes()),
        'media_type': attachment.mimeType,
        'media_filename': attachment.filename,
      });
    }
    await _api.post('/tickets/$id/reply', payload);
  }

  @override
  Future<EmailThread> create(
      {required String to,
      String? customerName,
      required String subject,
      required String message}) async {
    final response = await _api.post('/tickets', {
      'subject': subject,
      'description': message,
      'customer_email': to,
      if (customerName != null && customerName.trim().isNotEmpty)
        'customer_name': customerName.trim(),
      'priority': 'medium',
      'source': 'email'
    });
    return _summary(
        _map(response is Map ? response['ticket'] : null), EmailFolder.sent);
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    await _api.post('/tickets/$id/status', {'status': status});
  }
}

final emailRepositoryProvider = Provider<EmailRepository>(
    (ref) => RemoteEmailRepository(ref.read(apiServiceProvider)));

class EmailStoreState {
  const EmailStoreState(
      {required this.threads,
      this.loading = false,
      this.error,
      this.loadedFolder});
  final List<EmailThread> threads;
  final bool loading;
  final Object? error;
  final EmailFolder? loadedFolder;
  EmailThread? findThread(String id) =>
      threads.firstWhereOrNull((item) => item.id == id && !item.deleted);
}

final emailStoreProvider =
    NotifierProvider<EmailStore, EmailStoreState>(EmailStore.new);

class EmailStore extends Notifier<EmailStoreState> {
  @override
  EmailStoreState build() => EmailStoreState(threads: _emailFixtures);
  Future<void> loadFolder(EmailFolder folder, {String query = ''}) async {
    state = EmailStoreState(
        threads: state.threads, loading: true, loadedFolder: folder);
    try {
      final threads = await ref
          .read(emailRepositoryProvider)
          .loadFolder(folder, query: query);
      state = EmailStoreState(threads: threads, loadedFolder: folder);
    } catch (error) {
      state = EmailStoreState(
          threads: state.threads, error: error, loadedFolder: folder);
    }
  }

  Future<void> refresh(EmailFolder folder, {String query = ''}) =>
      loadFolder(folder, query: query);
  EmailThread? findById(String id) => state.findThread(id);
  Future<void> openThread(String id) async {
    _replace(id, (item) => item.copyWith(unread: false));
    try {
      await ref.read(emailRepositoryProvider).markRead(id);
    } catch (_) {}
  }

  void markUnread(String id) =>
      _replace(id, (item) => item.copyWith(unread: true));
  void toggleStar(String id) => _replace(id, (item) {
        final folders = {...item.folders};
        item.starred
            ? folders.remove(EmailFolder.starred)
            : folders.add(EmailFolder.starred);
        return item.copyWith(folders: folders, starred: !item.starred);
      });
  void archive(String id) => _replace(id, (item) {
        final folders = {...item.folders}
          ..remove(EmailFolder.inbox)
          ..remove(EmailFolder.pending)
          ..add(EmailFolder.archived);
        return item.copyWith(folders: folders);
      });
  void delete(String id) =>
      _replace(id, (item) => item.copyWith(deleted: true));
  void appendOutgoing(String id, EmailThreadMessage message) => _replace(
      id, (item) => item.copyWith(messages: [...item.messages, message]));
  void createSentThread(EmailThread thread) =>
      state = EmailStoreState(threads: [thread, ...state.threads]);
  void _replace(String id, EmailThread Function(EmailThread) update) =>
      state = EmailStoreState(threads: [
        for (final item in state.threads)
          if (item.id == id) update(item) else item
      ]);

  Future<void> reply(String id, String message,
      {EmailAttachment? attachment}) async {
    await ref
        .read(emailRepositoryProvider)
        .reply(id, message, attachment: attachment);
    final thread = findById(id);
    if (thread != null) await loadThread(id);
  }

  Future<void> loadThread(String id) async {
    final thread = await ref.read(emailRepositoryProvider).loadThread(id);
    _replace(id, (_) => thread);
  }

  Future<EmailThread> createRemote(
      {required String to,
      String? customerName,
      required String subject,
      required String message}) async {
    final thread = await ref.read(emailRepositoryProvider).create(
        to: to, customerName: customerName, subject: subject, message: message);
    createSentThread(thread);
    return thread;
  }

  Future<void> updateStatus(String id, String status) async {
    await ref.read(emailRepositoryProvider).updateStatus(id, status);
  }
}

final emailThreadProvider = Provider.family<EmailThread?, String>(
    (ref, id) => ref.watch(emailStoreProvider).findThread(id));

class EmailPageState {
  EmailPageState({
    this.folder = EmailFolder.inbox,
    this.searchActive = false,
    this.query = '',
    List<EmailThread>? threads,
  }) : threads = threads ?? _emailFixtures;
  final EmailFolder folder;
  final bool searchActive;
  final String query;
  final List<EmailThread> threads;
  int get unreadCount => threads
      .where((item) => item.folders.contains(folder) && item.unread)
      .length;
  String get subtitle => switch (folder) {
        EmailFolder.inbox => '21 messages · 11 unread',
        EmailFolder.pending => '2 messages',
        EmailFolder.sent => '2 messages',
        EmailFolder.starred => '2 messages',
        EmailFolder.archived => '2 messages',
      };
  List<EmailThread> get filteredMessages => filteredThreads;
  List<EmailThread> get filteredThreads {
    final needle = query.trim().toLowerCase();
    return threads.where((item) {
      if (item.deleted || !item.folders.contains(folder)) return false;
      if (needle.isEmpty) return true;
      return [
        item.sender,
        item.subject,
        item.preview,
        item.ticketId ?? '',
        item.latestMessage.from.address
      ].any((value) => value.toLowerCase().contains(needle));
    }).toList(growable: false);
  }

  EmailPageState copyWith(
          {EmailFolder? folder,
          bool? searchActive,
          String? query,
          List<EmailThread>? threads}) =>
      EmailPageState(
          folder: folder ?? this.folder,
          searchActive: searchActive ?? this.searchActive,
          query: query ?? this.query,
          threads: threads ?? this.threads);
}

@riverpod
class EmailPageNotifier extends _$EmailPageNotifier {
  @override
  EmailPageState build() => EmailPageState();
  void selectFolder(EmailFolder folder) =>
      state = state.copyWith(folder: folder, searchActive: false, query: '');
  void openSearch() => state = state.copyWith(searchActive: true);
  void closeSearch() => state = state.copyWith(searchActive: false, query: '');
  void setSearchQuery(String value) => state = state.copyWith(query: value);
}

String emailDraftKey({String? threadId, required EmailComposerMode mode}) =>
    '$agentMailbox:${threadId ?? 'new'}:${mode.name}';
String _relativeTime(DateTime date) => '${date.day}/${date.month}';

final _emailFixtures = <EmailThread>[
  EmailThread(
    id: 'shipping-rates',
    subject: "From China to Mombasa USD 4300/40'HQ",
    ticketId: 'DGKSL-365',
    folders: const {EmailFolder.inbox},
    messages: [
      EmailThreadMessage(
          id: 'shipping-older',
          from: const EmailAddress(
              address: 'tonny.kirui@example.com', name: 'Tonny Kirui'),
          to: const [EmailAddress(address: agentMailbox)],
          sentAt: DateTime(2026, 8, 16, 10, 9),
          direction: EmailDirection.inbound,
          body: const EmailBody(
              plainText:
                  'Please share the August freight rates when available.')),
      EmailThreadMessage(
          id: 'shipping-latest',
          from: const EmailAddress(address: '15919574681@163.com'),
          to: const [EmailAddress(address: agentMailbox)],
          replyTo: const EmailAddress(address: '15919574681@163.com'),
          sentAt: DateTime(2026, 8, 17, 13, 34),
          direction: EmailDirection.inbound,
          body: const EmailBody(
              plainText:
                  'Special rate!!!!\n\nNS\n\nMOMBASA  USD3000/4300\nLome  USD3200/4400\nApapa  USD4200/5300\nDakar  USD4270/4520\nAbidjan  USD3208/4420\n\nMOB: +86 15919574681',
              html:
                  '<p>Special rate!!!!</p><p><strong>NS</strong></p><table><thead><tr><th>Port</th><th>Rate</th></tr></thead><tbody><tr><td>MOMBASA</td><td>USD3000/4300</td></tr><tr><td>Lome</td><td>USD3200/4400</td></tr><tr><td>Apapa</td><td>USD4200/5300</td></tr><tr><td>Dakar</td><td>USD4270/4520</td></tr><tr><td>Abidjan</td><td>USD3208/4420</td></tr></tbody></table><p>MOB: <a href="tel:+8615919574681">+86 15919574681</a></p>'),
          attachments: const [
            EmailAttachment(
                id: 'shipping-pdf',
                filename: 'Shipping_Rates_August.pdf',
                mimeType: 'application/pdf',
                byteCount: 1843200)
          ]),
    ],
  ),
  EmailThread(
      id: 'school-management',
      subject: 'Fwd: SCHOOL MANAGEMENT SYSTEM',
      ticketId: 'DGKSL-386',
      unread: true,
      starred: true,
      folders: const {
        EmailFolder.inbox,
        EmailFolder.starred
      },
      messages: [
        EmailThreadMessage(
            id: 'school-management-latest',
            from: const EmailAddress(address: 'accounts@bigbrainz.co.ke'),
            to: const [EmailAddress(address: agentMailbox)],
            sentAt: DateTime(2026, 8, 17, 8, 18),
            direction: EmailDirection.inbound,
            body: const EmailBody(
                plainText:
                    'Dear Chepkolon Green Highlands Academy. Thank you for your request.',
                html:
                    '<p>Dear Chepkolon Green Highlands Academy,</p><blockquote><p>---------- Forwarded message ----------</p><p>Thank you for your request.</p></blockquote>',
                forwarded: true))
      ]),
  EmailThread(
      id: 'requisition-12',
      subject: 'Requisition approval required',
      ticketId: 'DGKSL-360',
      unread: true,
      pendingContext: 'Pending',
      folders: const {
        EmailFolder.inbox,
        EmailFolder.pending
      },
      messages: [
        EmailThreadMessage(
            id: 'requisition-12-latest',
            from: const EmailAddress(
                address: 'approvals@moi-kabarak.ac.ke',
                name: 'MOI HIGH SCHOOL-KABARAK'),
            to: const [EmailAddress(address: agentMailbox)],
            sentAt: DateTime(2026, 8, 17, 12, 16),
            direction: EmailDirection.inbound,
            body: const EmailBody(
                plainText:
                    'Requisition(s) 12 are waiting for your approval. Please log in to review.'))
      ]),
  EmailThread(
      id: 'widget-agent',
      subject: 'Widget: Can I talk to an agent?',
      ticketId: 'DGKSL-211',
      unread: true,
      folders: const {EmailFolder.inbox, EmailFolder.sent},
      customerId: 'aloise-obaga',
      messages: [
        EmailThreadMessage(
            id: 'widget-agent-latest',
            from: const EmailAddress(
                address: 'aloise.obaga@example.com',
                name: 'Aloise Obaga Kaizen School'),
            to: const [EmailAddress(address: agentMailbox)],
            sentAt: DateTime(2026, 8, 17, 8, 32),
            direction: EmailDirection.inbound,
            body: const EmailBody(plainText: 'Which school should we check?'))
      ]),
  EmailThread(
      id: 'teacher-accounts',
      subject: 'Fwd: Teacher accounts for Sunshine Primary',
      folders: const {EmailFolder.sent, EmailFolder.starred},
      starred: true,
      messages: [
        EmailThreadMessage(
            id: 'teacher-accounts-latest',
            from: const EmailAddress(
                address: agentMailbox, name: 'OmniDesk Support'),
            to: const [
              EmailAddress(
                  address: 'kirui-mac@gmail.com', name: 'Tony Kirui Sunshine')
            ],
            sentAt: DateTime(2026, 8, 16, 10, 9),
            direction: EmailDirection.outbound,
            body: const EmailBody(
                plainText:
                    'Attached is the data for the Sunshine Primary teachers.'))
      ]),
  EmailThread(
      id: 'fee-balances',
      subject: 'Widget: How do I send fee balances?',
      ticketId: 'DGKSL-271',
      folders: const {
        EmailFolder.inbox,
        EmailFolder.sent
      },
      messages: [
        EmailThreadMessage(
            id: 'fee-balances-latest',
            from: const EmailAddress(address: 'cheserekhillary@gmail.com'),
            to: const [EmailAddress(address: agentMailbox)],
            sentAt: DateTime(2026, 8, 17, 8, 29),
            direction: EmailDirection.inbound,
            body: const EmailBody(plainText: 'How do I send fee balances?'))
      ]),
  EmailThread(
      id: 'rich-html-preview',
      subject: 'HTML email preview — content coverage',
      ticketId: 'DGKSL-402',
      unread: true,
      folders: const {
        EmailFolder.inbox
      },
      messages: [
        EmailThreadMessage(
          id: 'rich-html-original',
          from: const EmailAddress(
              address: 'design@acme.example', name: 'Acme Design Team'),
          to: const [EmailAddress(address: agentMailbox)],
          sentAt: DateTime(2026, 8, 18, 9, 12),
          direction: EmailDirection.inbound,
          body: const EmailBody(
              plainText:
                  'Original plain-text fallback. This message demonstrates an HTML email.',
              html:
                  '<p>Original plain-text fallback. This message demonstrates an HTML email.</p>'),
        ),
        EmailThreadMessage(
          id: 'rich-html-latest',
          from: const EmailAddress(
              address: 'design@acme.example', name: 'Acme Design Team'),
          replyTo: const EmailAddress(address: 'reply@acme.example'),
          to: const [EmailAddress(address: agentMailbox)],
          cc: const [EmailAddress(address: 'operations@omnidesk.africa')],
          sentAt: DateTime(2026, 8, 18, 9, 25),
          direction: EmailDirection.inbound,
          messageId: '<html-preview-402@acme.example>',
          body: const EmailBody(
            plainText:
                'HTML email preview\n\nHeadings, lists, links, quoted content, code, a table, a remote image prompt, and RTL text are included.',
            html:
                '<h1>HTML email preview</h1><p>This fixture exercises the supported reader content in one message.</p><h2>Checklist</h2><ul><li>Headings and paragraphs</li><li><strong>Bold</strong>, <em>italic</em>, and <u>underlined</u> text</li><li><a href="https://example.com/release-notes">Confirmed external link</a></li><li><a href="mailto:reply@acme.example">Email reply</a> and <a href="tel:+254723506031">call link</a></li></ul><ol><li>First ordered item</li><li>Second ordered item</li></ol><blockquote><p>Quoted customer context is shown in a restrained block.</p></blockquote><pre>curl --request POST /v1/messages\n# code / preformatted content</pre><table><thead><tr><th>Channel</th><th>Status</th></tr></thead><tbody><tr><td>Email</td><td>Ready</td></tr><tr><td>Attachment</td><td>Local-ready</td></tr></tbody></table><p><img src="https://example.com/tracking-pixel.png" alt="Remote image test"></p><p dir="rtl">مرحبا، هذه رسالة اختبار باللغة العربية.</p><hr><p>Thanks,<br>Acme Design Team</p>',
          ),
          attachments: const [
            EmailAttachment(
              id: 'html-preview-image',
              filename: 'reader-preview.png',
              mimeType: 'image/png',
              byteCount: 482310,
              disposition: EmailAttachmentDisposition.inline,
              contentId: 'reader-preview',
            ),
            EmailAttachment(
              id: 'html-preview-document',
              filename: 'content-coverage.pdf',
              mimeType: 'application/pdf',
              byteCount: 98765,
            ),
          ],
        ),
      ]),
  EmailThread(
      id: 'ticket-update',
      subject: 'Ticket update: DGKSL-302',
      ticketId: 'DGKSL-302',
      pendingContext: 'Awaiting customer response',
      folders: const {
        EmailFolder.pending,
        EmailFolder.archived
      },
      messages: [
        EmailThreadMessage(
            id: 'ticket-update-latest',
            from: const EmailAddress(
                address: agentMailbox, name: 'OmniDesk Support'),
            to: const [EmailAddress(address: 'customer@example.com')],
            sentAt: DateTime(2026, 8, 14, 10),
            direction: EmailDirection.outbound,
            body: const EmailBody(
                plainText:
                    'Your ticket has been updated and is awaiting a response.'))
      ]),
];
