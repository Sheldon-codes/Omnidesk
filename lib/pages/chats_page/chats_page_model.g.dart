// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chats_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ChatsPageNotifier)
final chatsPageProvider = ChatsPageNotifierProvider._();

final class ChatsPageNotifierProvider
    extends $NotifierProvider<ChatsPageNotifier, ChatsPageState> {
  ChatsPageNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'chatsPageProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$chatsPageNotifierHash();

  @$internal
  @override
  ChatsPageNotifier create() => ChatsPageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatsPageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatsPageState>(value),
    );
  }
}

String _$chatsPageNotifierHash() => r'd0afbd5782e5d191f7de20adaf59d893fcac8e7f';

abstract class _$ChatsPageNotifier extends $Notifier<ChatsPageState> {
  ChatsPageState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ChatsPageState, ChatsPageState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<ChatsPageState, ChatsPageState>,
        ChatsPageState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
