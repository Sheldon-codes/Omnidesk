import 'dart:async';

import 'call_models.dart';

/// Media-engine events. The controller owns the platform-neutral lifecycle;
/// iOS uses native WebRTC by default, with the WebView retained as fallback,
/// while Android continues to use the existing WebView client.
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

  /// Sanitized protocol/state trace from a media engine; informational only.
  diagnostic,

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
/// Call-engine boundary shared by native iOS WebRTC and the existing WebView
/// client. It remains transport-neutral so platform selection does not leak
/// into the call state machine.
abstract class CallMediaService {
  Stream<CallMediaEvent> get events;

  /// Performs a bounded, local-only admission check before a new outbound
  /// backend-call record is created. Stateful engines can release a verified
  /// idle stale reservation here. They must never tear down an unknown call.
  Future<void> prepareForNewOutboundCall() async {}

  /// Releases setup state when an attempt ends before [initialize] returns a
  /// media-session ID. This prevents a leaked engine reservation from
  /// blocking the next call.
  Future<void> abandonMediaPreparation() async {}

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
