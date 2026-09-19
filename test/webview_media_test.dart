import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/services/calls/call_media_provider.dart';
import 'package:omnidesk_agent/services/calls/call_media_service.dart';
import 'package:omnidesk_agent/services/calls/call_models.dart';
import 'package:omnidesk_agent/services/calls/native_call_service.dart';
import 'package:omnidesk_agent/services/calls/webview_call_media_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Map<String, dynamic> _dualBlockConfig() => {
      'success': true,
      'provider': 'africas_talking',
      'transport': 'sip',
      'endpoint_type': 'mobile',
      'sip': {
        'uri': 'sip:agent@ke.sip.example.test',
        'username': 'agent',
        'password': 'sip-secret',
        'registrar': 'ke.sip.example.test',
        'domain': 'ke.sip.example.test',
        'proxy': 'ke.sip.example.test:5061',
        'transport': 'tls',
        'port': 5061,
      },
      'webrtc': {
        'token': 'ATCAPtkn_test',
        'client_name': 'agent_1',
        'gateway_url': 'wss://webrtc.example.test:4443',
      },
      'capabilities': {'hold': true, 'dtmf': true, 'native_incoming': true},
    };

class _FakeNative implements NativeCallService {
  final _events = StreamController<NativeCallEvent>.broadcast();
  final calls = <String>[];
  Map<String, Object?>? lastArgs;

  @override
  Stream<NativeCallEvent> get events => _events.stream;
  @override
  Future<String?> readVoipPushToken() async => null;
  @override
  Future<CallOffer?> takePendingOffer() async => null;
  @override
  Future<NativeCallEvent?> takePendingAction() async => null;
  @override
  Future<void> presentIncoming(CallOffer offer) async {}
  @override
  Future<void> dismiss(CallId callId) async {}
  @override
  Future<String> ensureRegistered(CallMediaConfig config,
      {CallId? incomingCallId}) async {
    calls.add('ensureRegistered');
    return 'media-1';
  }

  @override
  Future<String> startOutgoingMedia(
      {required String callSid, required String targetSipUri}) async {
    calls.add('startOutgoingMedia:$targetSipUri');
    lastArgs = {'callSid': callSid, 'targetSipUri': targetSipUri};
    return 'media-1';
  }

  @override
  Future<void> endMedia(String mediaSessionId) async {}
  @override
  Future<void> setMuted(bool enabled) async {}
  @override
  Future<void> setSpeaker(bool enabled) async {}
  @override
  Future<void> setHeld(bool enabled) async {}
  @override
  Future<void> sendDtmf(String digit) async {}

  void emit(NativeCallEvent event) => _events.add(event);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('media config parses dual sip+webrtc blocks', () {
    final config = CallMediaConfig.fromJson(_dualBlockConfig());
    expect(config.canAuthenticate, isTrue);
    expect(config.canUseWebRtc, isTrue);
    expect(config.webrtcToken, 'ATCAPtkn_test');
    expect(config.webrtcGatewayUrl, 'wss://webrtc.example.test:4443');
    expect(config.webrtcClientName, 'agent_1');

    final sipOnly = CallMediaConfig.fromJson({
      'provider': 'africas_talking',
      'transport': 'sip',
      'endpoint_type': 'mobile',
      'sip': {'uri': 'x', 'username': 'y'},
    });
    expect(sipOnly.canUseWebRtc, isFalse);
    expect(sipOnly.webrtcToken, isNull);
  });

  test('bridge protocol maps known events, ignores noise', () {
    expect(
      parseBridgeEvent({'v': 1, 'event': 'ready'}, callSid: null)?.type,
      CallMediaEventType.ready,
    );
    expect(
      parseBridgeEvent({'v': 1, 'event': 'connected'}, callSid: null)?.type,
      CallMediaEventType.connected,
    );
    expect(
      parseBridgeEvent(
        {'v': 1, 'event': 'error', 'reason': 'boom'},
        callSid: null,
      )?.reason,
      'boom',
    );
    expect(parseBridgeEvent({'v': 2, 'event': 'ready'}, callSid: null), isNull);
    expect(parseBridgeEvent({'v': 1, 'event': 'nope'}, callSid: null), isNull);
    expect(parseBridgeEvent('garbage', callSid: null), isNull);
    // Heartbeats are consumed by the watchdog, not the state machine.
    expect(parseBridgeEvent({'v': 1, 'event': 'heartbeat'}, callSid: null),
        isNull);
  });

  test('normalizes JSON-encoded WebView string results across platforms', () {
    expect(normalizeJavaScriptStringResult('"bridge_ok"'), 'bridge_ok');
    expect(normalizeJavaScriptStringResult('bridge_ok'), 'bridge_ok');
    expect(
        normalizeJavaScriptStringResult('"bridge_missing"'), 'bridge_missing');
  });

  test('page console lines are captured without touching streams', () {
    final service = WebViewCallMediaService();
    addTearDown(service.dispose);
    service.noteConsoleMessage('log', 'Sending initial request');
    service.noteConsoleMessage('error', '  ');
    service.noteConsoleMessage('error', 'Auth rejected');
    // Empty lines ignored; latest lines retained for timeout reports.
    expect(service.consoleTailForTest, [
      'Sending initial request',
      'Auth rejected',
    ]);
  });

  test('baresip media service preserves register-then-dial flow', () async {
    final fake = _FakeNative();
    final service = BaresipCallMediaService(native: fake);
    final config = CallMediaConfig.fromJson(_dualBlockConfig());

    final init = service.initialize(config);
    await Future<void>.delayed(Duration.zero);
    fake.emit(const NativeCallEvent(
      type: NativeCallEventType.registered,
      mediaSessionId: 'media-1',
    ));
    expect(await init, 'media-1');

    final session = await service.dial(
      callSid: 'CA1',
      phoneNumber: '+254700000001',
      sipTargetUri: 'sip:+254700000001@ke.sip.example.test',
    );
    expect(session, 'media-1');
    expect(fake.lastArgs?['callSid'], 'CA1');
    expect(
      fake.calls,
      [
        'ensureRegistered',
        'startOutgoingMedia:sip:+254700000001@ke.sip.example.test'
      ],
    );
    await service.dispose();
  });

  test('baresip media service surfaces registration failure', () async {
    final fake = _FakeNative();
    final service = BaresipCallMediaService(native: fake);
    final init =
        service.initialize(CallMediaConfig.fromJson(_dualBlockConfig()));
    await Future<void>.delayed(Duration.zero);
    fake.emit(const NativeCallEvent(
      type: NativeCallEventType.failed,
      mediaSessionId: 'media-1',
      reason: 'nope',
    ));
    await expectLater(init, throwsA(isA<MediaUnavailable>()));
    await service.dispose();
  });

  test('re-init settle delay honors the 5s gateway cooldown', () {
    expect(
      settleDelaySince(null, DateTime(2026, 9, 18, 12)),
      Duration.zero,
    );
    expect(
      settleDelaySince(
        DateTime(2026, 9, 18, 12, 0, 0),
        DateTime(2026, 9, 18, 12, 0, 2),
      ),
      const Duration(seconds: 3),
    );
    expect(
      settleDelaySince(
        DateTime(2026, 9, 18, 12, 0, 0),
        DateTime(2026, 9, 18, 12, 1, 0),
      ),
      Duration.zero,
    );
  });

  test('bridge events retain call and media-session correlation', () {
    final event = parseBridgeEvent({
      'v': 1,
      'event': 'connected',
      'callSid': 'CA1',
      'sessionId': 'webview-media-1',
    }, callSid: null);
    expect(event?.callSid, 'CA1');
    expect(event?.mediaSessionId, 'webview-media-1');
  });

  test('media provider defaults to baresip, switches on flag', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(callMediaServiceProvider),
        isA<BaresipCallMediaService>());
    container.read(useWebViewMediaProvider.notifier).setEnabled(true);
    expect(container.read(callMediaServiceProvider),
        isA<WebViewCallMediaService>());
  });

  test('engine follows the backend-declared transport', () {
    // The Sept 2026 backend returns transport "webrtc" with no sip block:
    // that must route to the hidden WebView engine, never Baresip.
    final webrtcOnly = CallMediaConfig.fromJson({
      'provider': 'africas_talking',
      'transport': 'webrtc',
      'endpoint_type': 'mobile',
      'webrtc': {'token': 'ATCAPtkn_test'},
      'capabilities': {'webrtc': true},
    });
    expect(
      useWebViewEngine(forceWebView: false, config: webrtcOnly),
      isTrue,
    );
    expect(
      useWebViewEngine(
          forceWebView: false,
          config: CallMediaConfig.fromJson(_dualBlockConfig())),
      isFalse,
    );
    // Manual POC override wins over everything, including SIP configs.
    expect(
      useWebViewEngine(
          forceWebView: true,
          config: CallMediaConfig.fromJson(_dualBlockConfig())),
      isTrue,
    );
  });
}
