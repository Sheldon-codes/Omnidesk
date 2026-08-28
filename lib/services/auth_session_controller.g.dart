// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AuthSessionController)
final authSessionControllerProvider = AuthSessionControllerProvider._();

final class AuthSessionControllerProvider
    extends $NotifierProvider<AuthSessionController, AuthState> {
  AuthSessionControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'authSessionControllerProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$authSessionControllerHash();

  @$internal
  @override
  AuthSessionController create() => AuthSessionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthState>(value),
    );
  }
}

String _$authSessionControllerHash() =>
    r'0eeb7406e2bc36b31836c29f4ff3abdd1b66aa24';

abstract class _$AuthSessionController extends $Notifier<AuthState> {
  AuthState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AuthState, AuthState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AuthState, AuthState>, AuthState, Object?, Object?>;
    element.handleCreate(ref, build);
  }
}
