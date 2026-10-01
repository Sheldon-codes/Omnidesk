import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/services/calls/call_media_provider.dart';
import 'package:omnidesk_agent/services/calls/call_media_service.dart';
import 'package:omnidesk_agent/services/calls/call_models.dart';
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

  test('bundled bridge has no runtime CDN dependency and is diagnostic',
      () async {
    final shell =
        await rootBundle.loadString('assets/html/at_call_bridge.html');
    final adapter =
        await rootBundle.loadString('assets/js/omnidesk-call-bridge.js');
    final sdk = await rootBundle
        .loadString('assets/js/africastalking-client-1.0.7.min.js');

    expect(shell, isNot(contains('unpkg.com')));
    expect(shell, contains('data-omnidesk-shell="2.0.0"'));
    expect(adapter, contains("var BRIDGE_VERSION = '2.1.0'"));
    expect(adapter, contains("event: 'diagnostic'"));
    expect(adapter, contains("'client_event_binding_completed'"));
    expect(adapter, contains("'get_user_media_rejected'"));
    // Diagnostics must never substitute browser media APIs. AT's adapter
    // retains ownership of peer creation, standard capture, and playback.
    expect(adapter, isNot(contains('InstrumentedPeerConnection')));
    expect(adapter, isNot(contains('instrumentPeerConnections')));
    expect(adapter, isNot(contains('element.play();')));
    expect(sdk, contains('Africastalking'));
  });

  test('visible WebKit inspector is strictly iOS debug-only', () {
    expect(
      usesIosDebugInspectorFor(
        debugMode: true,
        platform: TargetPlatform.iOS,
      ),
      isTrue,
    );
    expect(
      usesIosDebugInspectorFor(
        debugMode: false,
        platform: TargetPlatform.iOS,
      ),
      isFalse,
    );
    expect(
      usesIosDebugInspectorFor(
        debugMode: true,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
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

  test('supported WebRTC selection rejects the deprecated SIP transport', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(callMediaServiceProvider),
        isA<WebViewCallMediaService>());
  });

  test('engine follows the backend-declared transport', () {
    // The Sept 2026 backend returns transport "webrtc" with no sip block:
    // that must route to the hidden WebView engine.
    final webrtcOnly = CallMediaConfig.fromJson({
      'provider': 'africas_talking',
      'transport': 'webrtc',
      'endpoint_type': 'mobile',
      'webrtc': {'token': 'ATCAPtkn_test'},
      'capabilities': {'webrtc': true},
    });
    expect(
      usesSupportedWebViewMedia(webrtcOnly),
      isTrue,
    );
    expect(
      usesSupportedWebViewMedia(CallMediaConfig.fromJson(_dualBlockConfig())),
      isFalse,
    );
  });

  test('default bridge URL is the known-working HTTPS ngrok shell', () {
    // The bundled bridge still owns executable code; iOS needs this HTTPS
    // document origin for WebKit microphone capture.
    expect(defaultBridgeRemoteUrl.startsWith('https://'), isTrue);
    expect(defaultBridgeRemoteUrl, contains('at_call_bridge.html'));
    expect(defaultBridgeRemoteUrl, contains('ngrok-free.dev'));
  });

  test('bridge origin accepts https remotes, rejects insecure', () {
    expect(
      resolveBridgeOrigin('https://api.omnidesk.africa/at_call_bridge.html')
          .origin,
      CallBridgeOrigin.remote,
    );
    expect(
      resolveBridgeOrigin(
              'https://unvisual-nedra.ngrok-free.dev/at_call_bridge.html')
          .origin,
      CallBridgeOrigin.remote,
    );
    expect(
        resolveBridgeOrigin('http://api.example.com/at_call_bridge.html')
            .origin,
        CallBridgeOrigin.asset);
    expect(resolveBridgeOrigin(null).origin, CallBridgeOrigin.asset);
    expect(resolveBridgeOrigin('').origin, CallBridgeOrigin.asset);
  });
}
