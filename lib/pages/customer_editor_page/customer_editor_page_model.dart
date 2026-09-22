import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/api_service.dart';
import '../customers_page/customer_repository.dart';
import '../customers_page/customers_page_model.dart';
import '../../services/auth_session_controller.dart';

part 'customer_editor_page_model.g.dart';

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    this.company = '',
    this.notes = '',
    this.ticketsCount,
    this.createdAt,
    this.tags = const [],
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String company;
  final String notes;
  final int? ticketsCount;
  final DateTime? createdAt;
  final List<String> tags;

  CustomerRecord copyWith({
    String? name,
    String? email,
    String? phone,
    String? company,
    String? notes,
    int? ticketsCount,
    DateTime? createdAt,
    List<String>? tags,
  }) =>
      CustomerRecord(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        company: company ?? this.company,
        notes: notes ?? this.notes,
        ticketsCount: ticketsCount ?? this.ticketsCount,
        createdAt: createdAt ?? this.createdAt,
        tags: tags ?? this.tags,
      );
}

@Riverpod(keepAlive: true)
class CustomersStore extends _$CustomersStore {
  @override
  List<CustomerRecord> build() {
    ref.watch(authSessionControllerProvider);
    return const [];
  }

  CustomerRecord? findById(String id) =>
      state.where((customer) => customer.id == id).firstOrNull;

  void create(CustomerRecord customer) => state = [...state, customer];

  void update(CustomerRecord customer) => state = [
        for (final item in state) item.id == customer.id ? customer : item,
      ];

  void upsertAll(Iterable<CustomerRecord> customers) {
    final byId = {for (final item in state) item.id: item};
    for (final customer in customers) {
      byId[customer.id] = customer;
    }
    state = byId.values.toList(growable: false);
  }

  void upsert(CustomerRecord customer) => upsertAll([customer]);
}

enum CustomerEditorMode { create, edit }

class CustomerEditorState {
  const CustomerEditorState({
    required this.mode,
    this.customerId,
    this.initialCustomer,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.company = '',
    this.notes = '',
    this.loading = false,
    this.submitting = false,
    this.failure,
    this.fieldErrors = const {},
  });

  final CustomerEditorMode mode;
  final String? customerId;
  final CustomerRecord? initialCustomer;
  final String name;
  final String email;
  final String phone;
  final String company;
  final String notes;
  final bool loading;
  final bool submitting;
  final String? failure;
  final Map<String, String> fieldErrors;

  bool get hasUnsavedChanges => mode == CustomerEditorMode.create
      ? name.trim().isNotEmpty ||
          email.trim().isNotEmpty ||
          phone.trim().isNotEmpty ||
          company.trim().isNotEmpty ||
          notes.trim().isNotEmpty
      : initialCustomer != null &&
          (name != initialCustomer!.name ||
              email != initialCustomer!.email ||
              phone != initialCustomer!.phone ||
              company != initialCustomer!.company ||
              notes != initialCustomer!.notes);

  CustomerEditorState copyWith({
    Object? name = _keep,
    Object? email = _keep,
    Object? phone = _keep,
    Object? company = _keep,
    Object? notes = _keep,
    bool? loading,
    bool? submitting,
    Object? failure = _keep,
    Object? fieldErrors = _keep,
  }) =>
      CustomerEditorState(
        mode: mode,
        customerId: customerId,
        initialCustomer: initialCustomer,
        name: identical(name, _keep) ? this.name : name as String,
        email: identical(email, _keep) ? this.email : email as String,
        phone: identical(phone, _keep) ? this.phone : phone as String,
        company: identical(company, _keep) ? this.company : company as String,
        notes: identical(notes, _keep) ? this.notes : notes as String,
        loading: loading ?? this.loading,
        submitting: submitting ?? this.submitting,
        failure: identical(failure, _keep) ? this.failure : failure as String?,
        fieldErrors: identical(fieldErrors, _keep)
            ? this.fieldErrors
            : Map<String, String>.from(fieldErrors as Map),
      );

  static const _keep = Object();
}

@riverpod
class CustomerEditorNotifier extends _$CustomerEditorNotifier {
  @override
  CustomerEditorState build({String? customerId}) {
    final existing = customerId == null
        ? null
        : ref.read(customersStoreProvider.notifier).findById(customerId);
    return CustomerEditorState(
      mode: customerId == null
          ? CustomerEditorMode.create
          : CustomerEditorMode.edit,
      customerId: customerId,
      initialCustomer: existing,
      name: existing?.name ?? '',
      email: existing?.email ?? '',
      phone: existing?.phone ?? '',
      company: existing?.company ?? '',
      notes: existing?.notes ?? '',
    );
  }

  void setName(String value) =>
      state = state.copyWith(name: value, fieldErrors: {});
  void setEmail(String value) =>
      state = state.copyWith(email: value, fieldErrors: {});
  void setPhone(String value) =>
      state = state.copyWith(phone: value, fieldErrors: {});
  void setCompany(String value) => state = state.copyWith(company: value);
  void setNotes(String value) => state = state.copyWith(notes: value);

  bool validate() {
    final errors = <String, String>{};
    if (state.name.trim().isEmpty) errors['name'] = 'Enter a name.';
    if (state.email.trim().isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(state.email.trim())) {
      errors['email'] = 'Enter a valid email address.';
    }
    final phoneDigits = state.phone.replaceAll(RegExp(r'\D'), '');
    if (state.phone.trim().isNotEmpty && phoneDigits.length < 7) {
      errors['phone'] = 'Enter a valid phone number.';
    }
    state = state.copyWith(fieldErrors: errors);
    return errors.isEmpty;
  }

  Future<CustomerRecord?> submit() async {
    if (!validate() || state.submitting) return null;
    state = state.copyWith(submitting: true, failure: null);
    try {
      final initial = state.initialCustomer;
      final fields = <String, Object?>{};
      if (state.mode == CustomerEditorMode.create) {
        fields.addAll({
          'name': state.name.trim(),
          'email': _optional(state.email),
          'phone_number': _optional(state.phone),
          'company': _optional(state.company),
          'notes': _optional(state.notes),
        });
      } else {
        if (state.name.trim() != initial?.name) {
          fields['name'] = state.name.trim();
        }
        if (state.email.trim() != initial?.email) {
          fields['email'] = _optional(state.email);
        }
        if (state.phone.trim() != initial?.phone) {
          fields['phone_number'] = _optional(state.phone);
        }
        if (state.company.trim() != initial?.company) {
          fields['company'] = _optional(state.company);
        }
        if (state.notes.trim() != initial?.notes) {
          fields['notes'] = _optional(state.notes);
        }
      }

      final store = ref.read(customersStoreProvider.notifier);
      late final CustomerRecord record;
      if (state.mode == CustomerEditorMode.create) {
        // Customer creation remains on its existing local-first flow; this
        // endpoint is the documented partial update endpoint only.
        record = CustomerRecord(
          id: 'customer-${DateTime.now().microsecondsSinceEpoch}',
          name: state.name.trim(),
          email: state.email.trim(),
          phone: state.phone.trim(),
          company: state.company.trim(),
          notes: state.notes.trim(),
        );
        store.create(record);
      } else if (fields.isEmpty) {
        record = initial!;
      } else {
        record = await ref.read(customerRepositoryProvider).update(
              state.customerId!,
              fields: fields,
              fallback: initial!,
            );
        store.upsert(record);
        ref.read(customersPageProvider.notifier).applyConfirmedUpdate(record);
      }
      state = state.copyWith(submitting: false);
      return record;
    } catch (error) {
      state = state.copyWith(
        submitting: false,
        failure: _friendlyError(error),
      );
      return null;
    }
  }

  String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

  String _friendlyError(Object error) {
    if (error is ApiClientException && error.statusCode == 422) {
      return error.message;
    }
    if (error is ApiClientException && error.statusCode == 404) {
      return 'This customer could not be found in the active workspace.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}
