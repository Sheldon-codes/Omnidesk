import 'dart:developer' as developer;

import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../index.dart';
import '../../main.dart';
import '../../services/auth_session_controller.dart';
import '../../services/onboarding_controller.dart';

export 'package:go_router/go_router.dart';

part 'nav.g.dart';

/// The application's single routing boundary.
///
/// Pages navigate through their static route paths; this router owns every
/// authentication, bootstrap, and onboarding redirect in one place.
@Riverpod(keepAlive: true)
GoRouter goRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: SplashScreenWidget.routePath,
    debugLogDiagnostics: true,
    redirect: (_, state) {
      final auth = ref.read(authSessionControllerProvider);
      final onboarding = ref.read(onboardingControllerProvider);
      final location = state.matchedLocation;

      developer.log(
        'redirect location=$location auth=${auth.status} '
        'bootstrapComplete=${auth.bootstrapComplete} '
        'onboardingInitialized=${onboarding.initialized} '
        'onboardingCompleted=${onboarding.completed}',
        name: 'Router',
      );

      if (auth.status == AuthStatus.bootstrapping ||
          (auth.status == AuthStatus.loading && !auth.bootstrapComplete) ||
          !onboarding.initialized) {
        return location == SplashScreenWidget.routePath
            ? null
            : SplashScreenWidget.routePath;
      }

      if (auth.isAuthenticated) {
        return location == HomePageWidget.routePath ||
                location == PhonePageWidget.routePath ||
                location == ChangePasswordPageWidget.routePath
            ? null
            : HomePageWidget.routePath;
      }

      if (!onboarding.completed) {
        return location == OnBoardingScreenWidget.routePath
            ? null
            : OnBoardingScreenWidget.routePath;
      }

      const publicRoutes = {
        LoginPageWidget.routePath,
        ForgotPasswordPageWidget.routePath,
        ResetPasswordPageWidget.routePath,
      };
      return publicRoutes.contains(location) ? null : LoginPageWidget.routePath;
    },
    errorBuilder: (_, __) => const SplashScreenWidget(),
    routes: [
      GoRoute(
        name: SplashScreenWidget.routeName,
        path: SplashScreenWidget.routePath,
        builder: (_, __) => const SplashScreenWidget(),
      ),
      GoRoute(
        name: OnBoardingScreenWidget.routeName,
        path: OnBoardingScreenWidget.routePath,
        builder: (_, __) => const OnBoardingScreenWidget(),
      ),
      GoRoute(
        name: LoginPageWidget.routeName,
        path: LoginPageWidget.routePath,
        builder: (_, __) => const LoginPageWidget(),
      ),
      GoRoute(
        name: ForgotPasswordPageWidget.routeName,
        path: ForgotPasswordPageWidget.routePath,
        builder: (_, __) => const ForgotPasswordPageWidget(),
      ),
      GoRoute(
        name: ResetPasswordPageWidget.routeName,
        path: ResetPasswordPageWidget.routePath,
        builder: (_, __) => const ResetPasswordPageWidget(),
      ),
      GoRoute(
        name: HomePageWidget.routeName,
        path: HomePageWidget.routePath,
        builder: (_, __) => const NavBarPage(
          initialPage: HomePageWidget.routeName,
        ),
      ),
      GoRoute(
        name: PhonePageWidget.routeName,
        path: PhonePageWidget.routePath,
        builder: (_, __) => const NavBarPage(
          initialPage: PhonePageWidget.routeName,
        ),
      ),
      GoRoute(
        name: ChangePasswordPageWidget.routeName,
        path: ChangePasswordPageWidget.routePath,
        builder: (_, __) => const ChangePasswordPageWidget(),
      ),
    ],
  );
  ref.listen<AuthState>(
      authSessionControllerProvider, (_, __) => router.refresh());
  ref.listen<OnboardingState>(
      onboardingControllerProvider, (_, __) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
}
