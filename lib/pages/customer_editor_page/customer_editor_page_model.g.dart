// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_editor_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
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
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$customersStoreHash();

  @$internal
  @override
  CustomersStore create() => CustomersStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CustomerRecord> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CustomerRecord>>(value),
    );
  }
}

String _$customersStoreHash() => r'82f4fab7e2cfcfcd7db4c8edc4b8e53c27478c43';

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
final customerEditorProvider = CustomerEditorNotifierFamily._();

final class CustomerEditorNotifierProvider
    extends $NotifierProvider<CustomerEditorNotifier, CustomerEditorState> {
  CustomerEditorNotifierProvider._(
      {required CustomerEditorNotifierFamily super.from,
      required String? super.argument})
      : super(
          retry: null,
          name: r'customerEditorProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$customerEditorNotifierHash();

  @override
  String toString() {
    return r'customerEditorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CustomerEditorNotifier create() => CustomerEditorNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CustomerEditorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CustomerEditorState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CustomerEditorNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$customerEditorNotifierHash() =>
    r'c80afacf3f9c77a8736f04313d004473ee217400';

final class CustomerEditorNotifierFamily extends $Family
    with
        $ClassFamilyOverride<CustomerEditorNotifier, CustomerEditorState,
            CustomerEditorState, CustomerEditorState, String?> {
  CustomerEditorNotifierFamily._()
      : super(
          retry: null,
          name: r'customerEditorProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  CustomerEditorNotifierProvider call({
    String? customerId,
  }) =>
      CustomerEditorNotifierProvider._(argument: customerId, from: this);

  @override
  String toString() => r'customerEditorProvider';
}

abstract class _$CustomerEditorNotifier extends $Notifier<CustomerEditorState> {
  late final _$args = ref.$arg as String?;
  String? get customerId => _$args;

  CustomerEditorState build({
    String? customerId,
  });
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CustomerEditorState, CustomerEditorState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<CustomerEditorState, CustomerEditorState>,
        CustomerEditorState,
        Object?,
        Object?>;
    element.handleCreate(
        ref,
        () => build(
              customerId: _$args,
            ));
  }
}
