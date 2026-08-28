// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_metadata_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(deviceMetadataService)
final deviceMetadataServiceProvider = DeviceMetadataServiceProvider._();

final class DeviceMetadataServiceProvider extends $FunctionalProvider<
    DeviceMetadataService,
    DeviceMetadataService,
    DeviceMetadataService> with $Provider<DeviceMetadataService> {
  DeviceMetadataServiceProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'deviceMetadataServiceProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$deviceMetadataServiceHash();

  @$internal
  @override
  $ProviderElement<DeviceMetadataService> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DeviceMetadataService create(Ref ref) {
    return deviceMetadataService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeviceMetadataService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeviceMetadataService>(value),
    );
  }
}

String _$deviceMetadataServiceHash() =>
    r'd27125413a8ddb7fc79316e7ceb3ad0b405a41fa';
