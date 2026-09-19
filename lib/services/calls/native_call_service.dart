import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_models.dart';

enum NativeCallEventType {
  answer,
  decline,
  end,
  registered,
  ringing,
  connected,
  held,
  disconnected,
  failed,
}

class NativeCallUnavailable implements Exception {
  const NativeCallUnavailable(this.message);
  final String message;
}

class NativeCallEvent {
  const NativeCallEvent({
    required this.type,
    this.callId,
    this.callSid,
    this.mediaSessionId,
    this.reason,
  }) : assert(callId != null || callSid != null || mediaSessionId != null);
  final NativeCallEventType type;
  final CallId? callId;
  final String? callSid;
  final String? mediaSessionId;
  final String? reason;
}

/// Boundary for CallKit/Android Telecom and the native SIP implementation.
///
/// The Flutter UI never needs to know whether the platform uses PJSIP or a
/// provider SDK. Platform channels also allow a PushKit background callback to
/// report an offer before Flutter's widget tree exists.
abstract class NativeCallService {
  Stream<NativeCallEvent> get events;
  Future<String?> readVoipPushToken();
  Future<CallOffer?> takePendingOffer();
  Future<NativeCallEvent?> takePendingAction();
  Future<void> presentIncoming(CallOffer offer);
  Future<void> dismiss(CallId callId);

  /// Registers the one foreground workspace SIP account. The returned ID is
  /// opaque and only correlates native events with the Dart call session.
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
  Future<String?> readVoipPushToken() =>
      _readString('readVoipPushToken', allowMissingPlugin: true);

  @override
  Future<CallOffer?> takePendingOffer() async {
    final value = await _readMap('takePendingOffer', allowMissingPlugin: true);
    if (value == null) return null;
    try {
      final offer = CallOffer.fromJson(value);
      return offer.callId.isEmpty || offer.offerId.isEmpty ? null : offer;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<NativeCallEvent?> takePendingAction() async {
    final value = await _readMap('takePendingAction', allowMissingPlugin: true);
    if (value == null) return null;
    final callId = value['callId']?.toString();
    final action = value['action']?.toString();
    if (callId == null || callId.isEmpty) return null;
    final type = switch (action) {
      'answer' => NativeCallEventType.answer,
      'decline' => NativeCallEventType.decline,
      'end' => NativeCallEventType.end,
      _ => null,
    };
    return type == null
        ? null
        : NativeCallEvent(
            type: type, callId: callId, reason: value['reason']?.toString());
  }

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

  Future<String> _invokeForString(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final value = await _channel.invokeMethod<String>(method, arguments);
      if (value == null || value.isEmpty) {
        throw const NativeCallUnavailable(
          'The native call service did not return a media session.',
        );
      }
      return value;
    } on MissingPluginException {
      throw const NativeCallUnavailable(
        'Native call media is not installed on this device.',
      );
    }
  }

  Future<String?> _readString(
    String method, {
    required bool allowMissingPlugin,
  }) async {
    try {
      return await _channel.invokeMethod<String>(method);
    } on MissingPluginException {
      if (allowMissingPlugin) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _readMap(
    String method, {
    required bool allowMissingPlugin,
  }) async {
    try {
      final value = await _channel.invokeMethod<dynamic>(method);
      if (value is! Map) return null;
      return value.map((key, nested) => MapEntry('$key', nested));
    } on MissingPluginException {
      if (allowMissingPlugin) return null;
      rethrow;
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final args = (call.arguments is Map
            ? call.arguments as Map
            : const <dynamic, dynamic>{})
        .map((key, value) => MapEntry('$key', value));
    final callId = args['callId']?.toString();
    final callSid = args['callSid']?.toString();
    final mediaSessionId = args['mediaSessionId']?.toString();
    if ((callId == null || callId.isEmpty) &&
        (callSid == null || callSid.isEmpty) &&
        (mediaSessionId == null || mediaSessionId.isEmpty)) {
      return;
    }
    final type = switch (call.method) {
      'answer' => NativeCallEventType.answer,
      'decline' => NativeCallEventType.decline,
      'end' => NativeCallEventType.end,
      'registered' => NativeCallEventType.registered,
      'ringing' => NativeCallEventType.ringing,
      'connected' => NativeCallEventType.connected,
      'held' => NativeCallEventType.held,
      'disconnected' => NativeCallEventType.disconnected,
      'failed' => NativeCallEventType.failed,
      _ => null,
    };
    if (type != null) {
      _events.add(NativeCallEvent(
        type: type,
        callId: callId,
        callSid: callSid,
        mediaSessionId: mediaSessionId,
        reason: args['reason']?.toString(),
      ));
    }
  }
}

final nativeCallServiceProvider = Provider<NativeCallService>(
  (ref) => MethodChannelNativeCallService(),
);
