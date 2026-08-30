import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TicketStatus { open, inProgress, overdue, escalated, resolved }

enum TicketPriority { low, medium, high }

enum TicketSource { manual, widget, call, whatsapp, email }

enum TicketActivityType {
  created,
  assigned,
  reassigned,
  statusChanged,
  callCompleted,
  messageReceived,
  emailReceived,
  resolved,
  reopened,
  noteAdded,
}

extension TicketStatusX on TicketStatus {
  String get label => switch (this) {
        TicketStatus.open => 'Open',
        TicketStatus.inProgress => 'In progress',
        TicketStatus.overdue => 'Overdue',
        TicketStatus.escalated => 'Escalated',
        TicketStatus.resolved => 'Resolved',
      };
}

extension TicketPriorityX on TicketPriority {
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
}

extension TicketSourceX on TicketSource {
  String get label => switch (this) {
        TicketSource.manual => 'Manual',
        TicketSource.widget => 'Widget Chat',
        TicketSource.call => 'Phone',
        TicketSource.whatsapp => 'WhatsApp',
        TicketSource.email => 'Email',
      };
}

class TicketCapabilities {
  const TicketCapabilities({
    this.canEdit = true,
    this.canReassign = true,
    this.canChangeStatus = true,
    this.canResolve = true,
    this.canDelete = true,
  });
  final bool canEdit;
  final bool canReassign;
  final bool canChangeStatus;
  final bool canResolve;
  final bool canDelete;
}

class TicketDescription {
  const TicketDescription({required this.plainText, this.html});
  final String plainText;
  final String? html;
}

class TicketResolution {
  const TicketResolution({
    required this.note,
    required this.resolvedBy,
    required this.resolvedAt,
    this.template,
  });
  final String note;
  final String resolvedBy;
  final DateTime resolvedAt;
  final String? template;
}

class TicketCall {
  const TicketCall({
    required this.id,
    required this.direction,
    required this.occurredAt,
    this.duration = Duration.zero,
    this.connected = false,
    this.recordingAsset,
  });
  final String id;
  final String direction;
  final DateTime occurredAt;
  final Duration duration;
  final bool connected;
  final String? recordingAsset;
  bool get hasRecording => connected && recordingAsset != null;
}

sealed class TicketSourceContext {
  const TicketSourceContext();
}

class TicketPhoneSourceContext extends TicketSourceContext {
  const TicketPhoneSourceContext({this.calls = const []});
  final List<TicketCall> calls;
}

class TicketConversationSourceContext extends TicketSourceContext {
  const TicketConversationSourceContext(
      {required this.conversationId,
      required this.preview,
      required this.channel});
  final String conversationId;
  final String preview;
  final TicketSource channel;
}

class TicketEmailSourceContext extends TicketSourceContext {
  const TicketEmailSourceContext(
      {required this.threadId, required this.preview, required this.from});
  final String threadId;
  final String preview;
  final String from;
}

class TicketManualSourceContext extends TicketSourceContext {
  const TicketManualSourceContext();
}

class TicketActivity {
  const TicketActivity(
      {required this.id,
      required this.type,
      required this.title,
      required this.timestamp,
      this.description,
      this.actor});
  final String id;
  final TicketActivityType type;
  final String title;
  final DateTime timestamp;
  final String? description;
  final String? actor;
}

class TicketRecord {
  const TicketRecord({
    required this.id,
    required this.subject,
    required this.customerLabel,
    required this.sourceActor,
    required this.source,
    required this.status,
    required this.priority,
    required this.department,
    required this.description,
    required this.assignedAgent,
    required this.createdAt,
    required this.updatedAt,
    required this.sourceContext,
    this.customerId,
    this.category,
    this.sla,
    this.contactIdentifier,
    this.resolution,
    this.activities = const [],
    this.revision = 1,
    this.deleted = false,
    this.capabilities = const TicketCapabilities(),
  });
  final String id;
  final String subject;
  final String customerLabel;
  final String sourceActor;
  final String? customerId;
  final TicketSource source;
  final TicketStatus status;
  final TicketPriority priority;
  final String department;
  final String? category;
  final String? sla;
  final String? contactIdentifier;
  final TicketDescription description;
  final String assignedAgent;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TicketResolution? resolution;
  final TicketSourceContext sourceContext;
  final List<TicketActivity> activities;
  final int revision;
  final bool deleted;
  final TicketCapabilities capabilities;
  String get customer => customerLabel;

  TicketRecord copyWith({
    String? subject,
    String? customerLabel,
    String? customerId,
    String? contactIdentifier,
    TicketStatus? status,
    TicketPriority? priority,
    String? department,
    Object? category = _keep,
    TicketDescription? description,
    String? assignedAgent,
    DateTime? updatedAt,
    Object? resolution = _keep,
    List<TicketActivity>? activities,
    int? revision,
    bool? deleted,
  }) =>
      TicketRecord(
        id: id,
        subject: subject ?? this.subject,
        customerLabel: customerLabel ?? this.customerLabel,
        sourceActor: sourceActor,
        customerId: customerId ?? this.customerId,
        source: source,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        department: department ?? this.department,
        category:
            identical(category, _keep) ? this.category : category as String?,
        sla: sla,
        contactIdentifier: contactIdentifier ?? this.contactIdentifier,
        description: description ?? this.description,
        assignedAgent: assignedAgent ?? this.assignedAgent,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        resolution: identical(resolution, _keep)
            ? this.resolution
            : resolution as TicketResolution?,
        sourceContext: sourceContext,
        activities: activities ?? this.activities,
        revision: revision ?? this.revision,
        deleted: deleted ?? this.deleted,
        capabilities: capabilities,
      );
  static const _keep = Object();
}

class TicketUpdateRequest {
  const TicketUpdateRequest(
      {required this.ticketId,
      required this.expectedRevision,
      required this.customerId,
      required this.customerLabel,
      required this.contactIdentifier,
      required this.assignedAgent,
      required this.subject,
      required this.description,
      required this.department,
      required this.category,
      required this.priority,
      required this.status,
      this.resolution});
  final String ticketId;
  final int expectedRevision;
  final String? customerId;
  final String customerLabel;
  final String? contactIdentifier;
  final String assignedAgent;
  final String subject;
  final TicketDescription description;
  final String department;
  final String category;
  final TicketPriority priority;
  final TicketStatus status;
  final TicketResolution? resolution;
}

class TicketCreateRequest {
  const TicketCreateRequest(
      {required this.customerId,
      required this.customerLabel,
      required this.contactIdentifier,
      required this.assignedAgent,
      required this.subject,
      required this.description,
      required this.department,
      required this.category,
      required this.priority,
      required this.status,
      this.resolution});
  final String? customerId;
  final String customerLabel;
  final String? contactIdentifier;
  final String assignedAgent;
  final String subject;
  final TicketDescription description;
  final String department;
  final String category;
  final TicketPriority priority;
  final TicketStatus status;
  final TicketResolution? resolution;
}

class TicketActivityPage {
  const TicketActivityPage({required this.items, this.nextCursor});
  final List<TicketActivity> items;
  final String? nextCursor;
}

abstract class TicketRepository {
  Future<List<TicketRecord>> loadTickets();
  Future<TicketRecord?> loadTicket(String id);
  Future<TicketRecord> create(TicketCreateRequest request);
  Future<TicketRecord> update(TicketUpdateRequest request);
  Future<TicketRecord> resolve(String id, String note);
  Future<TicketRecord> reopen(String id);
  Future<TicketRecord> reassign(String id, String agent);
  Future<void> delete(String id, {required int expectedRevision});
  Future<TicketActivityPage> loadActivity(String id, {String? cursor});
}

class LocalTicketRepository implements TicketRepository {
  LocalTicketRepository() : _tickets = List.of(ticketFixtures);
  final List<TicketRecord> _tickets;
  @override
  Future<List<TicketRecord>> loadTickets() async => List.unmodifiable(_tickets);
  @override
  Future<TicketRecord?> loadTicket(String id) async =>
      _tickets.firstWhereOrNull((item) => item.id == id && !item.deleted);
  @override
  Future<TicketRecord> create(TicketCreateRequest request) async {
    final now = DateTime.now();
    final ticket = TicketRecord(
        id: 'DGKSL-${400 + _tickets.length + 1}',
        subject: request.subject,
        customerLabel: request.customerLabel,
        sourceActor: request.customerLabel,
        customerId: request.customerId,
        source: TicketSource.manual,
        status: request.status,
        priority: request.priority,
        department: request.department,
        category: request.category,
        contactIdentifier: request.contactIdentifier,
        description: request.description,
        assignedAgent: request.assignedAgent,
        createdAt: now,
        updatedAt: now,
        resolution: request.resolution,
        sourceContext: const TicketManualSourceContext(),
        activities: [
          TicketActivity(
              id: 'created-$now',
              type: TicketActivityType.created,
              title: 'Ticket created',
              timestamp: now,
              actor: 'Hillary')
        ]);
    _tickets.insert(0, ticket);
    return ticket;
  }

  @override
  Future<TicketRecord> update(TicketUpdateRequest request) async {
    final index = _indexOf(request.ticketId);
    final current = _tickets[index];
    _validateRevision(current, request.expectedRevision);
    final now = DateTime.now();
    final activities = [...current.activities];
    if (current.status != request.status) {
      activities.insert(
          0,
          TicketActivity(
              id: 'status-$now',
              type: request.status == TicketStatus.resolved
                  ? TicketActivityType.resolved
                  : TicketActivityType.statusChanged,
              title: 'Status changed',
              description: '${current.status.label} → ${request.status.label}',
              timestamp: now,
              actor: 'Hillary'));
    }
    final updated = current.copyWith(
        subject: request.subject,
        customerId: request.customerId,
        customerLabel: request.customerLabel,
        contactIdentifier: request.contactIdentifier,
        assignedAgent: request.assignedAgent,
        description: request.description,
        department: request.department,
        category: request.category,
        priority: request.priority,
        status: request.status,
        resolution: request.resolution,
        activities: activities,
        updatedAt: now,
        revision: current.revision + 1);
    _tickets[index] = updated;
    return updated;
  }

  @override
  Future<TicketRecord> resolve(String id, String note) async {
    final ticket = _tickets[_indexOf(id)];
    final now = DateTime.now();
    final resolution = TicketResolution(
        note: note, resolvedBy: 'Hillary', resolvedAt: now, template: 'Solved');
    final updated = ticket.copyWith(
        status: TicketStatus.resolved,
        resolution: resolution,
        updatedAt: now,
        revision: ticket.revision + 1,
        activities: [
          TicketActivity(
              id: 'resolved-$now',
              type: TicketActivityType.resolved,
              title: 'Ticket resolved',
              description: note,
              timestamp: now,
              actor: 'Hillary'),
          ...ticket.activities
        ]);
    _tickets[_indexOf(id)] = updated;
    return updated;
  }

  @override
  Future<TicketRecord> reopen(String id) async {
    final ticket = _tickets[_indexOf(id)];
    final now = DateTime.now();
    final updated = ticket.copyWith(
        status: TicketStatus.open,
        resolution: null,
        updatedAt: now,
        revision: ticket.revision + 1,
        activities: [
          TicketActivity(
              id: 'reopened-$now',
              type: TicketActivityType.reopened,
              title: 'Ticket reopened',
              timestamp: now,
              actor: 'Hillary'),
          ...ticket.activities
        ]);
    _tickets[_indexOf(id)] = updated;
    return updated;
  }

  @override
  Future<TicketRecord> reassign(String id, String agent) async {
    final ticket = _tickets[_indexOf(id)];
    final now = DateTime.now();
    final updated = ticket.copyWith(
        assignedAgent: agent,
        updatedAt: now,
        revision: ticket.revision + 1,
        activities: [
          TicketActivity(
              id: 'assigned-$now',
              type: TicketActivityType.reassigned,
              title: 'Reassigned to $agent',
              timestamp: now,
              actor: 'Hillary'),
          ...ticket.activities
        ]);
    _tickets[_indexOf(id)] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id, {required int expectedRevision}) async {
    final index = _indexOf(id);
    final ticket = _tickets[index];
    _validateRevision(ticket, expectedRevision);
    _tickets[index] = ticket.copyWith(
        deleted: true,
        revision: ticket.revision + 1,
        updatedAt: DateTime.now());
  }

  @override
  Future<TicketActivityPage> loadActivity(String id, {String? cursor}) async {
    final ticket = _tickets[_indexOf(id)];
    final offset = int.tryParse(cursor ?? '0') ?? 0;
    const size = 4;
    final items = ticket.activities.skip(offset).take(size).toList();
    return TicketActivityPage(
        items: items,
        nextCursor: offset + items.length < ticket.activities.length
            ? '${offset + items.length}'
            : null);
  }

  int _indexOf(String id) {
    final index = _tickets.indexWhere((item) => item.id == id && !item.deleted);
    if (index < 0) throw StateError('Ticket not found');
    return index;
  }

  void _validateRevision(TicketRecord ticket, int revision) {
    if (ticket.revision != revision) {
      throw StateError('This ticket has changed. Refresh and try again.');
    }
  }
}

class TicketStoreState {
  const TicketStoreState(
      {this.tickets = const [], this.loading = true, this.failure});
  final List<TicketRecord> tickets;
  final bool loading;
  final Object? failure;
  TicketRecord? findById(String id) =>
      tickets.firstWhereOrNull((item) => item.id == id && !item.deleted);
  TicketStoreState copyWith(
          {List<TicketRecord>? tickets, bool? loading, Object? failure}) =>
      TicketStoreState(
          tickets: tickets ?? this.tickets,
          loading: loading ?? this.loading,
          failure: failure);
}

final ticketRepositoryProvider =
    Provider<TicketRepository>((_) => LocalTicketRepository());
final ticketStoreProvider =
    NotifierProvider<TicketStore, TicketStoreState>(TicketStore.new);

class TicketStore extends Notifier<TicketStoreState> {
  @override
  TicketStoreState build() =>
      TicketStoreState(tickets: List.of(ticketFixtures), loading: false);
  TicketRecord? findById(String id) => state.findById(id);
  Future<void> refresh() async {
    state = state.copyWith(loading: true, failure: null);
    try {
      state = TicketStoreState(
          tickets: await ref.read(ticketRepositoryProvider).loadTickets(),
          loading: false);
    } catch (error) {
      state = state.copyWith(loading: false, failure: error);
    }
  }

  Future<TicketRecord> create(TicketCreateRequest request) async =>
      _commit(await ref.read(ticketRepositoryProvider).create(request));
  Future<TicketRecord> update(TicketUpdateRequest request) async =>
      _commit(await ref.read(ticketRepositoryProvider).update(request));
  Future<TicketRecord> resolve(String id, String note) async =>
      _commit(await ref.read(ticketRepositoryProvider).resolve(id, note));
  Future<TicketRecord> reopen(String id) async =>
      _commit(await ref.read(ticketRepositoryProvider).reopen(id));
  Future<TicketRecord> reassign(String id, String agent) async =>
      _commit(await ref.read(ticketRepositoryProvider).reassign(id, agent));
  Future<void> delete(String id, int revision) async {
    await ref
        .read(ticketRepositoryProvider)
        .delete(id, expectedRevision: revision);
    state = TicketStoreState(tickets: [
      for (final item in state.tickets)
        if (item.id != id) item
    ], loading: false);
  }

  Future<TicketActivityPage> loadActivity(String id, {String? cursor}) =>
      ref.read(ticketRepositoryProvider).loadActivity(id, cursor: cursor);
  TicketRecord _commit(TicketRecord updated) {
    final found = state.tickets.any((item) => item.id == updated.id);
    state = TicketStoreState(
        tickets: found
            ? [
                for (final item in state.tickets)
                  if (item.id == updated.id) updated else item
              ]
            : [updated, ...state.tickets],
        loading: false);
    return updated;
  }
}

final ticketProvider = Provider.family<TicketRecord?, String>(
    (ref, id) => ref.watch(ticketStoreProvider).findById(id));

const ticketDepartments = <String>['General', 'Finance', 'Technical support'];
const ticketCategoriesByDepartment = <String, List<String>>{
  'General': ['General inquiry', 'Technical support'],
  'Finance': ['Accounting', 'Billing and payments'],
  'Technical support': ['Technical support', 'Configuration']
};

class TicketAgent {
  const TicketAgent(
      {required this.id, required this.name, required this.availability});
  final String id;
  final String name;
  final String availability;
}

const ticketAgents = <TicketAgent>[
  TicketAgent(id: 'hillary', name: 'Hillary', availability: 'Available'),
  TicketAgent(id: 'elsie', name: 'Elsie', availability: 'Away'),
  TicketAgent(id: 'john', name: 'John Slater', availability: 'Offline')
];

final _baseActivities = <TicketActivity>[
  TicketActivity(
      id: 'activity-created',
      type: TicketActivityType.created,
      title: 'Ticket created',
      description: 'Auto-created from the incoming channel.',
      timestamp: DateTime(2026, 8, 27, 14, 37),
      actor: 'System'),
  TicketActivity(
      id: 'activity-assigned',
      type: TicketActivityType.assigned,
      title: 'Assigned to Hillary',
      description: 'Routed from the available agent pool.',
      timestamp: DateTime(2026, 8, 27, 14, 38),
      actor: 'System'),
  TicketActivity(
      id: 'activity-call',
      type: TicketActivityType.callCompleted,
      title: 'Call completed',
      description: 'Outbound call completed. Duration: 00:14.',
      timestamp: DateTime(2026, 8, 27, 15, 13),
      actor: 'Hillary'),
  TicketActivity(
      id: 'activity-note',
      type: TicketActivityType.noteAdded,
      title: 'Follow-up noted',
      description: 'Customer requested an update.',
      timestamp: DateTime(2026, 8, 28, 9),
      actor: 'Hillary'),
  TicketActivity(
      id: 'activity-update',
      type: TicketActivityType.statusChanged,
      title: 'Ticket updated',
      description: 'Classification was reviewed.',
      timestamp: DateTime(2026, 8, 28, 10),
      actor: 'Hillary'),
];

final ticketFixtures = <TicketRecord>[
  TicketRecord(
      id: 'DGKSL-392',
      subject: 'Widget AI: How do I create a payroll',
      customerLabel: 'Phyllis',
      sourceActor: 'Phyllis',
      source: TicketSource.widget,
      status: TicketStatus.open,
      priority: TicketPriority.low,
      department: 'General',
      category: 'Accounting',
      sla: 'SLA 2h 10m',
      contactIdentifier: 'phyllis@example.com',
      description: const TicketDescription(
          plainText:
              'Customer asks how to create a payroll from the Widget Chat.'),
      assignedAgent: 'Hillary',
      createdAt: DateTime(2026, 8, 29, 9),
      updatedAt: DateTime(2026, 8, 29, 9, 16),
      sourceContext: const TicketConversationSourceContext(
          conversationId: 'aloise-whatsapp',
          preview: 'Can I talk to an agent?',
          channel: TicketSource.widget),
      activities: _baseActivities),
  TicketRecord(
      id: 'DGKSL-388',
      subject: 'Billing-and-payments call from +254722161652',
      customerLabel: 'Sharon Dreams Mosop',
      sourceActor: 'Caller 7650',
      source: TicketSource.call,
      status: TicketStatus.inProgress,
      priority: TicketPriority.medium,
      department: 'Finance',
      category: 'Billing and payments',
      sla: 'SLA 17h',
      contactIdentifier: '+254722161652',
      description: const TicketDescription(
          plainText:
              'Auto-created from incoming call.\n\nCategory: Billing-and-payments\nCaller: +254722161652\nCustomer: Caller 7650'),
      assignedAgent: 'Hillary',
      createdAt: DateTime(2026, 8, 27, 14, 37),
      updatedAt: DateTime(2026, 8, 28, 9),
      sourceContext: TicketPhoneSourceContext(calls: [
        TicketCall(
            id: 'call-388-1',
            direction: 'Outbound',
            occurredAt: DateTime(2026, 8, 27, 15, 13),
            duration: const Duration(seconds: 14),
            connected: true,
            recordingAsset: 'assets/demo/chat/voice_note.m4a'),
        TicketCall(
            id: 'call-388-2',
            direction: 'Missed call',
            occurredAt: DateTime(2026, 8, 27, 14, 37))
      ]),
      activities: _baseActivities),
  TicketRecord(
      id: 'DGKSL-378',
      subject: 'Technical-support call from +254720261967',
      customerLabel: 'Deborah Hekima',
      sourceActor: 'Caller 1967',
      source: TicketSource.call,
      status: TicketStatus.overdue,
      priority: TicketPriority.medium,
      department: 'Technical support',
      category: 'Technical support',
      sla: 'Overdue by 35m',
      contactIdentifier: '+254720261967',
      description: const TicketDescription(
          plainText:
              'A customer reported a technical support issue on a phone call.'),
      assignedAgent: 'Hillary',
      createdAt: DateTime(2026, 8, 28, 8),
      updatedAt: DateTime(2026, 8, 29, 10),
      sourceContext: TicketPhoneSourceContext(calls: [
        TicketCall(
            id: 'call-378-1',
            direction: 'Missed call',
            occurredAt: DateTime(2026, 8, 28, 8))
      ]),
      activities: _baseActivities),
  TicketRecord(
      id: 'DGKSL-376',
      subject: 'Good morning Hillary',
      customerLabel: 'Raphael Sunshine',
      sourceActor: 'Raphael Sunshine',
      source: TicketSource.whatsapp,
      status: TicketStatus.open,
      priority: TicketPriority.low,
      department: 'General',
      category: 'General inquiry',
      contactIdentifier: '+254719106280',
      description: const TicketDescription(
          plainText: 'Customer asked for help through WhatsApp.'),
      assignedAgent: 'Hillary',
      createdAt: DateTime(2026, 8, 25, 9, 20),
      updatedAt: DateTime(2026, 8, 26, 9, 30),
      sourceContext: const TicketConversationSourceContext(
          conversationId: 'aloise-whatsapp',
          preview: 'That worked. Thank you.',
          channel: TicketSource.whatsapp),
      activities: _baseActivities),
  TicketRecord(
      id: 'DGKSL-373',
      subject: 'Fee balances are not showing',
      customerLabel: 'Nana Betterstream',
      sourceActor: 'Nana Betterstream',
      customerId: 'nana',
      source: TicketSource.whatsapp,
      status: TicketStatus.escalated,
      priority: TicketPriority.high,
      department: 'Finance',
      category: 'Accounting',
      sla: 'SLA 1h 20m',
      contactIdentifier: '+254719106280',
      description: const TicketDescription(
          plainText: 'Fee balances are not appearing for the customer.'),
      assignedAgent: 'Hillary',
      createdAt: DateTime(2026, 8, 28, 11),
      updatedAt: DateTime(2026, 8, 29, 13),
      sourceContext: const TicketConversationSourceContext(
          conversationId: 'aloise-whatsapp',
          preview: 'The balances are still missing.',
          channel: TicketSource.whatsapp),
      activities: _baseActivities),
  TicketRecord(
      id: 'DGKSL-360',
      subject: 'Requisition approval required',
      customerLabel: 'MOI HIGH SCHOOL-KABARAK',
      sourceActor: 'MOI HIGH SCHOOL-KABARAK',
      source: TicketSource.email,
      status: TicketStatus.resolved,
      priority: TicketPriority.high,
      department: 'Finance',
      category: 'Billing and payments',
      contactIdentifier: 'approvals@moi-kabarak.ac.ke',
      description: const TicketDescription(
          plainText:
              'Requisition(s) 12 are waiting for your approval. Please log in to review.'),
      assignedAgent: 'Hillary',
      createdAt: DateTime(2026, 8, 17, 12, 16),
      updatedAt: DateTime(2026, 8, 18, 10),
      resolution: TicketResolution(
          note: 'Responded to the email and confirmed the approval path.',
          resolvedBy: 'Hillary',
          resolvedAt: DateTime(2026, 8, 18, 10),
          template: 'Customer educated'),
      sourceContext: const TicketEmailSourceContext(
          threadId: 'requisition-12',
          preview: 'Requisition(s) 12 are waiting for your approval.',
          from: 'approvals@moi-kabarak.ac.ke'),
      activities: _baseActivities),
  TicketRecord(
      id: 'DGKSL-356',
      subject: 'Teacher accounts for Sunshine Primary',
      customerLabel: 'Tony Kirui Sunshine',
      sourceActor: 'Tony Kirui Sunshine',
      source: TicketSource.email,
      status: TicketStatus.resolved,
      priority: TicketPriority.medium,
      department: 'General',
      category: 'General inquiry',
      contactIdentifier: 'kirui-mac@gmail.com',
      description: const TicketDescription(
          plainText: 'Teacher account information was requested by email.'),
      assignedAgent: 'Hillary',
      createdAt: DateTime(2026, 8, 16, 10),
      updatedAt: DateTime(2026, 8, 17, 9),
      resolution: TicketResolution(
          note: 'Information was sent to the customer.',
          resolvedBy: 'Hillary',
          resolvedAt: DateTime(2026, 8, 17, 9),
          template: 'Solved'),
      sourceContext: const TicketEmailSourceContext(
          threadId: 'teacher-accounts',
          preview: 'Attached is the data for the Sunshine Primary teachers.',
          from: 'kirui-mac@gmail.com'),
      activities: _baseActivities),
];
