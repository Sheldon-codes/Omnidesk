import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/components/call_experience/call_experience_host.dart';
import 'package:omnidesk_agent/components/call_experience/call_session_controller.dart';

const _party = CallParty(
  customerId: 'aloise-obaga',
  displayName: 'Aloise Obaga Kaizen School',
  phoneNumber: '+254723506031',
);

void main() {
  test('call controller supports incoming, active, and collapsed states', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(container.read(callSessionControllerProvider).hasCall, isFalse);
    expect(controller.startIncoming(_party), isTrue);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.incomingRinging);
    expect(controller.startOutgoing(_party), isFalse);

    controller.answer();
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.active);
    controller.toggleMute();
    controller.toggleSpeaker();
    controller.toggleHold();
    expect(container.read(callSessionControllerProvider).muted, isTrue);
    expect(
        container.read(callSessionControllerProvider).speakerEnabled, isTrue);
    expect(container.read(callSessionControllerProvider).onHold, isTrue);

    controller.openKeypad();
    controller.appendDtmfDigit('2');
    controller.appendDtmfDigit('#');
    expect(container.read(callSessionControllerProvider).dtmfDigits, '2#');
    controller.minimize();
    expect(container.read(callSessionControllerProvider).presentation,
        CallPresentation.collapsed);
    expect(
        container.read(callSessionControllerProvider).keypadVisible, isFalse);
    controller.restore();
    controller.end();
    expect(container.read(callSessionControllerProvider).hasCall, isFalse);
  });

  test('outgoing call can be connected deterministically', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(callSessionControllerProvider.notifier);

    expect(controller.startOutgoing(_party), isTrue);
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.outgoingRinging);
    controller.connectOutgoing();
    expect(container.read(callSessionControllerProvider).lifecycle,
        CallLifecycle.active);
    expect(container.read(callSessionControllerProvider).startedAt, isNotNull);
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
    controller.startOutgoing(_party);
    controller.connectOutgoing();

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
