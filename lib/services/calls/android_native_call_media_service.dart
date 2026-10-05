import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'call_media_service.dart';
import 'call_models.dart';

/// Native Android AT transport and PeerConnection media adapter.
/// The Android foreground service owns registration, audio, and the peer.
class AndroidNativeCallMediaService implements CallMediaService {
  AndroidNativeCallMediaService({
    MethodChannel? channel,
    EventChannel? eventChannel,
  })  : _channel = channel ?? const MethodChannel('africa.omnidesk/media'),
        _eventChannel =
            eventChannel ?? const EventChannel('africa.omnidesk/media_events') {
    _subscription =
        _eventChannel.receiveBroadcastStream().listen(_onNativeEvent);
  }

  final MethodChannel _channel;
  final EventChannel _eventChannel;
  final StreamController<CallMediaEvent> _events = StreamController.broadcast();
  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;

  @override
  Stream<CallMediaEvent> get events => _events.stream;

  @override
  Future<void> prepareForNewOutboundCall() => _invokeVoid('prepareForCall');

  /// Waits for the matching self-managed Telecom call and foreground-service
  /// audio lease. Incoming callers invoke this only after backend /accept.
  @override
  Future<void> prepareSystemAudio({
    required String systemCallId,
    required bool incoming,
  }) async {
    try {
      await _channel.invokeMethod<void>('prepareSystemAudio', {
        'systemCallId': systemCallId,
        'incoming': incoming,
      }).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const MediaUnavailable('Android call audio was not ready in time.');
    } on PlatformException catch (error) {
      throw MediaUnavailable(error.message ?? error.code);
    } on MissingPluginException {
      throw const MediaUnavailable('Native Android call audio is unavailable.');
    }
  }

  @override
  Future<void> ensureMicrophonePermission() async {
    final current = await Permission.microphone.status;
    if (current.isGranted) return;
    if (current.isPermanentlyDenied || current.isRestricted) {
      throw const MediaUnavailable(
        'Microphone access is blocked. Enable it for OmniDesk in Android settings to place calls.',
      );
    }
    final requested = await Permission.microphone.request();
    if (!requested.isGranted) {
      throw const MediaUnavailable(
        'Microphone permission is required to place a call.',
      );
    }
  }

  @override
  Future<void> abandonMediaPreparation() =>
      _invokeVoid('abandonCallPreparation');

  @override
  Future<String> initialize(CallMediaConfig config,
      {CallId? incomingCallId}) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw const MediaUnavailable(
          'Native AT media is only available on Android.');
    }
    if (!config.canUseWebRtc ||
        config.webrtcToken?.isNotEmpty != true ||
        config.webrtcGatewayUrl?.isNotEmpty != true) {
      throw const MediaUnavailable(
          'The call service returned incomplete WebRTC media settings.');
    }
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('initialize', {
        'token': config.webrtcToken,
        'gatewayUrl': config.webrtcGatewayUrl,
        if (incomingCallId != null) 'incomingCallId': incomingCallId,
      });
      final sessionId = result?['sessionId']?.toString();
      if (sessionId == null || sessionId.isEmpty) {
        throw const MediaUnavailable(
            'Native AT registration returned no session.');
      }
      return sessionId;
    } on PlatformException catch (error) {
      // Platform errors are deliberately generic and native code never includes
      // the capability token in its message or details.
      throw MediaUnavailable(error.message ?? error.code);
    } on MissingPluginException {
      throw const MediaUnavailable(
          'Native Android AT media is unavailable in this build.');
    }
  }

  @override
  Future<String> dial(
      {required String callSid,
      required String phoneNumber,
      String? sipTargetUri}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('dial', {
        'callSid': callSid,
        'phoneNumber': phoneNumber,
      });
      final sessionId = result?['sessionId']?.toString();
      if (sessionId == null || sessionId.isEmpty) {
        throw const MediaUnavailable(
            'Native AT call setup returned no session.');
      }
      return sessionId;
    } on PlatformException catch (error) {
      throw MediaUnavailable(error.message ?? error.code);
    } on MissingPluginException {
      throw const MediaUnavailable(
          'Native Android AT media is unavailable in this build.');
    }
  }

  @override
  Future<void> answerIncoming({required String callSid}) =>
      _invokeVoid('answer', {'callSid': callSid});
  @override
  Future<void> endMedia(String mediaSessionId) async {
    try {
      await _invokeVoid('end', {'sessionId': mediaSessionId});
    } finally {
      await _invokeVoid('abandonCallPreparation');
    }
  }

  @override
  Future<void> setMuted(bool enabled) =>
      _invokeVoid('setMuted', {'enabled': enabled});
  @override
  Future<void> setHeld(bool enabled) =>
      _invokeVoid('setHeld', {'enabled': enabled});
  @override
  Future<void> sendDtmf(String digit) =>
      _invokeVoid('sendDtmf', {'digit': digit});

  Future<void> _invokeVoid(String method,
      [Map<String, dynamic>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw MediaUnavailable(error.message ?? error.code);
    } on MissingPluginException {
      throw const MediaUnavailable(
          'Native Android AT media is unavailable in this build.');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    // This adapter belongs to a Flutter engine, while the registration belongs
    // to OmniDeskCallForegroundService. Engine/provider disposal must only
    // detach listeners so Activity/engine recreation cannot tear down a live
    // service-owned WebSocket registration.
    await _events.close();
  }

  /// Explicitly releases the service-owned registration. Normal Flutter
  /// engine teardown must use [dispose] instead and must not call this.
  Future<void> disposeRegistration() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('dispose');
    } on MissingPluginException {
      // The foreground-service owner may not be bound in this engine.
    } on PlatformException catch (error) {
      debugPrint(
          '[CallMedia] Android registration disposal failed: ${error.code}');
    }
  }

  void _onNativeEvent(dynamic raw) {
    if (_disposed || raw is! Map) return;
    final value = raw.map((key, item) => MapEntry('$key', item));
    if (value['type'] == 'snapshot') {
      final state = value['state']?.toString();
      if (state == 'registered') {
        _events.add(CallMediaEvent(
            type: CallMediaEventType.ready,
            mediaSessionId: value['sessionId']?.toString()));
      }
      return;
    }
    if (value['type'] == 'diagnostic') {
      final phase = value['phase']?.toString() ?? '';
      final result = value['result']?.toString() ?? '';
      _events.add(CallMediaEvent(
          type: CallMediaEventType.diagnostic,
          reason: '$phase:$result',
          mediaSessionId: value['sessionId']?.toString()));
      return;
    }
    if (value['type'] == 'media_event') {
      final type = switch (value['event']?.toString()) {
        'incoming' => CallMediaEventType.incoming,
        'ringing' => CallMediaEventType.ringing,
        'connected' => CallMediaEventType.connected,
        'held' => CallMediaEventType.held,
        'ended' => CallMediaEventType.ended,
        'error' => CallMediaEventType.error,
        'processTerminated' => CallMediaEventType.processTerminated,
        _ => null,
      };
      if (type != null) {
        _events.add(CallMediaEvent(
          type: type,
          callSid: value['callSid']?.toString(),
          mediaSessionId: value['sessionId']?.toString(),
          reason: value['reason']?.toString(),
        ));
      }
    }
  }
}
