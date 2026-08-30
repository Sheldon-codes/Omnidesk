// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ticket_details_page_model.dart';

// ***************************************************************************
// RiverpodGenerator
// ***************************************************************************

// ignore_for_file: type=lint, type=warning

@ProviderFor(TicketDetailsNotifier)
final ticketDetailsNotifierProvider = TicketDetailsNotifierFamily._();

final class TicketDetailsNotifierProvider
    extends $NotifierProvider<TicketDetailsNotifier, TicketDetailsState> {
  TicketDetailsNotifierProvider._(
      {required TicketDetailsNotifierFamily super.from,
      required String super.argument})
      : super(
          retry: null,
          name: r'ticketDetailsNotifierProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );
  @override
  String debugGetCreateSourceHash() => r'ticket-details';
  @override
  TicketDetailsNotifier create() => TicketDetailsNotifier();
  @override
  bool operator ==(Object other) =>
      other is TicketDetailsNotifierProvider && other.argument == argument;
  @override
  int get hashCode => argument.hashCode;
}

final class TicketDetailsNotifierFamily extends $Family
    with
        $ClassFamilyOverride<TicketDetailsNotifier, TicketDetailsState,
            TicketDetailsState, TicketDetailsState, String> {
  TicketDetailsNotifierFamily._()
      : super(
          retry: null,
          name: r'ticketDetailsNotifierProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );
  TicketDetailsNotifierProvider call({required String ticketId}) =>
      TicketDetailsNotifierProvider._(argument: ticketId, from: this);
}

abstract class _$TicketDetailsNotifier extends $Notifier<TicketDetailsState> {
  late final _$args = ref.$arg as String;
  String get ticketId => _$args;
  TicketDetailsState build({required String ticketId});
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<TicketDetailsState, TicketDetailsState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<TicketDetailsState, TicketDetailsState>,
        TicketDetailsState,
        Object?,
        Object?>;
    element.handleCreate(ref, () => build(ticketId: _$args));
  }
}
