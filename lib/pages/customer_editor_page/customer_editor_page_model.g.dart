// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_editor_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// ignore_for_file: type=lint, type=warning

@ProviderFor(CustomersStore)
final customersStoreProvider = CustomersStoreProvider._();

final class CustomersStoreProvider
    extends $NotifierProvider<CustomersStore, List<CustomerRecord>> {
  CustomersStoreProvider._()
      : super(
            from: null,
            argument: null,
            retry: null,
            name: r'customersStoreProvider',
            isAutoDispose: false,
            dependencies: null,
            $allTransitiveDependencies: null);
  @override
  String debugGetCreateSourceHash() => _$customersStoreHash();
  @$internal
  @override
  CustomersStore create() => CustomersStore();
  @override
  Override overrideWithValue(List<CustomerRecord> value) => $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CustomerRecord>>(value));
}

String _$customersStoreHash() => r'3e1e9c4d4f5c9c2c7b6b1d6e1e0a3b2c4d5e6f70';

abstract class _$CustomersStore extends $Notifier<List<CustomerRecord>> {
  List<CustomerRecord> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<CustomerRecord>, List<CustomerRecord>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<List<CustomerRecord>, List<CustomerRecord>>,
        List<CustomerRecord>,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(CustomerEditorNotifier)
final customerEditorNotifierProvider = CustomerEditorNotifierFamily._();

final class CustomerEditorNotifierProvider
    extends $NotifierProvider<CustomerEditorNotifier, CustomerEditorState> {
  CustomerEditorNotifierProvider._(
      {required CustomerEditorNotifierFamily super.from,
      required String? super.argument})
      : super(
            retry: null,
            name: r'customerEditorNotifierProvider',
            isAutoDispose: true,
            dependencies: null,
            $allTransitiveDependencies: null);
  @override
  String debugGetCreateSourceHash() => _$customerEditorNotifierHash();
  @override
  String toString() => r'customerEditorNotifierProvider'
      '($argument)';
  @$internal
  @override
  CustomerEditorNotifier create() => CustomerEditorNotifier();
  @override
  Override overrideWithValue(CustomerEditorState value) => $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CustomerEditorState>(value));
  @override
  bool operator ==(Object other) =>
      other is CustomerEditorNotifierProvider && other.argument == argument;
  @override
  int get hashCode => argument.hashCode;
}

String _$customerEditorNotifierHash() =>
    r'6b1a7e9f3d2c4b5a8e0f1c2d3b4a596877665544';

final class CustomerEditorNotifierFamily extends $Family
    with
        $ClassFamilyOverride<CustomerEditorNotifier, CustomerEditorState,
            CustomerEditorState, String?, String?> {
  CustomerEditorNotifierFamily._()
      : super(
            retry: null,
            name: r'customerEditorNotifierProvider',
            dependencies: null,
            $allTransitiveDependencies: null,
            isAutoDispose: true);
  CustomerEditorNotifierProvider call({String? customerId}) =>
      CustomerEditorNotifierProvider._(argument: customerId, from: this);
  @override
  String toString() => r'customerEditorNotifierProvider';
}

abstract class _$CustomerEditorNotifier extends $Notifier<CustomerEditorState> {
  late final _$args = ref.$arg as String?;
  String? get customerId => _$args;
  CustomerEditorState build({String? customerId});
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CustomerEditorState, CustomerEditorState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<CustomerEditorState, CustomerEditorState>,
        CustomerEditorState,
        Object?,
        Object?>;
    element.handleCreate(ref, () => build(customerId: _$args));
  }
}
