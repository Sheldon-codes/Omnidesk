import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/services/realtime/realtime_config.dart';
import 'package:omnidesk_agent/services/realtime/realtime_event.dart';
import 'package:omnidesk_agent/services/realtime/realtime_service.dart';
import 'package:omnidesk_agent/services/realtime/realtime_transport.dart';
import 'package:omnidesk_agent/services/realtime/reverb_transport.dart';
import 'package:omnidesk_agent/services/realtime/whatsapp_outbox.dart';

class FakeTransport implements RealtimeTransport {
  final _states = StreamController<RealtimeConnectionState>.broadcast();
  final _events = StreamController<TransportEnvelope>.broadcast();
  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;
  final subscribed = <String>{};

  @override
  Stream<RealtimeConnectionState> get connectionState => _states.stream;
  @override
  RealtimeConnectionState get currentState => _state;
  @override
  Stream<TransportEnvelope> get events => _events.stream;

  void emit(TransportEnvelope e) => _events.add(e);
  void setState(RealtimeConnectionState s) {
    _state = s;
    _states.add(s);
  }

  @override
  Future<void> connect() async {
    _state = RealtimeConnectionState.connected;
    _states.add(_state);
  }

  @override
  Future<void> disconnect() async {
    _state = RealtimeConnectionState.disconnected;
    _states.add(_state);
  }

  @override
  Future<void> subscribe(String c) async => subscribed.add(c);
  @override
  Future<void> unsubscribe(String c) async => subscribed.remove(c);
  @override
  Future<void> dispose() async {
    await _states.close();
    await _events.close();
  }
}

class ControlledPusherFacade implements PusherFacade {
  final _events = StreamController<FacadeEvent>.broadcast();
  final _states = StreamController<String>.broadcast();
  final subscribed = <String>[];
  Completer<void>? pauseNextSubscribe;

  @override
  Stream<FacadeEvent> get onEvent => _events.stream;

  @override
  Stream<String> get onConnectionStateChange => _states.stream;

  @override
  Future<void> init({
    required String apiKey,
    required String cluster,
    bool? useTLS,
    String? authEndpoint,
    String? host,
    int? wsPort,
    int? wssPort,
  }) async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> subscribe({required String channelName}) async {
    subscribed.add(channelName);
    final pause = pauseNextSubscribe;
    pauseNextSubscribe = null;
    if (pause != null) await pause.future;
  }

  @override
  Future<void> unsubscribe({required String channelName}) async {}

  Future<void> dispose() async {
    await _events.close();
    await _states.close();
  }
}

void main() {
  test('decodes ticket.message + typing, dedupes timeline fan-out', () async {
    final transport = FakeTransport();
    final service = RealtimeService(
      transport: transport,
      config: const RealtimeConfig(
        enabled: true,
        appKey: 'k',
        cluster: 'mt1',
        host: '127.0.0.1',
        wsPort: 8086,
        wssPort: 8086,
        useTls: false,
        httpAuthEndpoint: null,
      ),
    );
    final seen = <RealtimeEvent>[];
    final sub = service.events.listen(seen.add);

    await service.watchTicket('14');
    expect(transport.subscribed, contains('ticket.14'));

    transport.emit(const TransportEnvelope(
      channel: 'ticket.14',
      eventName: '.ticket.message',
      data: {'ticket_id': 14, 'timeline_id': 504, 'description': 'hi'},
    ));
    // Duplicate via `tickets` fan-out collapses.
    transport.emit(const TransportEnvelope(
      channel: 'tickets',
      eventName: 'NewTicketMessage',
      data: {'ticket_id': 14, 'timeline_id': 504, 'description': 'hi'},
    ));
    transport.emit(const TransportEnvelope(
      channel: 'ticket.14',
      eventName: '.ticket.typing',
      data: {'ticket_id': 14, 'who': 'customer', 'is_typing': true},
    ));
    await Future.delayed(const Duration(milliseconds: 50));

    expect(seen.whereType<TicketMessageEvent>().length, 1);
    expect(seen.whereType<TicketTypingEvent>().length, 1);
    await sub.cancel();
    await service.dispose();
  });

  test('outbox backoff schedule caps at 5 attempts', () {
    expect(WhatsAppOutbox.backoffForAttempt(0), const Duration(seconds: 2));
    expect(WhatsAppOutbox.backoffForAttempt(4), const Duration(minutes: 10));
    expect(WhatsAppOutbox.backoffForAttempt(99), const Duration(minutes: 10));
  });

  test('realtime config derives host + tls from api base', () {
    final config = RealtimeConfig.fromEnv({
      'API_BASE_URL': 'https://api.example.com/api/v1',
      'REVERB_APP_KEY': 'k',
    });
    expect(config.host, 'api.example.com');
    expect(config.useTls, isTrue);
    expect(config.enabled, isTrue);
    // Remote hosts default to scheme ports (ngrok/proxy rarely expose 8086).
    expect(config.wssPort, 443);
    expect(config.wsPort, 80);
  });

  test('realtime config keeps loopback reverb defaults', () {
    final config = RealtimeConfig.fromEnv({
      'API_BASE_URL': 'http://127.0.0.1:8000/api/v1',
      'REVERB_APP_KEY': 'k',
    });
    expect(config.host, '127.0.0.1');
    expect(config.useTls, isFalse);
    expect(config.wssPort, 8086);
    expect(config.wsPort, 8086);
  });

  test('realtime config rejects an invalid websocket port', () {
    final config = RealtimeConfig.fromEnv({
      'API_BASE_URL': 'https://app.omnidesk.africa/api/v1',
      'REVERB_WSS_PORT': '0',
    });

    expect(config.wssPort, 443);
  });

  test('resubscribe tolerates channels being removed during async I/O',
      () async {
    final facade = ControlledPusherFacade();
    final transport = ReverbTransport(
      const RealtimeConfig(
        enabled: true,
        appKey: 'k',
        cluster: 'mt1',
        host: '127.0.0.1',
        wsPort: 8086,
        wssPort: 8086,
        useTls: false,
        httpAuthEndpoint: null,
      ),
      facade,
    );
    await transport.subscribe('tickets');
    await transport.subscribe('ticket.14');

    final pause = Completer<void>();
    facade.pauseNextSubscribe = pause;
    final resubscribe = transport.resubscribeAll();
    await Future<void>.delayed(Duration.zero);
    await transport.unsubscribe('ticket.14');
    pause.complete();
    await resubscribe;

    expect(facade.subscribed, ['tickets', 'ticket.14', 'tickets']);
    await transport.dispose();
    await facade.dispose();
  });
}
