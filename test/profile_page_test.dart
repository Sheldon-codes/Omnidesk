import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/models/auth/auth_models.dart';
import 'package:omnidesk_agent/pages/profile_page/profile_page_widget.dart';
import 'package:omnidesk_agent/services/auth_session_controller.dart';

void main() {
  test('presence state updates independently and retries failures', () async {
    final repository = _FakePresenceRepository(failNext: true);
    final container = ProviderContainer(overrides: [
      agentPresenceRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(agentPresenceProvider.notifier);

    expect(
        container.read(agentPresenceProvider).status, PresenceStatus.available);
    expect(container.read(agentPresenceProvider).receiveIncomingCalls, isTrue);

    expect(await controller.setStatus(PresenceStatus.away), isFalse);
    expect(
        container.read(agentPresenceProvider).status, PresenceStatus.available);
    expect(container.read(agentPresenceProvider).failure, isNotNull);

    repository.failNext = false;
    expect(await controller.retry(), isTrue);
    expect(container.read(agentPresenceProvider).status, PresenceStatus.away);

    expect(await controller.setReceiveIncomingCalls(false), isTrue);
    expect(container.read(agentPresenceProvider).status, PresenceStatus.away);
    expect(container.read(agentPresenceProvider).receiveIncomingCalls, isFalse);
  });

  testWidgets('Profile renders account data and availability controls',
      (tester) async {
    final container = ProviderContainer(overrides: [
      authSessionControllerProvider.overrideWithValue(_authenticatedState),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProfilePageWidget()),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Hillary Agent'), findsOneWidget);
    expect(find.text('Agent · Digiskool'), findsOneWidget);
    expect(find.text('hillary@omnidesk.co.ke'), findsOneWidget);
    expect(find.text('Receive incoming calls'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Home'), findsNothing);

    await tester.tap(find.text('Available').first);
    await tester.pumpAndSettle();
    expect(find.text('Set availability'), findsOneWidget);
    expect(find.text('Busy'), findsOneWidget);
    await tester.tap(find.text('Away').last);
    await tester.pumpAndSettle();
    expect(container.read(agentPresenceProvider).status, PresenceStatus.away);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(container.read(agentPresenceProvider).receiveIncomingCalls, isFalse);

    await tester.ensureVisible(find.text('App theme'));
    await tester.pumpAndSettle();
    expect(find.text('System default'), findsOneWidget);
    await tester.tap(find.text('App theme'));
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(container.read(appThemeModeProvider), ThemeMode.dark);

    await tester.scrollUntilVisible(find.text('Sign out'), 300);
    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'You’ll stop receiving calls and assignments on this device.'),
        findsOneWidget);
  });

  test('theme preference can be changed independently from presence', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(appThemeModeProvider.notifier);
    controller.setThemeMode(ThemeMode.light);
    expect(container.read(appThemeModeProvider), ThemeMode.light);

    controller.setThemeMode(ThemeMode.system);
    expect(container.read(appThemeModeProvider), ThemeMode.system);
  });
}

class _FakePresenceRepository implements AgentPresenceRepository {
  _FakePresenceRepository({required this.failNext});
  bool failNext;
  @override
  Future<void> updateCallAvailability(bool enabled) async {}
  @override
  Future<void> updateStatus(PresenceStatus status) async {
    if (failNext) throw StateError('offline');
  }
}

final _authenticatedState = AuthState(
  status: AuthStatus.authenticated,
  bootstrapComplete: true,
  session: AuthSession(
    accessToken: 'test-token',
    tokenType: 'Bearer',
    user: const AuthUser(
      id: 'agent-hillary',
      name: 'Hillary Agent',
      email: 'hillary@omnidesk.co.ke',
      phone: '+254720228448',
      role: 'Agent',
      isSuperAdmin: false,
      status: 'active',
      activeWorkspace: WorkspaceMembership(
        id: 'digiskool',
        name: 'Digiskool',
        slug: 'digiskool',
        role: 'Agent',
      ),
    ),
  ),
);
