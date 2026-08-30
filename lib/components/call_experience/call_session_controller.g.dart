// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CallSessionController)
final callSessionControllerProvider = CallSessionControllerProvider._();

final class CallSessionControllerProvider
    extends $NotifierProvider<CallSessionController, CallSessionState> {
  CallSessionControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'callSessionControllerProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$callSessionControllerHash();

  @$internal
  @override
  CallSessionController create() => CallSessionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CallSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CallSessionState>(value),
    );
  }
}

String _$callSessionControllerHash() =>
    r'163c47e9670a3a717d72bc98888f8f5ca2da8f7b';

abstract class _$CallSessionController extends $Notifier<CallSessionState> {
  CallSessionState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CallSessionState, CallSessionState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<CallSessionState, CallSessionState>,
        CallSessionState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
