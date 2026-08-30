// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_room_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ConversationStore)
final conversationStoreProvider = ConversationStoreProvider._();

final class ConversationStoreProvider
    extends $NotifierProvider<ConversationStore, List<ConversationThread>> {
  ConversationStoreProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'conversationStoreProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$conversationStoreHash();

  @$internal
  @override
  ConversationStore create() => ConversationStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ConversationThread> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ConversationThread>>(value),
    );
  }
}

String _$conversationStoreHash() => r'f029fabced9b51909109e251e111b72644f01a4a';

abstract class _$ConversationStore extends $Notifier<List<ConversationThread>> {
  List<ConversationThread> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<List<ConversationThread>, List<ConversationThread>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<List<ConversationThread>, List<ConversationThread>>,
        List<ConversationThread>,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(conversationThread)
final conversationThreadProvider = ConversationThreadFamily._();

final class ConversationThreadProvider extends $FunctionalProvider<
    ConversationThread?,
    ConversationThread?,
    ConversationThread?> with $Provider<ConversationThread?> {
  ConversationThreadProvider._(
      {required ConversationThreadFamily super.from,
      required String super.argument})
      : super(
          retry: null,
          name: r'conversationThreadProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$conversationThreadHash();

  @override
  String toString() {
    return r'conversationThreadProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ConversationThread?> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ConversationThread? create(Ref ref) {
    final argument = this.argument as String;
    return conversationThread(
      ref,
      argument,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConversationThread? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConversationThread?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConversationThreadProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$conversationThreadHash() =>
    r'2002d02ea85cd5552c7ba090ecab1f6b23d06154';

final class ConversationThreadFamily extends $Family
    with $FunctionalFamilyOverride<ConversationThread?, String> {
  ConversationThreadFamily._()
      : super(
          retry: null,
          name: r'conversationThreadProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  ConversationThreadProvider call(
    String conversationId,
  ) =>
      ConversationThreadProvider._(argument: conversationId, from: this);

  @override
  String toString() => r'conversationThreadProvider';
}
