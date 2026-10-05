import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/services/calls/android_native_call_media_service.dart';
import 'package:omnidesk_agent/services/calls/call_models.dart';
import 'package:omnidesk_agent/services/calls/call_media_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methodChannel = MethodChannel('test/native_media');
  const eventChannel = EventChannel('test/native_media_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'initialize') return {'sessionId': 'native-session'};
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  test('native media is Android-only and enabled by default', () {
    expect(useAndroidNativeAtMedia, isTrue);
    expect(
      shouldUseAndroidNativeAtMedia(
        platform: TargetPlatform.android,
        enabled: true,
      ),
      isTrue,
    );
    expect(
      shouldUseAndroidNativeAtMedia(
        platform: TargetPlatform.android,
        enabled: false,
      ),
      isFalse,
    );
    expect(
      shouldUseAndroidNativeAtMedia(
        platform: TargetPlatform.iOS,
        enabled: true,
      ),
      isFalse,
    );
  });

  test('initialize forwards backend gateway and ephemeral token only to native',
      () async {
    final config = CallMediaConfig.fromJson({
      'provider': 'africas_talking',
      'transport': 'webrtc',
      'endpoint_type': 'mobile',
      'webrtc': {
        'token': 'ATCAP_ephemeral',
        'gateway_url': 'wss://gateway.example/connect',
      },
    });
    Map<Object?, Object?>? sent;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'dispose') return null;
      expect(call.method, 'initialize');
      sent = call.arguments as Map<Object?, Object?>;
      return {'sessionId': 'native-session'};
    });
    final service = AndroidNativeCallMediaService(
      channel: methodChannel,
      eventChannel: eventChannel,
    );
    expect(await service.initialize(config), 'native-session');
    expect(sent?['gatewayUrl'], 'wss://gateway.example/connect');
    expect(sent?['token'], 'ATCAP_ephemeral');
    await service.dispose();
  });

  test('initialization carries inbound correlation identity and answer action',
      () async {
    final config = CallMediaConfig.fromJson({
      'provider': 'africas_talking',
      'transport': 'webrtc',
      'endpoint_type': 'mobile',
      'webrtc': {
        'token': 'ATCAP_ephemeral',
        'gateway_url': 'wss://gateway.example/connect',
      },
    });
    final methods = <String>[];
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      methods.add(call.method);
      if (call.method == 'initialize') {
        expect((call.arguments as Map)['incomingCallId'], 'incoming-1');
        return {'sessionId': 'native-session'};
      }
      return null;
    });
    final service = AndroidNativeCallMediaService(
      channel: methodChannel,
      eventChannel: eventChannel,
    );
    await service.initialize(config, incomingCallId: 'incoming-1');
    await service.answerIncoming(callSid: 'incoming-1');
    expect(methods, containsAll(['initialize', 'answer']));
    await service.dispose();
  });

  test('native media forwards outbound peer operations without fallback',
      () async {
    final service = AndroidNativeCallMediaService(
      channel: methodChannel,
      eventChannel: eventChannel,
    );
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'dial') return {'sessionId': 'native-session'};
      return null;
    });
    expect(
      await service.dial(callSid: 'sid', phoneNumber: '+254700000000'),
      'native-session',
    );
    await service.setMuted(true);
    await service.setHeld(true);
    await service.sendDtmf('4');
    await service.endMedia('native-session');
    await service.dispose();
  });

  test('system audio readiness is requested for the matching Telecom call',
      () async {
    Map<Object?, Object?>? arguments;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'prepareSystemAudio');
      arguments = call.arguments as Map<Object?, Object?>;
      return null;
    });
    final service = AndroidNativeCallMediaService(
      channel: methodChannel,
      eventChannel: eventChannel,
    );
    await service.prepareSystemAudio(
        systemCallId: 'backend-call-42', incoming: true);
    expect(arguments, {'systemCallId': 'backend-call-42', 'incoming': true});
    await service.dispose();
  });

  test('Flutter adapter detach does not dispose service-owned registration',
      () async {
    var nativeDisposeCalls = 0;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'dispose') nativeDisposeCalls++;
      return null;
    });
    final service = AndroidNativeCallMediaService(
      channel: methodChannel,
      eventChannel: eventChannel,
    );

    await service.dispose();

    expect(nativeDisposeCalls, 0);
  });

  test('explicit registration disposal reaches the foreground service',
      () async {
    var nativeDisposeCalls = 0;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'dispose') nativeDisposeCalls++;
      return null;
    });
    final service = AndroidNativeCallMediaService(
      channel: methodChannel,
      eventChannel: eventChannel,
    );

    await service.disposeRegistration();

    expect(nativeDisposeCalls, 1);
    await service.dispose();
  });
}
