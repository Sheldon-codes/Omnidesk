// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'forgot_password_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ForgotPasswordPageNotifier)
final forgotPasswordPageProvider = ForgotPasswordPageNotifierProvider._();

final class ForgotPasswordPageNotifierProvider extends $NotifierProvider<
    ForgotPasswordPageNotifier, ForgotPasswordPageState> {
  ForgotPasswordPageNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'forgotPasswordPageProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$forgotPasswordPageNotifierHash();

  @$internal
  @override
  ForgotPasswordPageNotifier create() => ForgotPasswordPageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ForgotPasswordPageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ForgotPasswordPageState>(value),
    );
  }
}

String _$forgotPasswordPageNotifierHash() =>
    r'c14a0f5e2959c1a58a85a44b76d7931ec6b3f79b';

abstract class _$ForgotPasswordPageNotifier
    extends $Notifier<ForgotPasswordPageState> {
  ForgotPasswordPageState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<ForgotPasswordPageState, ForgotPasswordPageState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<ForgotPasswordPageState, ForgotPasswordPageState>,
        ForgotPasswordPageState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
