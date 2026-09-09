import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/components/call_experience/call_experience_host.dart';
import 'package:omnidesk_agent/components/call_experience/call_session_controller.dart';
import 'package:omnidesk_agent/services/calls/call_api.dart';
import 'package:omnidesk_agent/services/calls/call_models.dart';
import 'package:omnidesk_agent/services/calls/device_installation_service.dart';
import 'package:omnidesk_agent/services/calls/native_call_service.dart';

const _party = CallParty(
  customerId: 'aloise-obaga',
  displayName: 'Aloise Obaga Kaizen School',
  phoneNumber: '+254723506031',
);

void main() {
  test('call controller supports incoming, active, and collapsed states',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(container.read(callSessionControllerProvider).hasCall, isFalse);
    expect(controller.startIncoming(_party), isTrue);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.incomingRinging);
    expect(controller.startOutgoing(_party), isFalse);

    await controller.answer();
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

  test('outgoing call does not recreate the removed timer-driven demo flow',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(controller.startOutgoing(_party), isFalse);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.idle);
    expect(container.read(callSessionControllerProvider).hasCall, isFalse);
    expect(container.read(callSessionControllerProvider).failureMessage,
        contains('Outgoing calling'));
    controller.connectOutgoing();
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.idle);
  });

  test('live incoming offer follows accept, media-ready, then native connect',
      () async {
    final api = _FakeCallApi();
    final native = _FakeNativeCallService();
    final container = ProviderContainer(overrides: [
      callApiProvider.overrideWithValue(api),
      nativeCallServiceProvider.overrideWithValue(native),
      callInstallationIdProvider
          .overrideWithValue(() async => 'installation-1'),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);
    final now = DateTime.now().toUtc();
    final offer = CallOffer(
      callId: 'call-1',
      offerId: 'offer-1',
      provider: 'africas_talking',
      callerNumber: '+254700000001',
      callerName: 'Aloise',
      workspaceId: 'workspace-1',
      receivedAt: now,
      expiresAt: now.add(const Duration(seconds: 30)),
    );

    expect(await controller.handleIncomingOffer(offer), isTrue);
    expect(container.read(callSessionControllerProvider).callId, 'call-1');
    await controller.answer();
    await Future<void>.delayed(Duration.zero);

    expect(api.deliveryAcknowledged, isTrue);
    expect(api.accepted, isTrue);
    expect(api.mediaReadySent, isTrue);
    expect(native.registered, isTrue);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.active);
  });

  testWidgets('incoming fullscreen answers and minimizes to call bar',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(callSessionControllerProvider.notifier)
        .startIncoming(_party);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: CallExperienceHost(
          child: Scaffold(body: Center(child: Text('App content'))),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Incoming call'), findsOneWidget);
    expect(find.byIcon(Icons.close_fullscreen_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Answer'), findsOneWidget);
    expect(find.bySemanticsLabel('Decline'), findsOneWidget);
    expect(find.text('App content'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Answer'));
    await tester.pump();
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
    container.read(callSessionControllerProvider.notifier).end();
  });

  testWidgets('active call keypad records local DTMF digits', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);
    controller.startDemoIncoming(_party);
    controller.answer();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: CallExperienceHost(child: Scaffold()),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Keypad'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.tap(find.text('#'));
    await tester.pump();
    expect(find.text('2#'), findsOneWidget);
    expect(container.read(callSessionControllerProvider).dtmfDigits, '2#');
    expect(find.bySemanticsLabel('Close keypad'), findsOneWidget);
    expect(find.bySemanticsLabel('Delete last digit. Long press to clear'),
        findsOneWidget);
    await tester
        .tap(find.bySemanticsLabel('Delete last digit. Long press to clear'));
    await tester.pump();
    expect(container.read(callSessionControllerProvider).dtmfDigits, '2');
    await tester.longPress(
        find.bySemanticsLabel('Delete last digit. Long press to clear'));
    await tester.pump();
    expect(container.read(callSessionControllerProvider).dtmfDigits, isEmpty);
    controller.end();
  });

  testWidgets('call controls work when the host is mounted in app builder',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(callSessionControllerProvider.notifier)
        .startIncoming(_party);

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
    expect(find.bySemanticsLabel('Answer'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Answer'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Minimize call'), findsOneWidget);
    container.read(callSessionControllerProvider.notifier).end();
  });
}

class _FakeCallApi implements CallApi {
  bool deliveryAcknowledged = false;
  bool accepted = false;
  bool mediaReadySent = false;

  @override
  Future<void> acknowledgeDelivery({
    required String callId,
    required String installationId,
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
  Future<ActiveCallSnapshot?> getActiveCall() async => null;

  @override
  Future<CallMediaConfig> getMediaConfig() async => const CallMediaConfig(
        provider: 'africas_talking',
        transport: 'sip',
        endpointType: 'mobile',
        sipUri: 'sip:agent@example.test',
        sipUsername: 'agent',
        sipPassword: 'short-lived',
        registrar: 'example.test',
        sipTransport: 'tls',
        port: 5061,
        supportsHold: true,
        supportsDtmf: true,
        supportsNativeIncoming: true,
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
  bool registered = false;
  String? _callId;

  @override
  Stream<NativeCallEvent> get events => _events.stream;

  @override
  Future<void> dismiss(String callId) async {}

  @override
  Future<void> endMedia(String callId) async {}

  @override
  Future<void> presentIncoming(CallOffer offer) async => _callId = offer.callId;

  @override
  Future<void> registerMedia(CallMediaConfig config) async {
    registered = true;
    _events.add(NativeCallEvent(
      type: NativeCallEventType.connected,
      callId: _callId!,
    ));
  }

  @override
  Future<void> sendDtmf(String digit) async {}

  @override
  Future<void> setHeld(bool enabled) async {}

  @override
  Future<void> setMuted(bool enabled) async {}

  @override
  Future<void> setSpeaker(bool enabled) async {}
}
