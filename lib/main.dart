import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'components/digistem_bottom_nav/digistem_bottom_nav.dart';
import 'components/call_experience/call_experience_host.dart';
import 'components/call_experience/call_session_controller.dart';
import 'services/calls/webview_call_media_service.dart';
import 'firebase_options.dart';
import 'flutter_flow/flutter_flow_theme.dart';
import 'flutter_flow/nav/nav.dart';
import 'pages/home_page/home_page_widget.dart';
import 'pages/home_page/home_dashboard_store.dart';
import 'pages/phone_page/phone_page_widget.dart';
import 'pages/profile_page/profile_page_model.dart';
import 'pages/notifications_page/notification_target_resolver.dart';
import 'pages/notifications_page/notifications_models.dart';
import 'pages/chats_page/chats_page_widget.dart';
import 'pages/email_page/email_page_widget.dart';
import 'pages/tickets_page/tickets_page_widget.dart';
import 'services/auth_session_controller.dart';
import 'services/agent_counters.dart';
import 'services/calls/call_lifecycle_coordinator.dart';
import 'services/fcm_service.dart';
import 'services/onboarding_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await FlutterFlowTheme.initialize();
  await dotenv.load(fileName: '.env');
  var fcmEnabled = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    fcmEnabled = true;
  } catch (error) {
    developer.log(
      'FCM initialization failed; push features are unavailable: '
      '${error.runtimeType}.',
      name: 'MainApp',
    );
  }
  runApp(ProviderScope(child: OmnideskAgentApp(fcmEnabled: fcmEnabled)));
}

class OmnideskAgentApp extends ConsumerStatefulWidget {
  const OmnideskAgentApp({super.key, required this.fcmEnabled});

  final bool fcmEnabled;
  @override
  ConsumerState<OmnideskAgentApp> createState() => _OmnideskAgentAppState();
}

class _OmnideskAgentAppState extends ConsumerState<OmnideskAgentApp>
    with WidgetsBindingObserver {
  ProviderSubscription<AuthState>? _authSubscription;
  ProviderSubscription<OnboardingState>? _onboardingSubscription;
  ProviderSubscription<CallSessionState>? _callSubscription;
  StreamSubscription<AppNotification>? _notificationTapSubscription;
  StreamSubscription<void>? _counterRefreshSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = ref.listenManual<AuthState>(
      authSessionControllerProvider,
      (previous, next) {
        developer.log(
          'Auth state: ${next.status}, '
          'bootstrapComplete=${next.bootstrapComplete}, '
          'hasSession=${next.session != null}',
          name: 'MainApp',
        );
        if (next.isAuthenticated) {
          ref.read(homeDashboardProvider.notifier).startHeartbeat();
          ref.read(agentCountersProvider.notifier).setAppActive(true);
          // Revalidate/rebuild an idle WebRTC standby client after auth or
          // workspace changes. The controller is single-flight and will not
          // touch an active call.
          unawaited(
            ref.read(callSessionControllerProvider.notifier).prewarmMedia(),
          );
          unawaited(
            ref.read(callLifecycleCoordinatorProvider).updateAuth(next),
          );
        } else if (ref.exists(homeDashboardProvider)) {
          ref.read(homeDashboardProvider.notifier).stopHeartbeat();
          ref.read(agentCountersProvider.notifier).setAppActive(false);
          unawaited(ref.read(callLifecycleCoordinatorProvider).stop());
        }
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
    _callSubscription = ref.listenManual<CallSessionState>(
      callSessionControllerProvider,
      (_, next) {
        final critical = next.hasCall &&
            next.lifecycle != CallLifecycle.terminalNotice &&
            next.lifecycle != CallLifecycle.failed;
        ref.read(agentCountersProvider.notifier).setCallCritical(critical);
      },
      fireImmediately: true,
    );
    if (widget.fcmEnabled) {
      _notificationTapSubscription =
          ref.read(fcmServiceProvider).notificationTaps.listen((notification) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(goRouterProvider).push(notificationRoute(notification));
          }
        });
      });
      // Notification payloads are not a source of truth for counts. A
      // foreground event simply asks the lightweight counter endpoint for a
      // fresh workspace-scoped snapshot. Incoming-call delivery continues to
      // be owned by the existing native/FCM call path.
      _counterRefreshSubscription = ref
          .read(fcmServiceProvider)
          .notificationRefreshEvents
          .listen((_) => unawaited(ref
              .read(agentCountersProvider.notifier)
              .refresh(reason: 'notification')));
      Future.microtask(() => ref.read(fcmServiceProvider).initialize());
    } else {
      developer.log(
        'Skipping Flutter FCM initialization because Firebase failed to '
        'initialize; native push registration may be unavailable.',
        name: 'MainApp',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.close();
    _onboardingSubscription?.close();
    _callSubscription?.close();
    _notificationTapSubscription?.cancel();
    _counterRefreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(agentCountersProvider.notifier).setAppActive(true);
      final hasLocalCall = ref.read(callSessionControllerProvider).hasCall;
      if (!hasLocalCall) {
        unawaited(
          ref.read(authSessionControllerProvider.notifier).refreshSession(),
        );
      }
      if (ref.read(authSessionControllerProvider).isAuthenticated) {
        ref.read(homeDashboardProvider.notifier).startHeartbeat();
        unawaited(
          ref.read(callSessionControllerProvider.notifier).prewarmMedia(),
        );
        if (!hasLocalCall) {
          unawaited(ref.read(callLifecycleCoordinatorProvider).recover());
        }
      } else if (ref.exists(homeDashboardProvider)) {
        ref.read(homeDashboardProvider.notifier).stopHeartbeat();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(agentCountersProvider.notifier).setAppActive(false);
      ref.read(homeDashboardProvider.notifier).stopHeartbeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeModeProvider);
    return MaterialApp.router(
      title: 'Omnidesk Agent',
      debugShowCheckedModeBanner: false,
      theme: _themeData(LightModeTheme(), Brightness.light),
      darkTheme: _themeData(DarkModeTheme(), Brightness.dark),
      themeMode: themeMode,
      routerConfig: ref.watch(goRouterProvider),
      builder: (context, child) =>
          _AppCallOverlay(child: child ?? const SizedBox.shrink()),
    );
  }

  ThemeData _themeData(FlutterFlowTheme flowTheme, Brightness brightness) =>
      ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: brightness == Brightness.dark
            ? ColorScheme.dark(
                primary: flowTheme.primary,
                onPrimary: flowTheme.primaryBackground,
                secondary: flowTheme.secondary,
                onSecondary: flowTheme.primaryBackground,
                error: flowTheme.error,
                onError: flowTheme.primaryBackground,
                surface: flowTheme.secondaryBackground,
                onSurface: flowTheme.primaryText,
              )
            : ColorScheme.light(
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
      );
}

/// App-root call overlay: the existing call UI plus an authenticated warm
/// WebView bridge. The bridge shell is preloaded only after the first app
/// frame, and remains inert until a call obtains fresh media credentials.
class _AppCallOverlay extends ConsumerStatefulWidget {
  const _AppCallOverlay({required this.child});

  final Widget child;

  @override
  ConsumerState<_AppCallOverlay> createState() => _AppCallOverlayState();
}

class _AppCallOverlayState extends ConsumerState<_AppCallOverlay> {
  Timer? _warmupTimer;
  bool _warmupScheduled = false;
  bool _warmMedia = false;

  @override
  void dispose() {
    _warmupTimer?.cancel();
    super.dispose();
  }

  void _scheduleMediaWarmup() {
    if (_warmupScheduled || _warmMedia) return;
    _warmupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Let the initial authenticated route paint and settle before Chromium
      // allocates its platform view. This keeps startup responsive while
      // still warming the bridge well before a normal incoming call.
      _warmupTimer = Timer(const Duration(milliseconds: 750), () {
        if (!mounted ||
            !ref.read(authSessionControllerProvider).isAuthenticated) {
          _warmupScheduled = false;
          return;
        }
        setState(() => _warmMedia = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(ref
                .read(callSessionControllerProvider.notifier)
                .prewarmMedia());
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final authenticated =
        ref.watch(authSessionControllerProvider).isAuthenticated;
    if (authenticated) _scheduleMediaWarmup();
    final callState = ref.watch(callSessionControllerProvider);
    final media = ref.read(webViewCallMediaServiceProvider);
    final shouldMountMedia =
        (authenticated && (_warmMedia || media.hasController)) ||
            (callState.hasCall &&
                (callState.lifecycle != CallLifecycle.incomingRinging ||
                    !callState.nativeIncomingSurfaceActive));
    return CallExperienceHost(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shouldMountMedia) const HiddenCallWebView(),
          widget.child,
        ],
      ),
    );
  }
}

/// Root-owned authenticated navigation, following OPDP's NavBarPage pattern.
///
/// Feature pages intentionally remain unaware of the bottom dock. Destinations
/// are selected by route while the dock remains owned by the app root.
class NavBarPage extends ConsumerStatefulWidget {
  const NavBarPage({super.key, this.initialPage, this.initialTicketStatus});

  final String? initialPage;
  final TicketStatus? initialTicketStatus;

  @override
  ConsumerState<NavBarPage> createState() => _NavBarPageState();
}

class _NavBarPageState extends ConsumerState<NavBarPage> {
  late int _currentIndex;

  static const _routePaths = <String>[
    HomePageWidget.routePath,
    PhonePageWidget.routePath,
    ChatsPageWidget.routePath,
    EmailPageWidget.routePath,
    TicketsPageWidget.routePath,
  ];

  static int _indexForPage(String? page) {
    if (page == PhonePageWidget.routeName) return 1;
    if (page == ChatsPageWidget.routeName) return 2;
    if (page == EmailPageWidget.routeName) return 3;
    if (page == TicketsPageWidget.routeName) return 4;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = _indexForPage(widget.initialPage);
  }

  static List<DigiStemBottomNavItem> _items(AgentCounters counters) => [
        const DigiStemBottomNavItem(
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
          badgeCount: counters.missedCalls,
        ),
        DigiStemBottomNavItem(
          id: 'chats',
          label: 'Chats',
          semanticLabel: 'Chats',
          icon: IconsaxPlusBroken.messages,
          selectedIcon: IconsaxPlusBold.messages,
          badgeCount: counters.chatUnread,
        ),
        DigiStemBottomNavItem(
          id: 'email',
          label: 'Email',
          semanticLabel: 'Email',
          icon: IconsaxPlusBroken.sms,
          selectedIcon: IconsaxPlusBold.sms,
          badgeCount: counters.emailUnread,
        ),
        DigiStemBottomNavItem(
          id: 'tickets',
          label: 'Tickets',
          semanticLabel: 'Tickets',
          icon: IconsaxPlusBroken.ticket,
          selectedIcon: IconsaxPlusBold.ticket,
          badgeCount: counters.openTickets,
        ),
      ];

  Widget _pageForIndex(int index) {
    switch (index) {
      case 1:
        return const PhonePageWidget();
      case 2:
        return const ChatsPageWidget();
      case 3:
        return const EmailPageWidget();
      case 4:
        return TicketsPageWidget(initialStatus: widget.initialTicketStatus);
      default:
        return const HomePageWidget();
    }
  }

  @override
  Widget build(BuildContext context) {
    final counters = ref.watch(agentCountersProvider).counters;
    return DigiStemBottomNav(
      items: _items(counters),
      initialIndex: _currentIndex,
      onSelected: (index) => context.go(_routePaths[index]),
      body: _pageForIndex(_currentIndex),
    );
  }
}
