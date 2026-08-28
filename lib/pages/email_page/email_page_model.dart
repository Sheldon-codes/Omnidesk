import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'email_page_model.g.dart';

enum EmailFolder { inbox, pending, sent, starred, archived }

class EmailMessage {
  const EmailMessage({
    required this.sender,
    required this.subject,
    required this.preview,
    required this.time,
    required this.folders,
    this.isRead = false,
    this.ticketId,
    this.contactIdentifier,
    this.label,
  });

  final String sender;
  final String subject;
  final String preview;
  final String time;
  final Set<EmailFolder> folders;
  final bool isRead;
  final String? ticketId;
  final String? contactIdentifier;
  final String? label;
}

class EmailPageState {
  const EmailPageState({
    this.folder = EmailFolder.inbox,
    this.searchActive = false,
    this.query = '',
    this.messages = _emailFixtures,
  });

  final EmailFolder folder;
  final bool searchActive;
  final String query;
  final List<EmailMessage> messages;

  int get unreadCount => messages
      .where((message) => message.folders.contains(folder) && !message.isRead)
      .length;

  String get subtitle {
    switch (folder) {
      case EmailFolder.inbox:
        return '21 messages · 11 unread';
      case EmailFolder.pending:
        return '2 messages';
      case EmailFolder.sent:
        return '2 messages';
      case EmailFolder.starred:
        return '2 messages';
      case EmailFolder.archived:
        return '2 messages';
    }
  }

  List<EmailMessage> get filteredMessages {
    final normalized = query.trim().toLowerCase();
    return messages.where((message) {
      if (!message.folders.contains(folder)) return false;
      if (normalized.isEmpty) return true;
      return [
        message.sender,
        message.subject,
        message.preview,
        message.ticketId ?? '',
        message.contactIdentifier ?? '',
        message.label ?? '',
      ].any((value) => value.toLowerCase().contains(normalized));
    }).toList(growable: false);
  }

  EmailPageState copyWith({
    EmailFolder? folder,
    bool? searchActive,
    String? query,
  }) =>
      EmailPageState(
        folder: folder ?? this.folder,
        searchActive: searchActive ?? this.searchActive,
        query: query ?? this.query,
        messages: messages,
      );
}

const _emailFixtures = <EmailMessage>[
  EmailMessage(
    sender: 'accounts@bigbrainz.co.ke',
    subject: 'Fwd: SCHOOL MANAGEMENT SYSTEM',
    preview: 'Dear Chepkolon Green Highlands Academy. Thank you for your…',
    time: '08:18',
    folders: {EmailFolder.inbox, EmailFolder.starred},
    ticketId: 'DGKSL-386',
    contactIdentifier: 'accounts@bigbrainz.co.ke',
  ),
  EmailMessage(
    sender: 'MOI HIGH SCHOOL-KABARAK',
    subject: 'Requisition approval required',
    preview: 'Requisition(s) 12 are waiting for your approval. Please log in…',
    time: '12:16',
    folders: {EmailFolder.inbox, EmailFolder.pending},
    ticketId: 'DGKSL-360',
  ),
  EmailMessage(
    sender: 'MOI HIGH SCHOOL-KABARAK',
    subject: 'Requisition approval required - #13',
    preview: 'Requisition #13 is waiting for your Authorized by Finance ac…',
    time: '12:16',
    folders: {EmailFolder.inbox, EmailFolder.pending},
    ticketId: 'DGKSL-361',
  ),
  EmailMessage(
    sender: '15919574681@163.com',
    subject: "From China to Mombasa USD 4300/40'HQ",
    preview: 'Special rate！！！ NS MOMBASA USD3000/4300 Lo…',
    time: '12:09',
    folders: {EmailFolder.inbox},
    ticketId: 'DGKSL-365',
    isRead: true,
  ),
  EmailMessage(
    sender: 'lagatgideon70@gmail.com',
    subject: 'Widget: Can I talk to an agent?',
    preview: 'Which school we check?',
    time: '08:32',
    folders: {EmailFolder.inbox, EmailFolder.sent},
    ticketId: 'DGKSL-211',
  ),
  EmailMessage(
    sender: 'cheserekhillary@gmail.com',
    subject: 'Widget: How do I add an allowance?',
    preview: 'Yes, go to HR&Payroll >> One off Allowances, select the mo…',
    time: '08:30',
    folders: {EmailFolder.inbox, EmailFolder.archived},
    ticketId: 'DGKSL-263',
    isRead: true,
  ),
  EmailMessage(
    sender: 'cheserekhillary@gmail.com',
    subject: 'Widget: How do I send fee balances?',
    preview: 'How do I send fee balances?',
    time: '08:29',
    folders: {EmailFolder.inbox, EmailFolder.sent},
    ticketId: 'DGKSL-271',
    isRead: true,
  ),
  EmailMessage(
    sender: 'Tony Kirui Sunshine',
    subject: 'Fwd: Teacher accounts for Sunshine Primary',
    preview: 'Attached is the data for the Sunshine Primary teachers.',
    time: 'Yesterday',
    folders: {EmailFolder.sent, EmailFolder.starred},
    contactIdentifier: 'kirui-mac@gmail.com',
    isRead: true,
  ),
  EmailMessage(
    sender: 'support@omnidesk.africa',
    subject: 'Ticket update: DGKSL-302',
    preview: 'Your ticket has been updated and is awaiting a response.',
    time: 'Mon',
    folders: {EmailFolder.archived},
    ticketId: 'DGKSL-302',
    isRead: true,
  ),
];

@riverpod
class EmailPageNotifier extends _$EmailPageNotifier {
  @override
  EmailPageState build() => const EmailPageState();

  void selectFolder(EmailFolder folder) {
    state = state.copyWith(folder: folder, searchActive: false, query: '');
  }

  void openSearch() => state = state.copyWith(searchActive: true);

  void closeSearch() => state = state.copyWith(searchActive: false, query: '');

  void setSearchQuery(String value) => state = state.copyWith(query: value);
}
