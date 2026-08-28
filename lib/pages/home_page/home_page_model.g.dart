// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(homePage)
final homePageProvider = HomePageProvider._();

final class HomePageProvider
    extends $FunctionalProvider<HomePageState, HomePageState, HomePageState>
    with $Provider<HomePageState> {
  HomePageProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'homePageProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$homePageHash();

  @$internal
  @override
  $ProviderElement<HomePageState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HomePageState create(Ref ref) {
    return homePage(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HomePageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HomePageState>(value),
    );
  }
}

String _$homePageHash() => r'721964c6252dcd170d534a4246f056e0fdc984a6';
