import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_models.dart';

class DeprecatedBaresipUnavailable implements Exception {
  const DeprecatedBaresipUnavailable(this.message);
  final String message;
}

/// Temporary compatibility boundary for the deprecated Baresip experiment.
///
/// It is intentionally not a [NativeCallService]: Baresip is a media engine,
/// not the owner of Android Telecom or future iOS CallKit state. No production
/// controller selects this bridge. It remains only so the separately tracked
/// cleanup pass can remove the native build artifacts without a risky mixed
/// refactor.
@Deprecated('Baresip is deprecated; use WebViewCallMediaService for AT media.')
abstract class DeprecatedBaresipMediaBridge {
  Stream<DeprecatedBaresipMediaEvent> get events;
  Future<String> ensureRegistered(
    CallMediaConfig config, {
    CallId? incomingCallId,
  });
  Future<String> startOutgoingMedia({
    required String callSid,
    required String targetSipUri,
  });
  Future<void> endMedia(String mediaSessionId);
  Future<void> setMuted(bool enabled);
  Future<void> setHeld(bool enabled);
  Future<void> sendDtmf(String digit);
}

enum DeprecatedBaresipMediaEventType {
  registered,
  ringing,
  connected,
  held,
  disconnected,
  failed,
}

class DeprecatedBaresipMediaEvent {
  const DeprecatedBaresipMediaEvent({
    required this.type,
    this.callId,
    this.callSid,
    this.mediaSessionId,
    this.reason,
  });

  final DeprecatedBaresipMediaEventType type;
  final CallId? callId;
  final String? callSid;
  final String? mediaSessionId;
  final String? reason;
}

@Deprecated('Baresip is deprecated; use WebViewCallMediaService for AT media.')
class MethodChannelDeprecatedBaresipMediaBridge
    implements DeprecatedBaresipMediaBridge {
  MethodChannelDeprecatedBaresipMediaBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('africa.omnidesk/calls') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final _events = StreamController<DeprecatedBaresipMediaEvent>.broadcast();

  @override
  Stream<DeprecatedBaresipMediaEvent> get events => _events.stream;

  @override
  Future<String> ensureRegistered(
    CallMediaConfig config, {
    CallId? incomingCallId,
  }) =>
      _invokeForString('ensureRegistered', {
        'uri': config.sipUri,
        'username': config.sipUsername,
        'authUsername': config.sipAuthUsername,
        'password': config.sipPassword,
        'registrar': config.registrar,
        'domain': config.sipDomain,
        'proxy': config.sipProxy,
        'transport': config.sipTransport,
        'port': config.port,
        if (incomingCallId != null) 'callId': incomingCallId,
      });

  @override
  Future<String> startOutgoingMedia({
    required String callSid,
    required String targetSipUri,
  }) =>
      _invokeForString('startOutgoingMedia', {
        'callSid': callSid,
        'targetSipUri': targetSipUri,
      });

  @override
  Future<void> endMedia(String mediaSessionId) =>
      _invoke('endMedia', {'mediaSessionId': mediaSessionId});

  @override
  Future<void> setMuted(bool enabled) =>
      _invoke('setMuted', {'enabled': enabled});

  @override
  Future<void> setHeld(bool enabled) =>
      _invoke('setHeld', {'enabled': enabled});

  @override
  Future<void> sendDtmf(String digit) => _invoke('sendDtmf', {'digit': digit});

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      throw const DeprecatedBaresipUnavailable(
        'The deprecated Baresip bridge is not installed on this device.',
      );
    }
  }

  Future<String> _invokeForString(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final value = await _channel.invokeMethod<String>(method, arguments);
      if (value == null || value.isEmpty) {
        throw const DeprecatedBaresipUnavailable(
          'The deprecated Baresip bridge did not return a media session.',
        );
      }
      return value;
    } on MissingPluginException {
      throw const DeprecatedBaresipUnavailable(
        'The deprecated Baresip bridge is not installed on this device.',
      );
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final args = (call.arguments is Map
            ? call.arguments as Map
            : const <dynamic, dynamic>{})
        .map((key, value) => MapEntry('$key', value));
    final type = switch (call.method) {
      'registered' => DeprecatedBaresipMediaEventType.registered,
      'ringing' => DeprecatedBaresipMediaEventType.ringing,
      'connected' => DeprecatedBaresipMediaEventType.connected,
      'held' => DeprecatedBaresipMediaEventType.held,
      'disconnected' => DeprecatedBaresipMediaEventType.disconnected,
      'failed' => DeprecatedBaresipMediaEventType.failed,
      _ => null,
    };
    if (type == null) return;
    _events.add(DeprecatedBaresipMediaEvent(
      type: type,
      callId: args['callId']?.toString(),
      callSid: args['callSid']?.toString(),
      mediaSessionId: args['mediaSessionId']?.toString(),
      reason: args['reason']?.toString(),
    ));
  }
}

final deprecatedBaresipMediaBridgeProvider =
    Provider<DeprecatedBaresipMediaBridge>(
  (ref) => MethodChannelDeprecatedBaresipMediaBridge(),
);
