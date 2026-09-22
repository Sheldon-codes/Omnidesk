// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ticket_details_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TicketDetailsNotifier)
final ticketDetailsProvider = TicketDetailsNotifierFamily._();

final class TicketDetailsNotifierProvider
    extends $NotifierProvider<TicketDetailsNotifier, TicketDetailsState> {
  TicketDetailsNotifierProvider._(
      {required TicketDetailsNotifierFamily super.from,
      required String super.argument})
      : super(
          retry: null,
          name: r'ticketDetailsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$ticketDetailsNotifierHash();

  @override
  String toString() {
    return r'ticketDetailsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TicketDetailsNotifier create() => TicketDetailsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TicketDetailsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TicketDetailsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TicketDetailsNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ticketDetailsNotifierHash() =>
    r'83a03bbe0e8af8337102fe01bcb9fef00a3c3935';

final class TicketDetailsNotifierFamily extends $Family
    with
        $ClassFamilyOverride<TicketDetailsNotifier, TicketDetailsState,
            TicketDetailsState, TicketDetailsState, String> {
  TicketDetailsNotifierFamily._()
      : super(
          retry: null,
          name: r'ticketDetailsProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  TicketDetailsNotifierProvider call({
    required String ticketId,
  }) =>
      TicketDetailsNotifierProvider._(argument: ticketId, from: this);

  @override
  String toString() => r'ticketDetailsProvider';
}

abstract class _$TicketDetailsNotifier extends $Notifier<TicketDetailsState> {
  late final _$args = ref.$arg as String;
  String get ticketId => _$args;

  TicketDetailsState build({
    required String ticketId,
  });
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<TicketDetailsState, TicketDetailsState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<TicketDetailsState, TicketDetailsState>,
        TicketDetailsState,
        Object?,
        Object?>;
    element.handleCreate(
        ref,
        () => build(
              ticketId: _$args,
            ));
  }
}
