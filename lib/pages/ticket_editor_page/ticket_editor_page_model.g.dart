// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ticket_editor_page_model.dart';

// ***************************************************************************
// RiverpodGenerator
// ***************************************************************************

// ignore_for_file: type=lint, type=warning

@ProviderFor(TicketEditorNotifier)
final ticketEditorNotifierProvider = TicketEditorNotifierFamily._();

final class TicketEditorNotifierProvider
    extends $NotifierProvider<TicketEditorNotifier, TicketEditorState> {
  TicketEditorNotifierProvider._(
      {required TicketEditorNotifierFamily super.from,
      required String? super.argument})
      : super(
          retry: null,
          name: r'ticketEditorNotifierProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );
  @override
  String debugGetCreateSourceHash() => r'ticket-editor';
  @override
  TicketEditorNotifier create() => TicketEditorNotifier();
  @override
  bool operator ==(Object other) =>
      other is TicketEditorNotifierProvider && other.argument == argument;
  @override
  int get hashCode => argument.hashCode;
}

final class TicketEditorNotifierFamily extends $Family
    with
        $ClassFamilyOverride<TicketEditorNotifier, TicketEditorState,
            TicketEditorState, TicketEditorState, String?> {
  TicketEditorNotifierFamily._()
      : super(
          retry: null,
          name: r'ticketEditorNotifierProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );
  TicketEditorNotifierProvider call({String? ticketId}) =>
      TicketEditorNotifierProvider._(argument: ticketId, from: this);
}

abstract class _$TicketEditorNotifier extends $Notifier<TicketEditorState> {
  late final _$args = ref.$arg as String?;
  String? get ticketId => _$args;
  TicketEditorState build({String? ticketId});
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<TicketEditorState, TicketEditorState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<TicketEditorState, TicketEditorState>,
        TicketEditorState,
        Object?,
        Object?>;
    element.handleCreate(ref, () => build(ticketId: _$args));
  }
}
