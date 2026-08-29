import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'customer_editor_page_model.g.dart';

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    this.company = '',
    this.notes = '',
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String company;
  final String notes;
}

@Riverpod(keepAlive: true)
class CustomersStore extends _$CustomersStore {
  @override
  List<CustomerRecord> build() => _initialCustomers;

  CustomerRecord? findById(String id) =>
      state.where((customer) => customer.id == id).firstOrNull;

  void create(CustomerRecord customer) => state = [...state, customer];

  void update(CustomerRecord customer) => state = [
        for (final item in state) item.id == customer.id ? customer : item,
      ];
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

  CustomerRecord? submit() {
    if (!validate() || state.submitting) return null;
    state = state.copyWith(submitting: true, failure: null);
    final record = CustomerRecord(
      id: state.customerId ??
          'customer-${DateTime.now().microsecondsSinceEpoch}',
      name: state.name.trim(),
      email: state.email.trim(),
      phone: state.phone.trim(),
      company: state.company.trim(),
      notes: state.notes.trim(),
    );
    final store = ref.read(customersStoreProvider.notifier);
    if (state.mode == CustomerEditorMode.create) {
      store.create(record);
    } else {
      store.update(record);
    }
    state = state.copyWith(submitting: false);
    return record;
  }
}

const _initialCustomers = <CustomerRecord>[
  CustomerRecord(
    id: 'aloise-obaga',
    name: 'Aloise Obaga Kaizen School',
    email: 'aloise.obaga@example.com',
    phone: '+254723506031',
    company: 'Kaizen School',
    notes:
        'Primary school contact for technical support and billing follow-up.',
  ),
  CustomerRecord(
      id: 'caller-1967', name: 'Caller 1967', phone: '+254720261967'),
  CustomerRecord(id: 'cool-customer', name: '😎', phone: '+254721161652'),
  CustomerRecord(id: 'contact-2945', name: '', phone: '+29454885757108'),
  CustomerRecord(id: 'nana', name: 'Nana', phone: '+254719106280'),
  CustomerRecord(id: 'contact-4390', name: '', phone: '+43907731261010'),
  CustomerRecord(id: 'otieno', name: 'otieno', email: 'sullyvan83@gmail.com'),
];
