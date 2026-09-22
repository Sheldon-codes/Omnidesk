// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customers_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CustomersPageNotifier)
final customersPageProvider = CustomersPageNotifierProvider._();

final class CustomersPageNotifierProvider
    extends $NotifierProvider<CustomersPageNotifier, CustomersPageState> {
  CustomersPageNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'customersPageProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$customersPageNotifierHash();

  @$internal
  @override
  CustomersPageNotifier create() => CustomersPageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CustomersPageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CustomersPageState>(value),
    );
  }
}

String _$customersPageNotifierHash() =>
    r'd38ffce94b54dd3ddaa2a22ead3e75966038b8ea';

abstract class _$CustomersPageNotifier extends $Notifier<CustomersPageState> {
  CustomersPageState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CustomersPageState, CustomersPageState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<CustomersPageState, CustomersPageState>,
        CustomersPageState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
