// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_page_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(EmailPageNotifier)
final emailPageProvider = EmailPageNotifierProvider._();

final class EmailPageNotifierProvider
    extends $NotifierProvider<EmailPageNotifier, EmailPageState> {
  EmailPageNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'emailPageProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$emailPageNotifierHash();

  @$internal
  @override
  EmailPageNotifier create() => EmailPageNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EmailPageState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EmailPageState>(value),
    );
  }
}

String _$emailPageNotifierHash() => r'6c8c69d657b6607be0b6025abd645bb4d5050efd';

abstract class _$EmailPageNotifier extends $Notifier<EmailPageState> {
  EmailPageState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<EmailPageState, EmailPageState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<EmailPageState, EmailPageState>,
        EmailPageState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
