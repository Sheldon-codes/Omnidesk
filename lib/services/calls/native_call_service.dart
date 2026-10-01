import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
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

/// Durable context recorded when the user opens a live native incoming-call
/// notification. It is intentionally separate from [CallOffer]: opening the
/// notification does not answer, consume, or otherwise mutate the offer.
class NativeIncomingCallLaunch {
  const NativeIncomingCallLaunch({
    required this.callId,
    required this.offerId,
    required this.openedAt,
  });

  final CallId callId;
  final String offerId;
  final DateTime openedAt;

  factory NativeIncomingCallLaunch.fromMap(Map<String, dynamic> map) {
    return NativeIncomingCallLaunch(
      callId: map['callId']?.toString() ?? '',
      offerId: map['offerId']?.toString() ?? '',
      openedAt: DateTime.tryParse(map['openedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(map['openedAt']?.toString() ?? '') ?? 0,
          ),
    );
  }

  bool get isValid => callId.isNotEmpty && offerId.isNotEmpty;
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

  /// Identity-free AVAudioSession snapshots for the iOS diagnostic surface.
  /// Android implementations deliberately use the default empty stream.
  Stream<NativeAudioSessionDiagnostic> get audioSessionDiagnostics =>
      const Stream<NativeAudioSessionDiagnostic>.empty();
  Future<String?> readNativePushToken();
  Future<CallOffer?> peekPendingOffer();
  Future<CallOffer?> takePendingOffer();
  Future<NativeIncomingCallLaunch?> peekInitialIncomingLaunch();
  Future<NativeIncomingCallLaunch?> takeInitialIncomingLaunch();
  Future<NativeCallEvent?> takePendingAction();
  Future<NativeIncomingPresentationReceipt> presentIncoming(CallOffer offer);
  Future<void> beginOutgoing(NativeCallIdentity identity);

  /// Waits for the system-call framework to activate its audio session before
  /// WebRTC requests microphone capture. Android has no equivalent CallKit
  /// activation edge in this implementation, so the default is a no-op.
  Future<void> waitForSystemAudioReady() async {}

  /// Ends the operating system's incoming-ringing state without claiming the
  /// backend call or marking media active.  This is deliberately distinct
  /// from [markActive]: a user can answer in Flutter while WebRTC is still
  /// preparing, and the device ringtone must stop immediately.
  Future<void> markAnswering(NativeCallIdentity identity);
  Future<void> markActive(NativeCallIdentity identity);
  Future<void> markFailed(NativeCallIdentity identity, {String? reason});
  Future<void> dismiss(NativeCallIdentity identity);
  Future<void> setSystemSpeaker(bool enabled);
}

class NativeAudioSessionDiagnostic {
  const NativeAudioSessionDiagnostic({
    required this.phase,
    required this.category,
    required this.mode,
    required this.route,
    required this.inputAvailable,
    required this.speakerRequested,
  });

  factory NativeAudioSessionDiagnostic.fromMap(Map<String, dynamic> map) =>
      NativeAudioSessionDiagnostic(
        phase: map['phase']?.toString() ?? 'unknown',
        category: map['category']?.toString() ?? 'unknown',
        mode: map['mode']?.toString() ?? 'unknown',
        route: map['route']?.toString() ?? 'unknown',
        inputAvailable: map['inputAvailable'] == true,
        speakerRequested: map['speakerRequested'] == true,
      );

  final String phase;
  final String category;
  final String mode;
  final String route;
  final bool inputAvailable;
  final bool speakerRequested;

  Map<String, Object?> toSafeMap() => {
        'phase': phase,
        'category': category,
        'mode': mode,
        'route': route,
        'inputAvailable': inputAvailable,
        'speakerRequested': speakerRequested,
      };
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

  bool _systemAudioActive = defaultTargetPlatform != TargetPlatform.iOS;
  Completer<void>? _systemAudioReady;

  final MethodChannel _channel;
  final _events = StreamController<NativeCallEvent>.broadcast();
  final _audioSessionDiagnostics =
      StreamController<NativeAudioSessionDiagnostic>.broadcast();

  @override
  Stream<NativeCallEvent> get events => _events.stream;

  @override
  Stream<NativeAudioSessionDiagnostic> get audioSessionDiagnostics =>
      _audioSessionDiagnostics.stream;

  @override
  Future<String?> readNativePushToken() =>
      _readString('readNativePushToken', allowMissingPlugin: true);

  @override
  Future<CallOffer?> peekPendingOffer() => _readOffer('peekPendingOffer');

  @override
  Future<CallOffer?> takePendingOffer() async {
    return _readOffer('takePendingOffer');
  }

  Future<CallOffer?> _readOffer(String method) async {
    final value = await _readMap(method, allowMissingPlugin: true);
    if (value == null) return null;
    try {
      final offer = CallOffer.fromJson(value);
      return offer.callId.isEmpty || offer.offerId.isEmpty ? null : offer;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<NativeIncomingCallLaunch?> takeInitialIncomingLaunch() async {
    return _readIncomingLaunch('takeInitialIncomingLaunch');
  }

  @override
  Future<NativeIncomingCallLaunch?> peekInitialIncomingLaunch() async {
    return _readIncomingLaunch('peekInitialIncomingLaunch');
  }

  Future<NativeIncomingCallLaunch?> _readIncomingLaunch(String method) async {
    final value = await _readMap(
      method,
      allowMissingPlugin: true,
    );
    if (value == null) return null;
    final launch = NativeIncomingCallLaunch.fromMap(value);
    return launch.isValid ? launch : null;
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
  Future<void> waitForSystemAudioReady() async {
    if (defaultTargetPlatform != TargetPlatform.iOS || _systemAudioActive) {
      return;
    }
    // A cold Flutter engine can miss the asynchronous activation callback.
    // Query native state once before waiting for the next event.
    try {
      final active = await _channel.invokeMethod<bool>('isSystemAudioActive');
      if (active == true) {
        _markSystemAudioActive();
        return;
      }
    } on MissingPluginException {
      // Old/native-test hosts retain the previous behavior rather than
      // failing every call solely because they lack the diagnostic method.
      return;
    }
    final ready = _systemAudioReady ??= Completer<void>();
    try {
      await ready.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const NativeCallUnavailable(
        'Call audio did not become active in time. Please try again.',
      );
    }
  }

  void _markSystemAudioActive() {
    _systemAudioActive = true;
    final ready = _systemAudioReady;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  void _markSystemAudioInactive() {
    _systemAudioActive = false;
    _systemAudioReady = null;
  }

  @override
  Future<void> markAnswering(NativeCallIdentity identity) =>
      _invoke('markSystemCallAnswering', identity.toMap(),
          allowMissingPlugin: true);

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
    if (call.method == 'audioSessionDiagnostic') {
      // Native iOS CallKit / AVAudioSession diagnostics are intentionally
      // identity-free and allowlisted on the Swift side. They explain whether
      // WebKit's `MediaStreamTrack.muted` means missing capture frames or an
      // inactive/wrongly-routed system audio session.
      developer.log(
        'iOS audio phase=${args['phase'] ?? 'unknown'} '
        'category=${args['category'] ?? 'unknown'} '
        'mode=${args['mode'] ?? 'unknown'} '
        'route=${args['route'] ?? 'unknown'} '
        'inputAvailable=${args['inputAvailable'] ?? 'unknown'} '
        'speakerRequested=${args['speakerRequested'] ?? 'unknown'}',
        name: 'NativeCallAudio',
      );
      _audioSessionDiagnostics.add(NativeAudioSessionDiagnostic.fromMap(args));
      return;
    }
    if (call.method == 'systemAudioActive') {
      _markSystemAudioActive();
      developer.log('iOS CallKit audio session is active.',
          name: 'NativeCallAudio');
      return;
    }
    if (call.method == 'systemAudioInactive') {
      _markSystemAudioInactive();
      developer.log('iOS CallKit audio session is inactive.',
          name: 'NativeCallAudio');
      return;
    }
    final callId = args['callId']?.toString();
    final callSid = args['callSid']?.toString();
    final mediaSessionId = args['mediaSessionId']?.toString();
    if (call.method != 'nativePushTokenChanged' &&
        call.method != 'voipPushToken' &&
        (callId == null || callId.isEmpty) &&
        (callSid == null || callSid.isEmpty) &&
        (mediaSessionId == null || mediaSessionId.isEmpty)) {
      return;
    }
    final type = switch (call.method) {
      'offerAvailable' => NativeCallEventType.offerAvailable,
      'nativePushTokenChanged' => NativeCallEventType.nativePushTokenChanged,
      // iOS PushKit posts VoIP token rotations on this method (see
      // AppDelegate `didUpdate credentials`). It carries no call identity;
      // treat it as a push-token change so device registration re-reads the
      // fresh token from UserDefaults and re-registers both tokens.
      'voipPushToken' => NativeCallEventType.nativePushTokenChanged,
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
