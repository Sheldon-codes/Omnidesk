import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/services/calls/call_media_service.dart';
import 'package:omnidesk_agent/services/calls/call_models.dart';
import 'package:omnidesk_agent/services/calls/ios_native_call_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native controls map to the media channel and validate capabilities',
      () async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('test/ios_native_media_controls');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        return <String, Object?>{'sessionId': 'native-test-session'};
      }
      return null;
    });
    final service = IOSNativeCallMediaService(channel: channel);
    addTearDown(() async {
      await service.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    final config = CallMediaConfig.fromJson({
      'provider': 'africas_talking',
      'transport': 'webrtc',
      'endpoint_type': 'mobile',
      'webrtc': {
        'token': 'test-capability',
        'client_name': 'agent-test',
        'gateway_url': 'wss://webrtc.example.test/connect',
      },
      'capabilities': {
        'hold': true,
        'dtmf': true,
        'native_incoming': true,
      },
    });

    expect(
      await service.initialize(config),
      'native-test-session',
    );
    await service.setHeld(true);
    await service.sendDtmf('#');
    await expectLater(service.sendDtmf('A'), throwsA(isA<MediaUnavailable>()));

    expect(calls.map((call) => call.method), [
      'initialize',
      'setHeld',
      'sendDtmf',
    ]);
    expect(calls[1].arguments, {'enabled': true});
    expect(calls[2].arguments, {'digit': '#'});
  });

  test('native hold and DTMF are rejected when provider lacks capability',
      () async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('test/ios_native_media_unsupported');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') {
        return <String, Object?>{'sessionId': 'native-test-session'};
      }
      return null;
    });
    final service = IOSNativeCallMediaService(channel: channel);
    addTearDown(() async {
      await service.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    final config = CallMediaConfig.fromJson({
      'provider': 'africas_talking',
      'transport': 'webrtc',
      'endpoint_type': 'mobile',
      'webrtc': {
        'token': 'test-capability',
        'client_name': 'agent-test',
        'gateway_url': 'wss://webrtc.example.test/connect',
      },
      'capabilities': {'hold': false, 'dtmf': false},
    });
    await service.initialize(config);

    await expectLater(service.setHeld(true), throwsA(isA<MediaUnavailable>()));
    await expectLater(service.sendDtmf('1'), throwsA(isA<MediaUnavailable>()));
  });
}
