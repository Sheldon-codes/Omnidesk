// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LoginPageNotifier)
final loginPageProvider = LoginPageNotifierProvider._();

final class LoginPageNotifierProvider
    extends $NotifierProvider<LoginPageNotifier, LoginPageState> {
  LoginPageNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'loginPageProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$loginPageNotifierHash();

  @$internal
  @override
  LoginPageNotifier create() => LoginPageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LoginPageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LoginPageState>(value),
    );
  }
}

String _$loginPageNotifierHash() => r'f90971aba3b42028f3f2f5de5cb09b6468918086';

abstract class _$LoginPageNotifier extends $Notifier<LoginPageState> {
  LoginPageState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<LoginPageState, LoginPageState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<LoginPageState, LoginPageState>,
        LoginPageState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
