import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/nav/nav.dart';
import 'services/auth_session_controller.dart';
import 'services/fcm_service.dart';
import 'services/onboarding_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await FlutterFlowTheme.initialize();
  await dotenv.load(fileName: '.env');
  var fcmEnabled = false;
  if (dotenv.env['ENABLE_FCM'] == 'true') {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      fcmEnabled = true;
    } catch (error) {
      developer.log(
        'FCM was enabled but Firebase configuration is unavailable: $error',
        name: 'MainApp',
      );
    }
  }
  runApp(ProviderScope(child: OmnideskAgentApp(fcmEnabled: fcmEnabled)));
}

class OmnideskAgentApp extends ConsumerStatefulWidget {
  const OmnideskAgentApp({super.key, required this.fcmEnabled});

  final bool fcmEnabled;
  @override
  ConsumerState<OmnideskAgentApp> createState() => _OmnideskAgentAppState();
}

class _OmnideskAgentAppState extends ConsumerState<OmnideskAgentApp> {
  ProviderSubscription<AuthState>? _authSubscription;
  ProviderSubscription<OnboardingState>? _onboardingSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = ref.listenManual<AuthState>(
      authSessionControllerProvider,
      (previous, next) {
        developer.log(
          'Auth state: ${next.status}, hasSession=${next.session != null}',
          name: 'MainApp',
        );
      },
      fireImmediately: true,
    );
    _onboardingSubscription = ref.listenManual<OnboardingState>(
      onboardingControllerProvider,
      (previous, next) {
        developer.log(
          'Onboarding state: initialized=${next.initialized}, '
          'completed=${next.completed}',
          name: 'MainApp',
        );
      },
      fireImmediately: true,
    );
    if (widget.fcmEnabled) {
      Future.microtask(() => ref.read(fcmServiceProvider).initialize());
    }
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _onboardingSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flowTheme = FlutterFlowTheme.of(context);
    return MaterialApp.router(
      title: 'Omnidesk Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: flowTheme.primary,
          onPrimary: flowTheme.primaryBackground,
          secondary: flowTheme.secondary,
          onSecondary: flowTheme.primaryBackground,
          error: flowTheme.error,
          onError: flowTheme.primaryBackground,
          surface: flowTheme.secondaryBackground,
          onSurface: flowTheme.primaryText,
        ),
        scaffoldBackgroundColor: flowTheme.primaryBackground,
        textTheme: TextTheme(
          headlineSmall: flowTheme.headlineSmall,
          titleLarge: flowTheme.titleLarge,
          titleMedium: flowTheme.titleMedium,
          bodyLarge: flowTheme.bodyLarge,
          bodyMedium: flowTheme.bodyMedium,
          bodySmall: flowTheme.bodySmall,
          labelLarge: flowTheme.labelLarge,
        ),
      ),
      routerConfig: ref.watch(goRouterProvider),
    );
  }
}
