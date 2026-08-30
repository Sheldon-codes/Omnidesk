// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_details_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CustomerDetailNotifier)
final customerDetailProvider = CustomerDetailNotifierFamily._();

final class CustomerDetailNotifierProvider
    extends $NotifierProvider<CustomerDetailNotifier, CustomerDetailState> {
  CustomerDetailNotifierProvider._(
      {required CustomerDetailNotifierFamily super.from,
      required String super.argument})
      : super(
          retry: null,
          name: r'customerDetailProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$customerDetailNotifierHash();

  @override
  String toString() {
    return r'customerDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CustomerDetailNotifier create() => CustomerDetailNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CustomerDetailState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CustomerDetailState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CustomerDetailNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$customerDetailNotifierHash() =>
    r'52f4918f2e242ecdf472a6753e4e4503f099a4a1';

final class CustomerDetailNotifierFamily extends $Family
    with
        $ClassFamilyOverride<CustomerDetailNotifier, CustomerDetailState,
            CustomerDetailState, CustomerDetailState, String> {
  CustomerDetailNotifierFamily._()
      : super(
          retry: null,
          name: r'customerDetailProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  CustomerDetailNotifierProvider call({
    required String customerId,
  }) =>
      CustomerDetailNotifierProvider._(argument: customerId, from: this);

  @override
  String toString() => r'customerDetailProvider';
}

abstract class _$CustomerDetailNotifier extends $Notifier<CustomerDetailState> {
  late final _$args = ref.$arg as String;
  String get customerId => _$args;

  CustomerDetailState build({
    required String customerId,
  });
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CustomerDetailState, CustomerDetailState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<CustomerDetailState, CustomerDetailState>,
        CustomerDetailState,
        Object?,
        Object?>;
    element.handleCreate(
        ref,
        () => build(
              customerId: _$args,
            ));
  }
}
