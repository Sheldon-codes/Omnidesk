import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../tickets_page/ticket_store.dart';

part 'ticket_editor_page_model.g.dart';

enum TicketEditorMode { create, edit }

class TicketEditorState {
  const TicketEditorState({
    required this.mode,
    this.initial,
    this.customerId,
    this.customerLabel = '',
    this.contactIdentifier,
    this.assignedAgent = 'Hillary',
    this.subject = '',
    this.description = '',
    this.department = 'General',
    this.category = 'General inquiry',
    this.priority = TicketPriority.medium,
    this.status = TicketStatus.open,
    this.resolutionNote = '',
    this.resolutionTemplate,
    this.submitting = false,
    this.errors = const {},
  });
  final TicketEditorMode mode;
  final TicketRecord? initial;
  final String? customerId;
  final String customerLabel;
  final String? contactIdentifier;
  final String assignedAgent;
  final String subject;
  final String description;
  final String department;
  final String category;
  final TicketPriority priority;
  final TicketStatus status;
  final String resolutionNote;
  final String? resolutionTemplate;
  final bool submitting;
  final Map<String, String> errors;
  bool get hasUnsavedChanges => mode == TicketEditorMode.create
      ? customerLabel.isNotEmpty || subject.isNotEmpty || description.isNotEmpty
      : initial != null &&
          (customerId != initial!.customerId ||
              customerLabel != initial!.customerLabel ||
              assignedAgent != initial!.assignedAgent ||
              subject != initial!.subject ||
              description != initial!.description.plainText ||
              department != initial!.department ||
              category != initial!.category ||
              priority != initial!.priority ||
              status != initial!.status ||
              resolutionNote != (initial!.resolution?.note ?? ''));
  TicketEditorState copyWith(
          {Object? customerId = _keep,
          String? customerLabel,
          Object? contactIdentifier = _keep,
          String? assignedAgent,
          String? subject,
          String? description,
          String? department,
          String? category,
          TicketPriority? priority,
          TicketStatus? status,
          String? resolutionNote,
          Object? resolutionTemplate = _keep,
          bool? submitting,
          Map<String, String>? errors}) =>
      TicketEditorState(
          mode: mode,
          initial: initial,
          customerId: identical(customerId, _keep)
              ? this.customerId
              : customerId as String?,
          customerLabel: customerLabel ?? this.customerLabel,
          contactIdentifier: identical(contactIdentifier, _keep)
              ? this.contactIdentifier
              : contactIdentifier as String?,
          assignedAgent: assignedAgent ?? this.assignedAgent,
          subject: subject ?? this.subject,
          description: description ?? this.description,
          department: department ?? this.department,
          category: category ?? this.category,
          priority: priority ?? this.priority,
          status: status ?? this.status,
          resolutionNote: resolutionNote ?? this.resolutionNote,
          resolutionTemplate: identical(resolutionTemplate, _keep)
              ? this.resolutionTemplate
              : resolutionTemplate as String?,
          submitting: submitting ?? this.submitting,
          errors: errors ?? this.errors);
  static const _keep = Object();
}

@riverpod
class TicketEditorNotifier extends _$TicketEditorNotifier {
  @override
  TicketEditorState build({String? ticketId}) {
    final current = ticketId == null
        ? null
        : ref.read(ticketStoreProvider).findById(ticketId);
    return TicketEditorState(
        mode:
            ticketId == null ? TicketEditorMode.create : TicketEditorMode.edit,
        initial: current,
        customerId: current?.customerId,
        customerLabel: current?.customerLabel ?? '',
        contactIdentifier: current?.contactIdentifier,
        assignedAgent: current?.assignedAgent ?? 'Hillary',
        subject: current?.subject ?? '',
        description: current?.description.plainText ?? '',
        department: current?.department ?? 'General',
        category: current?.category ?? 'General inquiry',
        priority: current?.priority ?? TicketPriority.medium,
        status: switch (current?.status) {
          TicketStatus.resolved => TicketStatus.resolved,
          TicketStatus.inProgress => TicketStatus.inProgress,
          _ => TicketStatus.open
        },
        resolutionNote: current?.resolution?.note ?? '',
        resolutionTemplate: current?.resolution?.template);
  }

  void setCustomer(
          {required String? id, required String name, String? identifier}) =>
      state = state.copyWith(
          customerId: id,
          customerLabel: name,
          contactIdentifier: identifier,
          errors: {});
  void setAgent(String value) =>
      state = state.copyWith(assignedAgent: value, errors: {});
  void setSubject(String value) =>
      state = state.copyWith(subject: value, errors: {});
  void setDescription(String value) =>
      state = state.copyWith(description: value);
  void setDepartment(String value) {
    final categories = ticketCategoriesByDepartment[value]!;
    state = state.copyWith(
        department: value,
        category: categories.contains(state.category)
            ? state.category
            : categories.first,
        errors: {});
  }

  void setCategory(String value) =>
      state = state.copyWith(category: value, errors: {});
  void setPriority(TicketPriority value) =>
      state = state.copyWith(priority: value, errors: {});
  void setStatus(TicketStatus value) =>
      state = state.copyWith(status: value, errors: {});
  void setResolution(String value) =>
      state = state.copyWith(resolutionNote: value, errors: {});
  void selectTemplate(String value) => state = state.copyWith(
      resolutionTemplate: value,
      resolutionNote:
          state.resolutionNote.isEmpty ? value : state.resolutionNote);
  bool validate() {
    final errors = <String, String>{};
    if (state.customerLabel.trim().isEmpty) {
      errors['customer'] = 'Select a customer.';
    }
    if (state.subject.trim().isEmpty) errors['subject'] = 'Enter a subject.';
    if (state.category.trim().isEmpty) {
      errors['category'] = 'Select a category.';
    }
    if (state.status == TicketStatus.resolved &&
        state.resolutionNote.trim().isEmpty) {
      errors['resolution'] = 'Describe how this was resolved.';
    }
    state = state.copyWith(errors: errors);
    return errors.isEmpty;
  }

  Future<TicketRecord?> submit() async {
    if (!validate() || state.submitting) return null;
    state = state.copyWith(submitting: true);
    try {
      final resolution = state.status == TicketStatus.resolved
          ? TicketResolution(
              note: state.resolutionNote.trim(),
              template: state.resolutionTemplate,
              resolvedBy: 'Hillary',
              resolvedAt: DateTime.now())
          : null;
      final store = ref.read(ticketStoreProvider.notifier);
      final result = state.mode == TicketEditorMode.create
          ? await store.create(TicketCreateRequest(
              customerId: state.customerId,
              customerLabel: state.customerLabel.trim(),
              contactIdentifier: state.contactIdentifier,
              assignedAgent: state.assignedAgent,
              subject: state.subject.trim(),
              description:
                  TicketDescription(plainText: state.description.trim()),
              department: state.department,
              category: state.category,
              priority: state.priority,
              status: state.status,
              resolution: resolution))
          : await store.update(TicketUpdateRequest(
              ticketId: state.initial!.id,
              expectedRevision: state.initial!.revision,
              customerId: state.customerId,
              customerLabel: state.customerLabel.trim(),
              contactIdentifier: state.contactIdentifier,
              assignedAgent: state.assignedAgent,
              subject: state.subject.trim(),
              description:
                  TicketDescription(plainText: state.description.trim()),
              department: state.department,
              category: state.category,
              priority: state.priority,
              status: state.status,
              resolution: resolution));
      state = state.copyWith(submitting: false);
      return result;
    } catch (_) {
      state = state.copyWith(
          submitting: false,
          errors: {'form': 'Unable to save ticket. Try again.'});
      return null;
    }
  }
}
