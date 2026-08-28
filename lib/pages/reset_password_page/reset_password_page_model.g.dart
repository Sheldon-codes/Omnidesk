// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reset_password_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ResetPasswordPageNotifier)
final resetPasswordPageProvider = ResetPasswordPageNotifierProvider._();

final class ResetPasswordPageNotifierProvider extends $NotifierProvider<
    ResetPasswordPageNotifier, ResetPasswordPageState> {
  ResetPasswordPageNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'resetPasswordPageProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$resetPasswordPageNotifierHash();

  @$internal
  @override
  ResetPasswordPageNotifier create() => ResetPasswordPageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ResetPasswordPageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ResetPasswordPageState>(value),
    );
  }
}

String _$resetPasswordPageNotifierHash() =>
    r'1d613c3b1743681f4d1a1774ac7a1ac0bb908c6e';

abstract class _$ResetPasswordPageNotifier
    extends $Notifier<ResetPasswordPageState> {
  ResetPasswordPageState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<ResetPasswordPageState, ResetPasswordPageState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<ResetPasswordPageState, ResetPasswordPageState>,
        ResetPasswordPageState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
