import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omnidesk_agent/index.dart';
import 'package:omnidesk_agent/flutter_flow/nav/nav.dart';
import 'package:omnidesk_agent/models/auth/auth_models.dart';
import 'package:omnidesk_agent/services/auth_session_controller.dart';
import 'package:omnidesk_agent/services/onboarding_controller.dart';

void main() {
  testWidgets('bootstrap redirects unresolved auth state to splash',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authSessionControllerProvider.overrideWithValue(
          const AuthState(status: AuthStatus.bootstrapping),
        ),
        onboardingControllerProvider.overrideWithValue(
          const OnboardingState(initialized: true, completed: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(goRouterProvider);
    await _attachRouter(
      tester,
      router,
      auth: const AuthState(status: AuthStatus.bootstrapping),
      onboarding: const OnboardingState(initialized: true, completed: false),
    );
    router.go(LoginPageWidget.routePath);
    await _pumpRoute(tester);

    expect(router.routerDelegate.currentConfiguration.uri.path,
        SplashScreenWidget.routePath);
  });

  testWidgets('unauthenticated cold launch routes to onboarding',
      (tester) async {
    final router = _router(
      auth: const AuthState(status: AuthStatus.unauthenticated),
      onboarding: const OnboardingState(initialized: true, completed: false),
    );
    await _attachRouter(
      tester,
      router,
      auth: const AuthState(status: AuthStatus.unauthenticated),
      onboarding: const OnboardingState(initialized: true, completed: false),
    );
    router.go(LoginPageWidget.routePath);
    await _pumpRoute(tester);

    expect(router.routerDelegate.currentConfiguration.uri.path,
        OnBoardingScreenWidget.routePath);
  });

  testWidgets('completed onboarding routes unauthenticated users to login',
      (tester) async {
    final router = _router(
      auth: const AuthState(status: AuthStatus.unauthenticated),
      onboarding: const OnboardingState(initialized: true, completed: true),
    );
    await _attachRouter(
      tester,
      router,
      auth: const AuthState(status: AuthStatus.unauthenticated),
      onboarding: const OnboardingState(initialized: true, completed: true),
    );
    router.go(OnBoardingScreenWidget.routePath);
    await _pumpRoute(tester);

    expect(router.routerDelegate.currentConfiguration.uri.path,
        LoginPageWidget.routePath);
  });

  testWidgets('restored authenticated session routes directly to home',
      (tester) async {
    final router = _router(
      auth: AuthState(
        status: AuthStatus.authenticated,
        session: AuthSession(
          accessToken: 'test-token',
          tokenType: 'Bearer',
          user: const AuthUser(
            id: 'user-1',
            name: 'Test User',
            email: 'test@example.com',
            role: 'agent',
            isSuperAdmin: false,
            status: 'active',
          ),
        ),
      ),
      onboarding: const OnboardingState(initialized: true, completed: false),
    );
    await _attachRouter(
      tester,
      router,
      auth: AuthState(
        status: AuthStatus.authenticated,
        session: AuthSession(
          accessToken: 'test-token',
          tokenType: 'Bearer',
          user: const AuthUser(
            id: 'user-1',
            name: 'Test User',
            email: 'test@example.com',
            role: 'agent',
            isSuperAdmin: false,
            status: 'active',
          ),
        ),
      ),
      onboarding: const OnboardingState(initialized: true, completed: false),
    );
    router.go(OnBoardingScreenWidget.routePath);
    await _pumpRoute(tester);

    expect(router.routerDelegate.currentConfiguration.uri.path,
        HomePageWidget.routePath);
  });
}

Future<void> _attachRouter(
  WidgetTester tester,
  GoRouter router, {
  required AuthState auth,
  required OnboardingState onboarding,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionControllerProvider.overrideWithValue(auth),
        onboardingControllerProvider.overrideWithValue(onboarding),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

Future<void> _pumpRoute(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

GoRouter _router({
  required AuthState auth,
  required OnboardingState onboarding,
}) {
  final container = ProviderContainer(
    overrides: [
      authSessionControllerProvider.overrideWithValue(auth),
      onboardingControllerProvider.overrideWithValue(onboarding),
    ],
  );
  final router = container.read(goRouterProvider);
  addTearDown(container.dispose);
  return router;
}
