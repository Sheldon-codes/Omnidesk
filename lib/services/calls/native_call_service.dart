import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_models.dart';

enum NativeCallEventType {
  offerAvailable,
  nativePushTokenChanged,
  answer,
  decline,
  end,
  incomingPresented,
  incomingOpened,
  outgoingDialing,
  active,
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
  }) : assert(
          type == NativeCallEventType.nativePushTokenChanged ||
              callId != null ||
              callSid != null ||
              mediaSessionId != null,
        );
  final NativeCallEventType type;
  final CallId? callId;
  final String? callSid;
  final String? mediaSessionId;
  final String? reason;
}

/// Records the moment Android Telecom accepted responsibility for presenting
/// an offer. This is telemetry, never a backend claim of the call.
class NativeIncomingPresentationReceipt {
  const NativeIncomingPresentationReceipt({
    required this.receivedAt,
    required this.nativePresentedAt,
  });

  final DateTime receivedAt;
  final DateTime nativePresentedAt;

  factory NativeIncomingPresentationReceipt.fromMap(Map<String, dynamic> map,
      {required DateTime fallbackReceivedAt}) {
    DateTime parse(Object? value, DateTime fallback) =>
        DateTime.tryParse(value?.toString() ?? '')?.toUtc() ?? fallback;
    return NativeIncomingPresentationReceipt(
      receivedAt: parse(map['receivedAt'], fallbackReceivedAt),
      nativePresentedAt:
          parse(map['nativePresentedAt'], DateTime.now().toUtc()),
    );
  }
}

/// Platform-neutral boundary for the operating system's call surface.
///
/// Android implements this with self-managed Telecom; iOS can implement the
/// same contract with CallKit. It deliberately contains no SIP, RTP, WebRTC,
/// or audio-device operation: those belong exclusively to [CallMediaService].
/// This lets the session controller keep one lifecycle regardless of which
/// platform owns the system UI or which engine supplies the media.
abstract class NativeCallService {
  Stream<NativeCallEvent> get events;
  Future<String?> readNativePushToken();
  Future<CallOffer?> takePendingOffer();
  Future<NativeCallEvent?> takePendingAction();
  Future<NativeIncomingPresentationReceipt> presentIncoming(CallOffer offer);
  Future<void> beginOutgoing(NativeCallIdentity identity);
  Future<void> markActive(NativeCallIdentity identity);
  Future<void> markFailed(NativeCallIdentity identity, {String? reason});
  Future<void> dismiss(NativeCallIdentity identity);
  Future<void> setSystemSpeaker(bool enabled);
}

/// Identity used only to correlate a system call with Flutter's backend and
/// media session. [callId] is canonical for inbound lifecycle APIs; [callSid]
/// identifies an outbound provider leg. Neither is interchangeable.
class NativeCallIdentity {
  const NativeCallIdentity({
    this.callId,
    this.callSid,
    required this.displayName,
    required this.phoneNumber,
  }) : assert(callId != null || callSid != null);

  final CallId? callId;
  final String? callSid;
  final String displayName;
  final String phoneNumber;

  Map<String, Object?> toMap() => {
        if (callId != null) 'callId': callId,
        if (callSid != null) 'callSid': callSid,
        'displayName': displayName,
        'phoneNumber': phoneNumber,
      };
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
  Future<String?> readNativePushToken() =>
      _readString('readNativePushToken', allowMissingPlugin: true);

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
  Future<NativeIncomingPresentationReceipt> presentIncoming(
      CallOffer offer) async {
    final value = await _readMapFromInvoke(
      'presentIncoming',
      {
        'callId': offer.callId,
        'offerId': offer.offerId,
        'callerName': offer.callerName,
        'callerNumber': offer.callerNumber,
        'receivedAt': offer.receivedAt.toIso8601String(),
        'expiresAt': offer.expiresAt.toIso8601String(),
      },
      allowMissingPlugin: true,
    );
    return NativeIncomingPresentationReceipt.fromMap(
      value ?? const {},
      fallbackReceivedAt: offer.receivedAt,
    );
  }

  @override
  Future<void> beginOutgoing(NativeCallIdentity identity) =>
      _invoke('beginOutgoingSystemCall', identity.toMap());

  @override
  Future<void> markActive(NativeCallIdentity identity) =>
      _invoke('markSystemCallActive', identity.toMap());

  @override
  Future<void> markFailed(NativeCallIdentity identity, {String? reason}) =>
      _invoke('markSystemCallFailed', {
        ...identity.toMap(),
        if (reason != null) 'reason': reason,
      });

  @override
  Future<void> dismiss(NativeCallIdentity identity) =>
      _invoke('dismissSystemCall', identity.toMap(), allowMissingPlugin: true);

  @override
  Future<void> setSystemSpeaker(bool enabled) =>
      _invoke('setSystemSpeaker', {'enabled': enabled});

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

  Future<Map<String, dynamic>?> _readMapFromInvoke(
    String method,
    Map<String, Object?> arguments, {
    required bool allowMissingPlugin,
  }) async {
    try {
      final value = await _channel.invokeMethod<dynamic>(method, arguments);
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
    if (call.method != 'nativePushTokenChanged' &&
        (callId == null || callId.isEmpty) &&
        (callSid == null || callSid.isEmpty) &&
        (mediaSessionId == null || mediaSessionId.isEmpty)) {
      return;
    }
    final type = switch (call.method) {
      'offerAvailable' => NativeCallEventType.offerAvailable,
      'nativePushTokenChanged' => NativeCallEventType.nativePushTokenChanged,
      'answer' => NativeCallEventType.answer,
      'decline' => NativeCallEventType.decline,
      'end' => NativeCallEventType.end,
      'incomingPresented' => NativeCallEventType.incomingPresented,
      'incomingOpened' => NativeCallEventType.incomingOpened,
      'outgoingDialing' => NativeCallEventType.outgoingDialing,
      'active' => NativeCallEventType.active,
      'disconnected' => NativeCallEventType.disconnected,
      'failed' => NativeCallEventType.failed,
      _ => null,
    };
    // A token update is intentionally identity-free; all other system events
    // require a call correlation key.
    if (type == NativeCallEventType.nativePushTokenChanged) {
      _events.add(const NativeCallEvent(
        type: NativeCallEventType.nativePushTokenChanged,
      ));
    } else if (type != null) {
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
