import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'call_media_service.dart';
import 'call_models.dart';

/// Dart adapter for the experimental native iOS AT media engine.
///
/// This adapter intentionally exposes the existing [CallMediaService] only.
/// CallKit/PushKit remain behind `africa.omnidesk/calls`; native WebRTC uses
/// the separate `africa.omnidesk/media` channel.
class IOSNativeCallMediaService implements CallMediaService {
  IOSNativeCallMediaService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('africa.omnidesk/media') {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  final MethodChannel _channel;
  final StreamController<CallMediaEvent> _events =
      StreamController<CallMediaEvent>.broadcast();
  bool _disposed = false;
  bool _supportsHold = false;
  bool _supportsDtmf = false;

  @override
  Stream<CallMediaEvent> get events => _events.stream;

  @override
  Future<void> prepareForNewOutboundCall() async {}

  @override
  Future<void> abandonMediaPreparation() async {}

  @override
  Future<String> initialize(
    CallMediaConfig config, {
    CallId? incomingCallId,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      throw const MediaUnavailable('Native AT media is only available on iOS.');
    }
    final token = config.webrtcToken;
    if (token == null || token.isEmpty) {
      throw const MediaUnavailable(
        'The call service did not provide a WebRTC capability token.',
      );
    }
    if (!config.canUseWebRtc) {
      throw const MediaUnavailable(
          'The WebRTC media configuration is unusable.');
    }
    _supportsHold = config.supportsHold;
    _supportsDtmf = config.supportsDtmf;
    final result = await _invokeMap('initialize', <String, Object?>{
      'token': token,
      'gatewayUrl': config.webrtcGatewayUrl,
      'clientName': config.webrtcClientName,
      'incomingCallId': incomingCallId,
    });
    final sessionId = result['sessionId']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw const MediaUnavailable(
          'Native AT registration returned no session.');
    }
    return sessionId;
  }

  @override
  Future<String> dial({
    required String callSid,
    required String phoneNumber,
    String? sipTargetUri,
  }) async {
    final result = await _invokeMap('dial', <String, Object?>{
      'callSid': callSid,
      'phoneNumber': phoneNumber,
    });
    return result['sessionId']?.toString() ?? callSid;
  }

  @override
  Future<void> answerIncoming({required String callSid}) =>
      _invoke('answer', <String, Object?>{'callSid': callSid});

  @override
  Future<void> endMedia(String mediaSessionId) =>
      _invoke('end', <String, Object?>{'sessionId': mediaSessionId});

  @override
  Future<void> setMuted(bool enabled) =>
      _invoke('setMuted', <String, Object?>{'enabled': enabled});

  @override
  Future<void> setHeld(bool enabled) async {
    if (!_supportsHold) {
      throw const MediaUnavailable(
          'Hold is not supported by the configured call provider.');
    }
    await _invoke('setHeld', <String, Object?>{'enabled': enabled});
  }

  @override
  Future<void> sendDtmf(String digit) async {
    if (!_supportsDtmf) {
      throw const MediaUnavailable(
          'DTMF is not supported by the configured call provider.');
    }
    if (!RegExp(r'^[0-9*#]$').hasMatch(digit)) {
      throw const MediaUnavailable('The DTMF digit is invalid.');
    }
    await _invoke('sendDtmf', <String, Object?>{'digit': digit});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _invoke('dispose');
    } finally {
      _supportsHold = false;
      _supportsDtmf = false;
      await _events.close();
    }
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw MediaUnavailable(error.message ?? error.code);
    } on MissingPluginException {
      throw const MediaUnavailable('Native AT media channel is unavailable.');
    }
  }

  Future<Map<String, dynamic>> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      return value ?? const <String, dynamic>{};
    } on PlatformException catch (error) {
      throw MediaUnavailable(error.message ?? error.code);
    } on MissingPluginException {
      throw const MediaUnavailable('Native AT media channel is unavailable.');
    }
  }

  Future<void> _handleNativeEvent(MethodCall call) async {
    if (_disposed) return;
    final args = call.arguments is Map
        ? (call.arguments as Map).map((key, value) => MapEntry('$key', value))
        : const <String, dynamic>{};
    final event = switch (call.method) {
      'ready' => CallMediaEventType.ready,
      'ringing' => CallMediaEventType.ringing,
      'incoming' => CallMediaEventType.incoming,
      'connected' => CallMediaEventType.connected,
      'ended' => CallMediaEventType.ended,
      'held' => CallMediaEventType.held,
      'micStatus' => CallMediaEventType.micStatus,
      'processTerminated' => CallMediaEventType.processTerminated,
      'error' => CallMediaEventType.error,
      'diagnostic' => CallMediaEventType.diagnostic,
      _ => null,
    };
    if (event == null) return;
    final diagnostic = call.method == 'diagnostic'
        ? <String?>[
            args['phase']?.toString(),
            args['negotiatedProtocol']?.toString(),
            args['result']?.toString(),
          ].whereType<String>().where((value) => value.isNotEmpty).join(':')
        : null;
    _events.add(CallMediaEvent(
      type: event,
      reason: diagnostic ?? args['reason']?.toString(),
      mediaSessionId: args['sessionId']?.toString(),
      callSid: args['callSid']?.toString(),
    ));
  }
}
