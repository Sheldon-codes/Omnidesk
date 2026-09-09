import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:pusher_channels_flutter/pusher_channels_flutter.dart'
    as pusher;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'realtime_config.dart';
import 'realtime_event.dart';
import 'realtime_transport.dart';

/// Thin seam over event sources so unit tests can inject fakes without
/// native method channels or real sockets.
abstract class PusherFacade {
  Stream<FacadeEvent> get onEvent;
  Stream<String> get onConnectionStateChange;
  Future<void> init({
    required String apiKey,
    required String cluster,
    bool? useTLS,
    String? authEndpoint,
    String? host,
    int? wsPort,
    int? wssPort,
  });
  Future<void> connect();
  Future<void> disconnect();
  Future<void> subscribe({required String channelName});
  Future<void> unsubscribe({required String channelName});
}

class FacadeEvent {
  const FacadeEvent({
    required this.channelName,
    required this.eventName,
    required this.data,
  });
  final String channelName;
  final String eventName;
  final String data;
}

/// Production facade delegating to `pusher_channels_flutter`.
///
/// NOTE: the plugin exposes Pusher-cloud parameters only (no custom host on
/// Android). It is used when the configured host is a Pusher endpoint; all
/// self-hosted Reverb hosts go through [ReverbSocketFacade] below.
class PusherChannelsFacade implements PusherFacade {
  PusherChannelsFacade([pusher.PusherChannelsFlutter? plugin])
      : _plugin = plugin ?? pusher.PusherChannelsFlutter.getInstance();

  final pusher.PusherChannelsFlutter _plugin;
  final _events = StreamController<FacadeEvent>.broadcast();
  final _states = StreamController<String>.broadcast();

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
  }) async {
    await _plugin.init(
      apiKey: apiKey,
      cluster: cluster,
      useTLS: useTLS ?? false,
      authEndpoint: authEndpoint,
      onEvent: (event) {
        final data = event.data;
        _events.add(FacadeEvent(
          channelName: event.channelName,
          eventName: event.eventName,
          data: data is String ? data : jsonEncode(data ?? {}),
        ));
      },
      onConnectionStateChange: (current, previous) {
        _states.add(current);
      },
      onError: (message, code, error) {
        developer.log('Reverb error $code: $message',
            name: 'ReverbTransport', error: error);
      },
    );
  }

  @override
  Future<void> connect() => _plugin.connect();

  @override
  Future<void> disconnect() => _plugin.disconnect();

  @override
  Future<void> subscribe({required String channelName}) =>
      _plugin.subscribe(channelName: channelName);

  @override
  Future<void> unsubscribe({required String channelName}) =>
      _plugin.unsubscribe(channelName: channelName);
}

/// Pure-Dart Pusher-protocol client for self-hosted Laravel Reverb.
///
/// Reverb speaks the Pusher Channels protocol over `ws(s)://host:port/app/<key>`
/// so the app works on Android/iOS/web/desktop without native plugins.
/// Handles connection_established handshake, resubscribe, ping/pong keepalive.
class ReverbSocketFacade implements PusherFacade {
  ReverbSocketFacade();

  final _events = StreamController<FacadeEvent>.broadcast();
  final _states = StreamController<String>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;
  String _apiKey = '';
  String _host = '127.0.0.1';
  int _port = 8086;
  bool _useTls = false;
  final _pendingChannels = <String>{};
  bool _disposed = false;

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
  }) async {
    _apiKey = apiKey;
    if (host != null && host.isNotEmpty) _host = host;
    _useTls = useTLS ?? false;
    _port = _useTls ? (wssPort ?? wsPort ?? 8086) : (wsPort ?? 8086);
  }

  Uri _uri() {
    final scheme = _useTls ? 'wss' : 'ws';
    final defaultPort = _useTls ? 443 : 80;
    final authority =
        _port == defaultPort ? _host : '$_host:$_port';
    return Uri.parse(
        '$scheme://$authority/app/$_apiKey?protocol=7&client=omidesk-flutter&version=1.0&flash=false');
  }

  @override
  Future<void> connect() async {
    if (_disposed) return;
    await _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _states.add('CONNECTING');
    try {
      final uri = _uri();
      developer.log('Reverb dial $uri', name: 'ReverbTransport');
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onData,
        onError: (Object e) {
          developer.log('Reverb socket error: $e', name: 'ReverbTransport');
          _states.add('DISCONNECTED');
        },
        onDone: () {
          developer.log('Reverb socket closed (onDone)',
              name: 'ReverbTransport');
          _states.add('DISCONNECTED');
          _pingTimer?.cancel();
        },
        cancelOnError: false,
      );
    } catch (error) {
      developer.log('Reverb dial failed: $error', name: 'ReverbTransport');
      _states.add('DISCONNECTED');
    }
  }

  void _onData(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = (jsonDecode('$raw') as Map)
          .map((k, v) => MapEntry('$k', v));
    } catch (_) {
      return;
    }
    final event = '${msg['event'] ?? ''}';
    if (event == 'pusher:connection_established') {
      developer.log('Reverb CONNECTED (${_pendingChannels.length} channels)',
          name: 'ReverbTransport');
      _states.add('CONNECTED');
      _pingTimer?.cancel();
      _pingTimer =
          Timer.periodic(const Duration(seconds: 25), (_) => _sendPong());
      for (final c in _pendingChannels.toList()) {
        _sendSubscribe(c);
      }
      return;
    }
    if (event == 'pusher:ping') {
      _sendPong();
      return;
    }
    if (event == 'pusher:pong') return;
    if (event == 'pusher:error') {
      developer.log('Reverb channel error: ${msg['data']}',
          name: 'ReverbTransport');
      return;
    }
    final channel = '${msg['channel'] ?? ''}';
    if (channel.isEmpty || event.isEmpty) return;
    var dataStr = '${msg['data'] ?? '{}'}';
    _events.add(
        FacadeEvent(channelName: channel, eventName: event, data: dataStr));
  }

  void _sendSubscribe(String channel) {
    try {
      _channel?.sink.add(jsonEncode({
        'event': 'pusher:subscribe',
        'data': {'channel': channel},
      }));
    } catch (_) {}
  }

  void _sendPong() {
    try {
      _channel?.sink.add(jsonEncode({'event': 'pusher:pong', 'data': {}}));
    } catch (_) {}
  }

  @override
  Future<void> subscribe({required String channelName}) async {
    _pendingChannels.add(channelName);
    _sendSubscribe(channelName);
  }

  @override
  Future<void> unsubscribe({required String channelName}) async {
    _pendingChannels.remove(channelName);
    try {
      _channel?.sink.add(jsonEncode({
        'event': 'pusher:unsubscribe',
        'data': {'channel': channelName},
      }));
    } catch (_) {}
  }

  @override
  Future<void> disconnect() async {
    _pingTimer?.cancel();
    try {
      await _sub?.cancel();
      await _channel?.sink.close();
    } catch (_) {}
    _states.add('DISCONNECTED');
  }

  Future<void> dispose() async {
    _disposed = true;
    _pingTimer?.cancel();
    await _sub?.cancel();
    await _events.close();
    await _states.close();
  }
}

/// Reverb-compatible transport over the Pusher Channels protocol.
///
/// Routing: Pusher-cloud hosts use the native plugin facade; every other
/// (self-hosted Reverb) host uses the pure-Dart socket facade so custom
/// host/ports/TLS work on all platforms. Public API is identical either way.
class ReverbTransport implements RealtimeTransport {
  ReverbTransport(this._config, [PusherFacade? facade])
      : _facade = facade ?? _facadeFor(_config);

  final RealtimeConfig _config;
  final PusherFacade _facade;

  static PusherFacade _facadeFor(RealtimeConfig config) {
    if (_isPusherCloud(config.host)) {
      return PusherChannelsFacade();
    }
    return ReverbSocketFacade();
  }

  static bool _isPusherCloud(String host) {
    final h = host.toLowerCase();
    return h.contains('pusher.com') || h.contains('pusherapp.com');
  }

  final _states = StreamController<RealtimeConnectionState>.broadcast();
  final _events = StreamController<TransportEnvelope>.broadcast();
  final _refCounts = <String, int>{};

  StreamSubscription<FacadeEvent>? _eventSub;
  StreamSubscription<String>? _stateSub;
  bool _initialized = false;
  bool _disposed = false;
  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;

  @override
  Stream<RealtimeConnectionState> get connectionState => _states.stream;

  @override
  RealtimeConnectionState get currentState => _state;

  @override
  Stream<TransportEnvelope> get events => _events.stream;

  void _setState(RealtimeConnectionState next) {
    if (_disposed || _state == next) return;
    _state = next;
    _states.add(next);
  }

  RealtimeConnectionState _mapPluginState(String raw) {
    final normalized = raw.toUpperCase();
    if (normalized.contains('CONNECTED')) {
      return RealtimeConnectionState.connected;
    }
    if (normalized.contains('CONNECTING') ||
        normalized.contains('RECONNECT')) {
      return RealtimeConnectionState.connecting;
    }
    return RealtimeConnectionState.disconnected;
  }

  @override
  Future<void> connect() async {
    if (_disposed || !_config.enabled) return;
    if (_state == RealtimeConnectionState.connected ||
        _state == RealtimeConnectionState.connecting) {
      return;
    }
    _setState(RealtimeConnectionState.connecting);
    try {
      if (!_initialized) {
        await _facade.init(
          apiKey: _config.appKey,
          cluster: _config.cluster,
          useTLS: _config.useTls,
          authEndpoint: _config.httpAuthEndpoint,
          host: _config.host,
          wsPort: _config.wsPort,
          wssPort: _config.wssPort,
        );
        _eventSub = _facade.onEvent.listen(_handlePluginEvent);
        _stateSub = _facade.onConnectionStateChange
            .listen((s) => _setState(_mapPluginState(s)));
        _initialized = true;
        for (final channel in _refCounts.keys.toList()) {
          try {
            await _facade.subscribe(channelName: channel);
          } catch (_) {}
        }
      }
      await _facade.connect();
    } catch (error) {
      developer.log('Reverb connect failed: $error', name: 'ReverbTransport');
      _setState(RealtimeConnectionState.degraded);
    }
  }

  void _handlePluginEvent(FacadeEvent event) {
    if (_disposed) return;
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(event.data);
      data = decoded is Map
          ? decoded.map((k, v) => MapEntry('$k', v))
          : <String, dynamic>{'value': decoded};
    } catch (_) {
      data = <String, dynamic>{'raw': event.data};
    }
    if (data.length == 1) {
      for (final nestKey in const ['data', 'message', 'payload']) {
        final nested = data[nestKey];
        if (nested is Map) {
          data = nested.map((k, v) => MapEntry('$k', v));
          break;
        }
      }
    }
    _events.add(TransportEnvelope(
      channel: event.channelName,
      eventName: event.eventName,
      data: data,
    ));
  }

  @override
  Future<void> subscribe(String channelName) async {
    if (_disposed) return;
    _refCounts.update(channelName, (v) => v + 1, ifAbsent: () => 1);
    if (_refCounts[channelName]! > 1) return;
    try {
      await _facade.subscribe(channelName: channelName);
    } catch (error) {
      developer.log('Subscribe $channelName failed: $error',
          name: 'ReverbTransport');
    }
  }

  @override
  Future<void> unsubscribe(String channelName) async {
    final count = (_refCounts[channelName] ?? 0) - 1;
    if (count > 0) {
      _refCounts[channelName] = count;
      return;
    }
    _refCounts.remove(channelName);
    try {
      await _facade.unsubscribe(channelName: channelName);
    } catch (_) {}
  }

  /// Force the socket back onto desired channels (used after reconnect).
  Future<void> resubscribeAll() async {
    for (final channel in _refCounts.keys) {
      try {
        await _facade.subscribe(channelName: channel);
      } catch (_) {}
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _facade.disconnect();
    } catch (_) {
    } finally {
      _setState(RealtimeConnectionState.disconnected);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _eventSub?.cancel();
    await _stateSub?.cancel();
    final facade = _facade;
    if (facade is ReverbSocketFacade) await facade.dispose();
    await _states.close();
    await _events.close();
  }
}
