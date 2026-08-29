// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tickets_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TicketsPageNotifier)
final ticketsPageProvider = TicketsPageNotifierProvider._();

final class TicketsPageNotifierProvider
    extends $NotifierProvider<TicketsPageNotifier, TicketsPageState> {
  TicketsPageNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'ticketsPageProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$ticketsPageNotifierHash();

  @$internal
  @override
  TicketsPageNotifier create() => TicketsPageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TicketsPageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TicketsPageState>(value),
    );
  }
}

String _$ticketsPageNotifierHash() =>
    r'b583332d76353a9d3332c464a33afc2518088c2b';

abstract class _$TicketsPageNotifier extends $Notifier<TicketsPageState> {
  TicketsPageState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<TicketsPageState, TicketsPageState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<TicketsPageState, TicketsPageState>,
        TicketsPageState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
