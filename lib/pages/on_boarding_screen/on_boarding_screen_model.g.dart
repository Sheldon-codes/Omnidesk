// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'on_boarding_screen_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(OnBoardingScreenNotifier)
final onBoardingScreenProvider = OnBoardingScreenNotifierProvider._();

final class OnBoardingScreenNotifierProvider
    extends $NotifierProvider<OnBoardingScreenNotifier, OnBoardingScreenState> {
  OnBoardingScreenNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'onBoardingScreenProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$onBoardingScreenNotifierHash();

  @$internal
  @override
  OnBoardingScreenNotifier create() => OnBoardingScreenNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnBoardingScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnBoardingScreenState>(value),
    );
  }
}

String _$onBoardingScreenNotifierHash() =>
    r'92ac95fe3500bdf7f95b925cab1982e883f6b54f';

abstract class _$OnBoardingScreenNotifier
    extends $Notifier<OnBoardingScreenState> {
  OnBoardingScreenState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<OnBoardingScreenState, OnBoardingScreenState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<OnBoardingScreenState, OnBoardingScreenState>,
        OnBoardingScreenState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
