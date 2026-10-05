import 'dart:async';

import 'package:flutter/foundation.dart';
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

  test('FCM cancellation tears down ringing without backend end', () async {
    final api = _FakeCallApi();
    final container = _liveContainer(api: api);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(await controller.handleIncomingOffer(_incomingOffer()), isTrue);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.incomingRinging);

    // Backend cancellation over FCM (APNs background push on iOS).
    controller.handleRemoteCancellation(
      callId: _incomingOffer().callId,
      reason: 'caller_hangup',
    );
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.terminalNotice);
    expect(api.endCalls, 0);

    // A cancellation for another call must not touch this surface.
    final container2 = _liveContainer();
    addTearDown(container2.dispose);
    final controller2 = container2.read(callSessionControllerProvider.notifier);
    expect(await controller2.handleIncomingOffer(_incomingOffer()), isTrue);
    controller2.handleRemoteCancellation(
      callId: 'some-other-call',
      reason: 'caller_hangup',
    );
    expect(container2.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.incomingRinging);
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

  test('outgoing admission failure does not create an orphan backend call',
      () async {
    final api = _FakeCallApi();
    final media = _FakeMedia()
      ..outboundAdmissionError = const MediaUnavailable(
        'The previous call is still closing. Please try again in a moment.',
      );
    final container = _liveContainer(api: api, media: media);
    addTearDown(container.dispose);

    expect(
      container.read(callSessionControllerProvider.notifier).startOutgoing(
            const CallParty(
              displayName: 'Caller',
              phoneNumber: '+254700000001',
            ),
          ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(media.outboundAdmissionChecks, 1);
    expect(api.outboundInitiated, isFalse);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.failed);
  });

  test('native Android prewarm registers without creating a backend call',
      () async {
    if (!useAndroidNativeAtMedia) return;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final api = _FakeCallApi();
    final media = _FakeMedia();
    final container = _liveContainer(api: api, media: media);
    addTearDown(container.dispose);

    await container.read(callSessionControllerProvider.notifier).prewarmMedia();

    expect(api.mediaConfigReads, 1);
    expect(media.initializeCalls, 1);
    expect(api.outboundInitiated, isFalse);

    container.read(callSessionControllerProvider.notifier).startOutgoing(
          const CallParty(
            displayName: 'Caller',
            phoneNumber: '+254700000001',
          ),
        );
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!api.outboundInitiated && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(media.outboundAdmissionChecks, 1,
        reason: 'native call prep must run before backend call creation');
    expect(media.microphonePermissionChecks, 1,
        reason: 'native microphone permission must be checked before dialing');
    expect(api.outboundInitiated, isTrue);
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

  test('Android audio readiness starts only after backend accept succeeds',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final order = <String>[];
    final api = _FakeCallApi()..flowOrder = order;
    final media = _FakeMedia()..flowOrder = order;
    final container = _liveContainer(api: api, media: media);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(await controller.handleIncomingOffer(_incomingOffer()), isTrue);
    await controller.answer();

    expect(order.indexOf('accept_succeeded'),
        lessThan(order.indexOf('system_audio_ready')));
    expect(media.systemAudioPreparations, [('call-1', true)]);
  });

  test('failed backend accept never promotes incoming Telecom to active audio',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final api = _FakeCallApi()..acceptFailure = true;
    final media = _FakeMedia();
    final container = _liveContainer(api: api, media: media);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(await controller.handleIncomingOffer(_incomingOffer()), isTrue);
    await controller.answer();

    expect(media.systemAudioPreparations, isEmpty);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.failed);
  });

  test('Android outbound registration waits for its DIALING audio lease',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final order = <String>[];
    final api = _FakeCallApi()..flowOrder = order;
    final media = _FakeMedia()..flowOrder = order;
    final native = _FakeNativeCallService()..flowOrder = order;
    final container = _liveContainer(api: api, media: media, native: native);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(
        controller.startOutgoing(const CallParty(
          displayName: 'Caller',
          phoneNumber: '+254700000001',
        )),
        isTrue);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!order.contains('dial') && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(order.indexOf('begin_outgoing'),
        lessThan(order.indexOf('system_audio_ready')));
    expect(order.indexOf('system_audio_ready'),
        lessThan(order.indexOf('initialize')));
    expect(order.indexOf('initialize'), lessThan(order.indexOf('dial')));
  });

  test('incoming media event during initialization is not lost', () async {
    final api = _FakeCallApi();
    final media = _FakeMedia()..incomingInitializationGate = Completer<void>();
    final container = _liveContainer(api: api, media: media);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(await controller.handleIncomingOffer(_incomingOffer()), isTrue);
    final answer = controller.answer();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(media.incomingEventsEmitted, 1);

    media.incomingInitializationGate!.complete();
    await answer.timeout(const Duration(seconds: 1));

    expect(api.mediaReadySent, isTrue);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.active);
  });

  test('failed client-event telemetry does not block inbound media connection',
      () async {
    final api = _FakeCallApi()..failClientEvents = true;
    final container = _liveContainer(api: api);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(await controller.handleIncomingOffer(_incomingOffer()), isTrue);
    await controller.answer();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.active);
    expect(api.clientEventFailures, greaterThan(0));
  });

  test('remote decline keeps a short terminal acknowledgement', () async {
    final native = _FakeNativeCallService();
    final container = _liveContainer(native: native);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    await controller.handleIncomingOffer(_incomingOffer());

    native.emit(const NativeCallEvent(
      type: NativeCallEventType.disconnected,
      callId: 'call-1',
      reason: 'customer_declined',
    ));
    await Future<void>.delayed(Duration.zero);

    final state = container.read(callSessionControllerProvider);
    expect(state.lifecycle, CallLifecycle.terminalNotice);
    expect(state.statusLabel, 'Call declined');
  });

  test('unowned active snapshot is not resurrected during recovery', () async {
    final container = _liveContainer();
    addTearDown(container.dispose);

    await container.read(callSessionControllerProvider.notifier).recover(
          ActiveCallSnapshot(
            callId: 'call-owned-by-another-device',
            direction: CallDirection.inbound,
            phase: CallPhase.active,
            remoteNumber: '+254700000001',
            createdAt: DateTime.now().toUtc(),
          ),
        );

    expect(container.read(callSessionControllerProvider).hasCall, isFalse);
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
  _FakeMedia? media,
}) {
  return ProviderContainer(overrides: [
    callApiProvider.overrideWithValue(api ?? _FakeCallApi()),
    nativeCallServiceProvider
        .overrideWithValue(native ?? _FakeNativeCallService()),
    callMediaServiceProvider.overrideWithValue(media ?? _FakeMedia()),
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
  bool failClientEvents = false;
  int clientEventFailures = 0;
  int mediaConfigReads = 0;
  bool acceptFailure = false;
  List<String>? flowOrder;

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
    flowOrder?.add('accept_requested');
    if (acceptFailure) throw StateError('test_accept_failure');
    accepted = true;
    flowOrder?.add('accept_succeeded');
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
  Future<void> reportClientEvent({
    required String callId,
    required String offerId,
    required String installationId,
    required CallClientEvent event,
  }) async {
    if (failClientEvents) {
      clientEventFailures++;
      throw StateError('simulated telemetry failure');
    }
  }

  @override
  Future<void> end({required String callId, required String reason}) async {
    endCalls++;
  }

  int endCalls = 0;

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
    flowOrder?.add('backend_outbound');
    return const OutboundCallResult(callSid: 'AT-call-sess-initiated');
  }

  @override
  Future<ActiveCallSnapshot?> getActiveCall() async => null;

  @override
  Future<CallLogPage> getCallLogs({int page = 1, int perPage = 20}) async =>
      CallLogPage(records: const [], page: page, hasMore: false);

  @override
  Future<CallMediaConfig> getMediaConfig() async {
    mediaConfigReads++;
    return const CallMediaConfig(
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
      webrtcGatewayUrl: 'wss://gateway.example/connect',
    );
  }

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
  List<String>? flowOrder;

  @override
  Stream<NativeCallEvent> get events => _events.stream;

  @override
  Stream<NativeAudioSessionDiagnostic> get audioSessionDiagnostics =>
      const Stream<NativeAudioSessionDiagnostic>.empty();

  void emit(NativeCallEvent event) => _events.add(event);

  @override
  Future<String?> readNativePushToken() async => null;

  @override
  Future<CallOffer?> peekPendingOffer() async => null;

  @override
  Future<CallOffer?> takePendingOffer() async => null;

  @override
  Future<NativeIncomingCallLaunch?> peekInitialIncomingLaunch() async => null;

  @override
  Future<NativeIncomingCallLaunch?> takeInitialIncomingLaunch() async => null;

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
  Future<void> beginOutgoing(NativeCallIdentity identity) async =>
      flowOrder?.add('begin_outgoing');

  @override
  Future<void> waitForSystemAudioReady() async {}

  @override
  Future<void> markActive(NativeCallIdentity identity) async {}

  @override
  Future<void> markAnswering(NativeCallIdentity identity) async {}

  @override
  Future<void> markFailed(NativeCallIdentity identity,
      {String? reason}) async {}

  @override
  Future<void> setSystemSpeaker(bool enabled) async {}
}

class _FakeMedia implements CallMediaService {
  final _events = StreamController<CallMediaEvent>.broadcast();
  Object? outboundAdmissionError;
  int outboundAdmissionChecks = 0;
  int microphonePermissionChecks = 0;
  Completer<void>? incomingInitializationGate;
  int incomingEventsEmitted = 0;
  int initializeCalls = 0;
  List<String>? flowOrder;
  final List<(String, bool)> systemAudioPreparations = [];

  @override
  Stream<CallMediaEvent> get events => _events.stream;

  @override
  Future<void> prepareForNewOutboundCall() async {
    outboundAdmissionChecks++;
    final error = outboundAdmissionError;
    if (error != null) throw error;
  }

  @override
  Future<void> prepareSystemAudio({
    required String systemCallId,
    required bool incoming,
  }) async {
    flowOrder?.add('system_audio_ready');
    systemAudioPreparations.add((systemCallId, incoming));
  }

  @override
  Future<void> ensureMicrophonePermission() async {
    microphonePermissionChecks++;
  }

  @override
  Future<void> abandonMediaPreparation() async {}

  @override
  Future<String> initialize(CallMediaConfig config,
      {CallId? incomingCallId}) async {
    initializeCalls++;
    flowOrder?.add('initialize');
    scheduleMicrotask(() =>
        _events.add(const CallMediaEvent(type: CallMediaEventType.ready)));
    if (incomingCallId != null) {
      final gate = incomingInitializationGate;
      if (gate != null) {
        incomingEventsEmitted++;
        _events.add(const CallMediaEvent(type: CallMediaEventType.incoming));
        await gate.future;
      } else {
        Future<void>.delayed(const Duration(milliseconds: 5), () {
          _events.add(const CallMediaEvent(type: CallMediaEventType.incoming));
        });
      }
    }
    return 'webview-test-1';
  }

  @override
  Future<String> dial(
      {required String callSid,
      required String phoneNumber,
      String? sipTargetUri}) async {
    flowOrder?.add('dial');
    scheduleMicrotask(() => _events.add(
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
