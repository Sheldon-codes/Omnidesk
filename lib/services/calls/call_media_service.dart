import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_models.dart';
import 'deprecated_baresip_media_bridge.dart';

/// Media-engine events. Deliberately transport-agnostic: the session
/// controller drives the same state machine whether audio flows through
/// Baresip SIP or a hidden WebView AT client.
enum CallMediaEventType {
  /// Engine initialized and ready (SIP registered / WebRTC client connected).
  ready,
  ringing,
  incoming,
  connected,
  ended,
  held,
  error,

  /// Microphone capture verdict from the engine (granted/denied/unavailable
  /// in [CallMediaEvent.reason]). Informational only; never drives call
  /// state directly.
  micStatus,

  /// The media process/engine disappeared mid-call. Always fatal for the
  /// active call: the UI must never show ACTIVE against dead air.
  processTerminated,
}

class CallMediaEvent {
  const CallMediaEvent({
    required this.type,
    this.reason,
    this.mediaSessionId,
    this.callSid,
  });
  final CallMediaEventType type;
  final String? reason;
  final String? mediaSessionId;
  final String? callSid;
}

class MediaUnavailable implements Exception {
  const MediaUnavailable(this.message);
  final String message;
}

/// Transport-agnostic voice media boundary.
///
/// The hidden-WebView AT client implements this in production. The deprecated
/// Baresip compatibility adapter remains temporarily unselected until its
/// native build artifacts are removed in a dedicated cleanup change.
abstract class CallMediaService {
  Stream<CallMediaEvent> get events;

  /// Prepares the engine for a call (SIP REGISTER / WebRTC client connect).
  /// Completes with an opaque media session ID when the engine reports ready.
  /// [incomingCallId] tags adapter-side correlation for inbound offers.
  Future<String> initialize(CallMediaConfig config, {CallId? incomingCallId});

  /// Places an outbound call. [phoneNumber] is the E.164 customer number for
  /// WebRTC-style clients; [sipTargetUri] is the backend-provided SIP
  /// destination for SIP stacks. Each implementation uses what it needs.
  /// [callSid] tags the media session so engine events correlate with the
  /// controller's call surface.
  Future<String> dial({
    required String callSid,
    required String phoneNumber,
    String? sipTargetUri,
  });

  /// Answers a pending inbound media session, if the engine holds one.
  /// No-op for engines where the provider bridges media after /media-ready.
  Future<void> answerIncoming({required String callSid});

  Future<void> endMedia(String mediaSessionId);
  Future<void> setMuted(bool enabled);
  Future<void> setHeld(bool enabled);
  Future<void> sendDtmf(String digit);
  Future<void> dispose();
}

/// Deprecated SIP compatibility path. It is never selected in production.
@Deprecated('Baresip is deprecated and unreachable in production.')
class BaresipCallMediaService implements CallMediaService {
  BaresipCallMediaService({required DeprecatedBaresipMediaBridge bridge})
      : _bridge = bridge {
    _nativeSub = bridge.events.listen(_onNativeEvent);
  }

  final DeprecatedBaresipMediaBridge _bridge;
  final _events = StreamController<CallMediaEvent>.broadcast();
  StreamSubscription<DeprecatedBaresipMediaEvent>? _nativeSub;
  Completer<void>? _ready;
  String? _sessionId;
  CallMediaConfig? _config;
  bool _disposed = false;

  @override
  Stream<CallMediaEvent> get events => _events.stream;

  @override
  Future<String> initialize(CallMediaConfig config,
      {CallId? incomingCallId}) async {
    _config = config;
    _ready = Completer<void>();
    final sessionId = await _bridge.ensureRegistered(
      config,
      incomingCallId: incomingCallId,
    );
    _sessionId = sessionId;
    try {
      await _ready!.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException(
          'The SIP service did not confirm registration in time.',
        ),
      );
    } finally {
      _ready = null;
    }
    return sessionId;
  }

  @override
  Future<String> dial({
    required String callSid,
    required String phoneNumber,
    String? sipTargetUri,
  }) {
    final config = _config;
    final target = sipTargetUri ??
        (config == null
            ? null
            : _outboundTargetUri(phoneNumber, config.sipDomain));
    if (target == null || target.isEmpty) {
      throw const MediaUnavailable('A valid SIP call target is required.');
    }
    return _bridge
        .startOutgoingMedia(callSid: callSid, targetSipUri: target)
        .then((sessionId) {
      // The controller correlates by callSid; Baresip reports the same
      // session the registration produced, so keep the original ID.
      return _sessionId ?? sessionId;
    });
  }

  @override
  Future<void> answerIncoming({required String callSid}) async {
    // The provider bridges audio to the registered SIP contact after
    // /media-ready; no explicit SIP answer step exists on this path.
  }

  @override
  Future<void> endMedia(String mediaSessionId) =>
      _bridge.endMedia(mediaSessionId);

  @override
  Future<void> setMuted(bool enabled) => _bridge.setMuted(enabled);

  @override
  Future<void> setHeld(bool enabled) => _bridge.setHeld(enabled);

  @override
  Future<void> sendDtmf(String digit) => _bridge.sendDtmf(digit);

  void _completeReady() {
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  void _onNativeEvent(DeprecatedBaresipMediaEvent event) {
    if (_disposed) return;
    switch (event.type) {
      case DeprecatedBaresipMediaEventType.registered:
        _completeReady();
        _events.add(const CallMediaEvent(type: CallMediaEventType.ready));
      case DeprecatedBaresipMediaEventType.ringing:
        _events.add(const CallMediaEvent(type: CallMediaEventType.ringing));
      case DeprecatedBaresipMediaEventType.connected:
        // Connected implies a usable engine (media already flowing), so it
        // also satisfies a pending initialize — the inbound path never emits
        // a separate `registered` event.
        _completeReady();
        _events.add(const CallMediaEvent(type: CallMediaEventType.connected));
      case DeprecatedBaresipMediaEventType.held:
        _events.add(const CallMediaEvent(type: CallMediaEventType.held));
      case DeprecatedBaresipMediaEventType.disconnected:
        _events.add(const CallMediaEvent(type: CallMediaEventType.ended));
      case DeprecatedBaresipMediaEventType.failed:
        final ready = _ready;
        if (ready != null && !ready.isCompleted) {
          ready.completeError(MediaUnavailable(
            event.reason ?? 'SIP registration failed.',
          ));
        }
        _events.add(CallMediaEvent(
          type: CallMediaEventType.error,
          reason: event.reason,
        ));
    }
  }

  String _outboundTargetUri(String number, String domain) {
    final normalized = number.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty || domain.trim().isEmpty) {
      throw const MediaUnavailable(
        'A valid phone number and SIP domain are required.',
      );
    }
    return 'sip:$normalized@${domain.trim()}';
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _nativeSub?.cancel();
    await _events.close();
  }
}

final baresipCallMediaServiceProvider = Provider<BaresipCallMediaService>(
  (ref) {
    final service = BaresipCallMediaService(
      bridge: ref.read(deprecatedBaresipMediaBridgeProvider),
    );
    ref.onDispose(() => unawaited(service.dispose()));
    return service;
  },
);
