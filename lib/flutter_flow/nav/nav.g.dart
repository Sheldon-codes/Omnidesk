// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nav.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The application's single routing boundary.
///
/// Pages navigate through their static route paths; this router owns every
/// authentication, bootstrap, and onboarding redirect in one place.

@ProviderFor(goRouter)
final goRouterProvider = GoRouterProvider._();

/// The application's single routing boundary.
///
/// Pages navigate through their static route paths; this router owns every
/// authentication, bootstrap, and onboarding redirect in one place.

final class GoRouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  /// The application's single routing boundary.
  ///
  /// Pages navigate through their static route paths; this router owns every
  /// authentication, bootstrap, and onboarding redirect in one place.
  GoRouterProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'goRouterProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$goRouterHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return goRouter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$goRouterHash() => r'7badec8aa469e7c4f3cf3cad033337c57c41b687';
