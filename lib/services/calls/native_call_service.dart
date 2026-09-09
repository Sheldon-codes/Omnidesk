import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_models.dart';

enum NativeCallEventType { answer, decline, end, connected, disconnected }

class NativeCallUnavailable implements Exception {
  const NativeCallUnavailable(this.message);
  final String message;
}

class NativeCallEvent {
  const NativeCallEvent({
    required this.type,
    required this.callId,
    this.reason,
  });
  final NativeCallEventType type;
  final CallId callId;
  final String? reason;
}

/// Boundary for CallKit/Android Telecom and the native SIP implementation.
///
/// The Flutter UI never needs to know whether the platform uses PJSIP or a
/// provider SDK. Platform channels also allow a PushKit background callback to
/// report an offer before Flutter's widget tree exists.
abstract class NativeCallService {
  Stream<NativeCallEvent> get events;
  Future<void> presentIncoming(CallOffer offer);
  Future<void> dismiss(CallId callId);
  Future<void> registerMedia(CallMediaConfig config);
  Future<void> endMedia(CallId callId);
  Future<void> setMuted(bool enabled);
  Future<void> setSpeaker(bool enabled);
  Future<void> setHeld(bool enabled);
  Future<void> sendDtmf(String digit);
}

class MethodChannelNativeCallService implements NativeCallService {
  MethodChannelNativeCallService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('africa.omnidesk/calls') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final _events = StreamController<NativeCallEvent>.broadcast();

  @override
  Stream<NativeCallEvent> get events => _events.stream;

  @override
  Future<void> presentIncoming(CallOffer offer) => _invoke(
      'presentIncoming',
      {
        'callId': offer.callId,
        'offerId': offer.offerId,
        'callerName': offer.callerName,
        'callerNumber': offer.callerNumber,
        'expiresAt': offer.expiresAt.toIso8601String(),
      },
      allowMissingPlugin: true);

  @override
  Future<void> dismiss(CallId callId) =>
      _invoke('dismiss', {'callId': callId}, allowMissingPlugin: true);

  @override
  Future<void> registerMedia(CallMediaConfig config) =>
      _invoke('registerMedia', {
        'uri': config.sipUri,
        'username': config.sipUsername,
        'password': config.sipPassword,
        'registrar': config.registrar,
        'transport': config.sipTransport,
        'port': config.port,
      });

  @override
  Future<void> endMedia(CallId callId) =>
      _invoke('endMedia', {'callId': callId});

  @override
  Future<void> setMuted(bool enabled) =>
      _invoke('setMuted', {'enabled': enabled});

  @override
  Future<void> setSpeaker(bool enabled) =>
      _invoke('setSpeaker', {'enabled': enabled});

  @override
  Future<void> setHeld(bool enabled) =>
      _invoke('setHeld', {'enabled': enabled});

  @override
  Future<void> sendDtmf(String digit) => _invoke('sendDtmf', {'digit': digit});

  Future<void> _invoke(
    String method,
    Map<String, Object?> arguments, {
    bool allowMissingPlugin = false,
  }) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      if (!allowMissingPlugin) {
        throw const NativeCallUnavailable(
          'Native call media is not installed on this device.',
        );
      }
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final args = (call.arguments is Map
            ? call.arguments as Map
            : const <dynamic, dynamic>{})
        .map((key, value) => MapEntry('$key', value));
    final callId = args['callId']?.toString();
    if (callId == null || callId.isEmpty) return;
    final type = switch (call.method) {
      'answer' => NativeCallEventType.answer,
      'decline' => NativeCallEventType.decline,
      'end' => NativeCallEventType.end,
      'connected' => NativeCallEventType.connected,
      'disconnected' => NativeCallEventType.disconnected,
      _ => null,
    };
    if (type != null) {
      _events.add(NativeCallEvent(
        type: type,
        callId: callId,
        reason: args['reason']?.toString(),
      ));
    }
  }
}

final nativeCallServiceProvider = Provider<NativeCallService>(
  (ref) => MethodChannelNativeCallService(),
);
