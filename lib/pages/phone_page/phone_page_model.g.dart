// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'phone_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PhonePageNotifier)
final phonePageProvider = PhonePageNotifierProvider._();

final class PhonePageNotifierProvider
    extends $NotifierProvider<PhonePageNotifier, PhonePageState> {
  PhonePageNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'phonePageProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$phonePageNotifierHash();

  @$internal
  @override
  PhonePageNotifier create() => PhonePageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhonePageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhonePageState>(value),
    );
  }
}

String _$phonePageNotifierHash() => r'234d20fb40516429e1d609169a936fe6e3f07067';

abstract class _$PhonePageNotifier extends $Notifier<PhonePageState> {
  PhonePageState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PhonePageState, PhonePageState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<PhonePageState, PhonePageState>,
        PhonePageState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
