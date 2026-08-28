// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'change_password_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ChangePasswordPageNotifier)
final changePasswordPageProvider = ChangePasswordPageNotifierProvider._();

final class ChangePasswordPageNotifierProvider extends $NotifierProvider<
    ChangePasswordPageNotifier, ChangePasswordPageState> {
  ChangePasswordPageNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'changePasswordPageProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$changePasswordPageNotifierHash();

  @$internal
  @override
  ChangePasswordPageNotifier create() => ChangePasswordPageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChangePasswordPageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChangePasswordPageState>(value),
    );
  }
}

String _$changePasswordPageNotifierHash() =>
    r'1029abf863534d4ba6daa94042783e9a7ad7d8b4';

abstract class _$ChangePasswordPageNotifier
    extends $Notifier<ChangePasswordPageState> {
  ChangePasswordPageState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<ChangePasswordPageState, ChangePasswordPageState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<ChangePasswordPageState, ChangePasswordPageState>,
        ChangePasswordPageState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
