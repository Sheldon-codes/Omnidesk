import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'components/digistem_bottom_nav/digistem_bottom_nav.dart';
import 'firebase_options.dart';
import 'flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/nav/nav.dart';
import 'pages/home_page/home_page_widget.dart';
import 'pages/phone_page/phone_page_widget.dart';
import 'pages/chats_page/chats_page_widget.dart';
import 'pages/email_page/email_page_widget.dart';
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
          'Auth state: ${next.status}, '
          'bootstrapComplete=${next.bootstrapComplete}, '
          'hasSession=${next.session != null}',
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

/// Root-owned authenticated navigation, following OPDP's NavBarPage pattern.
///
/// Feature pages intentionally remain unaware of the bottom dock. Destinations
/// are selected by route while the dock remains owned by the app root.
class NavBarPage extends StatefulWidget {
  const NavBarPage({super.key, this.initialPage});

  final String? initialPage;

  @override
  State<NavBarPage> createState() => _NavBarPageState();
}

class _NavBarPageState extends State<NavBarPage> {
  late int _currentIndex;

  static const _routePaths = <String>[
    HomePageWidget.routePath,
    PhonePageWidget.routePath,
    ChatsPageWidget.routePath,
    EmailPageWidget.routePath,
    HomePageWidget.routePath,
  ];

  static int _indexForPage(String? page) {
    if (page == PhonePageWidget.routeName) return 1;
    if (page == ChatsPageWidget.routeName) return 2;
    if (page == EmailPageWidget.routeName) return 3;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = _indexForPage(widget.initialPage);
  }

  static const _items = <DigiStemBottomNavItem>[
    DigiStemBottomNavItem(
      id: 'home',
      label: 'Home',
      semanticLabel: 'Home',
      icon: IconsaxPlusBroken.home_1,
      selectedIcon: IconsaxPlusBold.home_1,
    ),
    DigiStemBottomNavItem(
      id: 'phone',
      label: 'Phone',
      semanticLabel: 'Phone',
      icon: IconsaxPlusBroken.call,
      selectedIcon: IconsaxPlusBold.call,
    ),
    DigiStemBottomNavItem(
      id: 'chats',
      label: 'Chats',
      semanticLabel: 'Chats',
      icon: IconsaxPlusBroken.messages,
      selectedIcon: IconsaxPlusBold.messages,
    ),
    DigiStemBottomNavItem(
      id: 'email',
      label: 'Email',
      semanticLabel: 'Email',
      icon: IconsaxPlusBroken.sms,
      selectedIcon: IconsaxPlusBold.sms,
    ),
    DigiStemBottomNavItem(
      id: 'tickets',
      label: 'Tickets',
      semanticLabel: 'Tickets',
      icon: IconsaxPlusBroken.ticket,
      selectedIcon: IconsaxPlusBold.ticket,
    ),
  ];

  static Widget _pageForIndex(int index) {
    switch (index) {
      case 1:
        return const PhonePageWidget();
      case 2:
        return const ChatsPageWidget();
      case 3:
        return const EmailPageWidget();
      default:
        return const HomePageWidget();
    }
  }

  @override
  Widget build(BuildContext context) => DigiStemBottomNav(
        items: _items,
        initialIndex: _currentIndex,
        onSelected: (index) => context.go(_routePaths[index]),
        body: _pageForIndex(_currentIndex),
      );
}
