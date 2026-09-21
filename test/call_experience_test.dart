import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/components/call_experience/call_experience_host.dart';
import 'package:omnidesk_agent/components/call_experience/call_session_controller.dart';
import 'package:omnidesk_agent/services/calls/call_api.dart';
import 'package:omnidesk_agent/services/calls/call_media_provider.dart';
import 'package:omnidesk_agent/services/calls/call_media_service.dart';
import 'package:omnidesk_agent/services/calls/call_models.dart';
import 'package:omnidesk_agent/services/calls/device_installation_service.dart';
import 'package:omnidesk_agent/services/calls/native_call_service.dart';

void main() {
  test('call controller supports live incoming, active, and collapsed states',
      () async {
    final container = _liveContainer();
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(container.read(callSessionControllerProvider).hasCall, isFalse);
    expect(await controller.handleIncomingOffer(_incomingOffer()), isTrue);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.incomingRinging);

    await controller.answer();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.active);
    await controller.toggleMute();
    await controller.toggleSpeaker();
    await controller.toggleHold();
    expect(container.read(callSessionControllerProvider).muted, isTrue);
    expect(
        container.read(callSessionControllerProvider).speakerEnabled, isTrue);
    expect(container.read(callSessionControllerProvider).onHold, isTrue);

    controller.openKeypad();
    await controller.appendDtmfDigit('2');
    await controller.appendDtmfDigit('#');
    expect(container.read(callSessionControllerProvider).dtmfDigits, '2#');
    controller.minimize();
    expect(container.read(callSessionControllerProvider).presentation,
        CallPresentation.collapsed);
    expect(
        container.read(callSessionControllerProvider).keypadVisible, isFalse);
    controller.restore();
    await controller.end();
    expect(container.read(callSessionControllerProvider).hasCall, isFalse);
  });

  test('outgoing call uses the server originate contract without a demo timer',
      () async {
    final api = _FakeCallApi();
    final container = _liveContainer(api: api);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(
      controller.startOutgoing(const CallParty(
        displayName: 'Caller',
        phoneNumber: '+254700000001',
      )),
      isTrue,
    );
    expect(container.read(callSessionControllerProvider).phase,
        CallPhase.outgoingPreparing);
    await Future<void>.delayed(Duration.zero);
    expect(api.outboundInitiated, isTrue);
    // The WebRTC bridge reports ringing; no fabricated active timer starts.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.outgoingRinging);
    expect(container.read(callSessionControllerProvider).startedAt, isNull);
  });

  test('live incoming offer follows accept, media-ready, then native connect',
      () async {
    final api = _FakeCallApi();
    final native = _FakeNativeCallService();
    final container = _liveContainer(api: api, native: native);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);
    final offer = _incomingOffer();

    expect(await controller.handleIncomingOffer(offer), isTrue);
    expect(container.read(callSessionControllerProvider).callId, 'call-1');
    await controller.answer();
    await Future<void>.delayed(Duration.zero);

    expect(api.deliveryAcknowledged, isTrue);
    expect(api.accepted, isTrue);
    expect(api.mediaReadySent, isTrue);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.active);
  });

  testWidgets('native incoming ringing does not duplicate Flutter UI',
      (tester) async {
    final container = _liveContainer();
    addTearDown(container.dispose);
    await container
        .read(callSessionControllerProvider.notifier)
        .handleIncomingOffer(_incomingOffer());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: CallExperienceHost(
          child: Scaffold(body: Center(child: Text('App content'))),
        ),
      ),
    ));
    await tester.pump();

    // Android Telecom owns incoming ringing. Flutter only takes over after
    // the native Answer action begins the WebRTC connection lifecycle.
    expect(find.text('Incoming call'), findsNothing);
    expect(find.bySemanticsLabel('Answer'), findsNothing);
    expect(find.text('App content'), findsOneWidget);

    unawaited(container.read(callSessionControllerProvider.notifier).answer());
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('00:00'), findsOneWidget);
    expect(find.bySemanticsLabel('Minimize call'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Minimize call'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('End call'), findsOneWidget);
    expect(find.bySemanticsLabel('Loudspeaker'), findsOneWidget);
    expect(find.text('App content'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Loudspeaker'));
    await tester.pump();
    expect(
        container.read(callSessionControllerProvider).speakerEnabled, isTrue);
    expect(find.bySemanticsLabel('Turn off loudspeaker'), findsOneWidget);

    await tester.tap(find.text('Aloise Obaga Kaizen School'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Minimize call'), findsOneWidget);
    await container.read(callSessionControllerProvider.notifier).end();
  });

  testWidgets('call controls work when the host is mounted in app builder',
      (tester) async {
    final container = _liveContainer();
    addTearDown(container.dispose);
    await container
        .read(callSessionControllerProvider.notifier)
        .handleIncomingOffer(_incomingOffer());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) =>
            CallExperienceHost(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('Router content')),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Answer'), findsNothing);
    unawaited(container.read(callSessionControllerProvider.notifier).answer());
    await tester.pump(const Duration(milliseconds: 10));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Minimize call'), findsOneWidget);
    await container.read(callSessionControllerProvider.notifier).end();
  });
}

ProviderContainer _liveContainer({
  _FakeCallApi? api,
  _FakeNativeCallService? native,
}) {
  return ProviderContainer(overrides: [
    callApiProvider.overrideWithValue(api ?? _FakeCallApi()),
    nativeCallServiceProvider
        .overrideWithValue(native ?? _FakeNativeCallService()),
    callMediaServiceProvider.overrideWithValue(_FakeMedia()),
    callInstallationIdProvider.overrideWithValue(() async => 'installation-1'),
  ]);
}

CallOffer _incomingOffer() {
  final now = DateTime.now().toUtc();
  return CallOffer(
    callId: 'call-1',
    offerId: 'offer-1',
    provider: 'africas_talking',
    callerNumber: '+254700000001',
    callerName: 'Aloise Obaga Kaizen School',
    workspaceId: 'workspace-1',
    receivedAt: now,
    expiresAt: now.add(const Duration(seconds: 30)),
  );
}

class _FakeCallApi implements CallApi {
  bool deliveryAcknowledged = false;
  bool accepted = false;
  bool mediaReadySent = false;
  bool outboundInitiated = false;

  @override
  Future<void> acknowledgeDelivery({
    required String callId,
    required String offerId,
    required String installationId,
    required DateTime receivedAt,
    required DateTime nativePresentedAt,
  }) async =>
      deliveryAcknowledged = true;

  @override
  Future<ActiveCallSnapshot> accept({
    required String callId,
    required String offerId,
    required String installationId,
  }) async {
    accepted = true;
    return ActiveCallSnapshot(
      callId: callId,
      direction: CallDirection.inbound,
      phase: CallPhase.connecting,
      remoteNumber: '+254700000001',
      createdAt: DateTime.now().toUtc(),
      answeredAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> decline({
    required String callId,
    required String offerId,
    required String installationId,
    required String reason,
  }) async {}

  @override
  Future<void> end({required String callId, required String reason}) async {}

  @override
  Future<void> completeOutbound({
    required String callSid,
    required Duration connectedDuration,
  }) async {}

  @override
  Future<OutboundCallResult> initiateOutbound({
    required String toNumber,
    String? ticketId,
  }) async {
    outboundInitiated = true;
    return const OutboundCallResult(callSid: 'AT-call-sess-initiated');
  }

  @override
  Future<ActiveCallSnapshot?> getActiveCall() async => null;

  @override
  Future<CallLogPage> getCallLogs({int page = 1, int perPage = 20}) async =>
      CallLogPage(records: const [], page: page, hasMore: false);

  @override
  Future<CallMediaConfig> getMediaConfig() async => const CallMediaConfig(
        provider: 'africas_talking',
        transport: 'webrtc',
        endpointType: 'mobile',
        sipUri: '',
        sipUsername: '',
        sipAuthUsername: '',
        registrar: '',
        sipDomain: '',
        sipProxy: '',
        sipTransport: '',
        port: 0,
        supportsHold: true,
        supportsDtmf: true,
        supportsNativeIncoming: true,
        webrtcToken: 'ATCAPtkn_test',
      );

  @override
  Future<void> mediaReady({
    required String callId,
    required String offerId,
    required String installationId,
  }) async =>
      mediaReadySent = true;

  @override
  Future<void> registerDevice(DeviceRegistration registration) async {}

  @override
  Future<void> unregisterDevice(String installationId) async {}
}

class _FakeNativeCallService implements NativeCallService {
  final _events = StreamController<NativeCallEvent>.broadcast();

  @override
  Stream<NativeCallEvent> get events => _events.stream;

  @override
  Future<String?> readNativePushToken() async => null;

  @override
  Future<CallOffer?> takePendingOffer() async => null;

  @override
  Future<NativeCallEvent?> takePendingAction() async => null;

  @override
  Future<void> dismiss(NativeCallIdentity identity) async {}

  @override
  Future<NativeIncomingPresentationReceipt> presentIncoming(
          CallOffer offer) async =>
      NativeIncomingPresentationReceipt(
        receivedAt: offer.receivedAt,
        nativePresentedAt: DateTime.now().toUtc(),
      );

  @override
  Future<void> beginOutgoing(NativeCallIdentity identity) async {}

  @override
  Future<void> markActive(NativeCallIdentity identity) async {}

  @override
  Future<void> markFailed(NativeCallIdentity identity,
      {String? reason}) async {}

  @override
  Future<void> setSystemSpeaker(bool enabled) async {}
}

class _FakeMedia implements CallMediaService {
  final _events = StreamController<CallMediaEvent>.broadcast();

  @override
  Stream<CallMediaEvent> get events => _events.stream;

  @override
  Future<String> initialize(CallMediaConfig config,
      {CallId? incomingCallId}) async {
    Timer.run(() =>
        _events.add(const CallMediaEvent(type: CallMediaEventType.ready)));
    if (incomingCallId != null) {
      Future<void>.delayed(const Duration(milliseconds: 5), () {
        _events.add(const CallMediaEvent(type: CallMediaEventType.incoming));
      });
    }
    return 'webview-test-1';
  }

  @override
  Future<String> dial(
      {required String callSid,
      required String phoneNumber,
      String? sipTargetUri}) async {
    Timer.run(() => _events.add(
        CallMediaEvent(type: CallMediaEventType.ringing, callSid: callSid)));
    return 'webview-test-1';
  }

  @override
  Future<void> answerIncoming({required String callSid}) async {
    _events.add(
        CallMediaEvent(type: CallMediaEventType.connected, callSid: callSid));
  }

  @override
  Future<void> endMedia(String mediaSessionId) async {}
  @override
  Future<void> setHeld(bool enabled) async {}
  @override
  Future<void> setMuted(bool enabled) async {}
  @override
  Future<void> sendDtmf(String digit) async {}
  @override
  Future<void> dispose() async => _events.close();
}
