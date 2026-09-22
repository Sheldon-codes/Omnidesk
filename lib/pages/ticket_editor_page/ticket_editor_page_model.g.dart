// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ticket_editor_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TicketEditorNotifier)
final ticketEditorProvider = TicketEditorNotifierFamily._();

final class TicketEditorNotifierProvider
    extends $NotifierProvider<TicketEditorNotifier, TicketEditorState> {
  TicketEditorNotifierProvider._(
      {required TicketEditorNotifierFamily super.from,
      required String? super.argument})
      : super(
          retry: null,
          name: r'ticketEditorProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$ticketEditorNotifierHash();

  @override
  String toString() {
    return r'ticketEditorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TicketEditorNotifier create() => TicketEditorNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TicketEditorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TicketEditorState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TicketEditorNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ticketEditorNotifierHash() =>
    r'0f1e27bd040cbcd24556fbc4b89dd8c8134b683c';

final class TicketEditorNotifierFamily extends $Family
    with
        $ClassFamilyOverride<TicketEditorNotifier, TicketEditorState,
            TicketEditorState, TicketEditorState, String?> {
  TicketEditorNotifierFamily._()
      : super(
          retry: null,
          name: r'ticketEditorProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  TicketEditorNotifierProvider call({
    String? ticketId,
  }) =>
      TicketEditorNotifierProvider._(argument: ticketId, from: this);

  @override
  String toString() => r'ticketEditorProvider';
}

abstract class _$TicketEditorNotifier extends $Notifier<TicketEditorState> {
  late final _$args = ref.$arg as String?;
  String? get ticketId => _$args;

  TicketEditorState build({
    String? ticketId,
  });
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<TicketEditorState, TicketEditorState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<TicketEditorState, TicketEditorState>,
        TicketEditorState,
        Object?,
        Object?>;
    element.handleCreate(
        ref,
        () => build(
              ticketId: _$args,
            ));
  }
}
