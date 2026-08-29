// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_details_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// ignore_for_file: type=lint, type=warning

@ProviderFor(CustomerDetailNotifier)
final customerDetailNotifierProvider = CustomerDetailNotifierFamily._();

final class CustomerDetailNotifierProvider
    extends $NotifierProvider<CustomerDetailNotifier, CustomerDetailState> {
  CustomerDetailNotifierProvider._(
      {required CustomerDetailNotifierFamily super.from,
      required String super.argument})
      : super(
          retry: null,
          name: r'customerDetailNotifierProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$customerDetailNotifierHash();

  @override
  CustomerDetailNotifier create() => CustomerDetailNotifier();

  @override
  Override overrideWithValue(CustomerDetailState value) => $ProviderOverride(
        origin: this,
        providerOverride: $SyncValueProvider<CustomerDetailState>(value),
      );

  @override
  bool operator ==(Object other) =>
      other is CustomerDetailNotifierProvider && other.argument == argument;

  @override
  int get hashCode => argument.hashCode;
}

String _$customerDetailNotifierHash() =>
    r'c71a6a49b3ce46e9a7f3b0d4a1e5c8f2d6b9e0a4';

final class CustomerDetailNotifierFamily extends $Family
    with
        $ClassFamilyOverride<CustomerDetailNotifier, CustomerDetailState,
            CustomerDetailState, String, String> {
  CustomerDetailNotifierFamily._()
      : super(
          retry: null,
          name: r'customerDetailNotifierProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  CustomerDetailNotifierProvider call({required String customerId}) =>
      CustomerDetailNotifierProvider._(argument: customerId, from: this);

  @override
  String toString() => r'customerDetailNotifierProvider';
}

abstract class _$CustomerDetailNotifier extends $Notifier<CustomerDetailState> {
  late final _$args = ref.$arg as String;
  String get customerId => _$args;

  CustomerDetailState build({required String customerId});

  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CustomerDetailState, CustomerDetailState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<CustomerDetailState, CustomerDetailState>,
        CustomerDetailState,
        Object?,
        Object?>;
    element.handleCreate(ref, () => build(customerId: _$args));
  }
}
