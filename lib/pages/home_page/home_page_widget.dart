import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../components/digistem_bottom_nav/digistem_bottom_nav.dart';
import '../../components/home_app_bar/home_app_bar.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../services/auth_session_controller.dart';
import 'home_page_model.dart';

export 'home_page_model.dart';

class HomePageWidget extends ConsumerWidget {
  const HomePageWidget({super.key});
  static const routeName = 'HomePage';
  static const routePath = '/home';

  static const _bottomNavigationItems = <DigiStemBottomNavItem>[
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionControllerProvider).session!.user;
    final state = ref.watch(homePageProvider);
    final theme = FlutterFlowTheme.of(context);
    return DigiStemBottomNav(
      items: _bottomNavigationItems,
      onSelected: (_) => context.go(routePath),
      body: Scaffold(
        appBar: AppBar(
          backgroundColor: theme.primaryBackground,
          surfaceTintColor: theme.primaryBackground,
          elevation: 0,
          titleSpacing: 0,
          toolbarHeight: 84,
          title: HomeAppBar(
            user: user,
            includeTopInset: false,
            locationLabel: user.activeWorkspace?.name ?? 'Your workspace',
            onAvatarTap: () => _showAccountMenu(context, ref),
            onNotificationTap: () {},
          ),
          actions: const [],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              CircleAvatar(child: Text(user.initials)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.greeting,
                      style: theme.titleLarge
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      state.subtitle,
                      style:
                          theme.bodyMedium.copyWith(color: theme.secondaryText),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 32),
            Text(
              'Home',
              style: theme.headlineSmall.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Card(
              color: theme.secondaryBackground,
              child: const ListTile(
                leading: Icon(Icons.inbox_outlined),
                title: Text('Your agent home is ready'),
                subtitle: Text(
                  'Conversation, customer, and queue content will appear here.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAccountMenu(BuildContext context, WidgetRef ref) async {
    final selection = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(16, 90, 0, 0),
      items: const [
        PopupMenuItem(value: 'password', child: Text('Change password')),
        PopupMenuItem(value: 'logout', child: Text('Log out')),
        PopupMenuItem(value: 'logoutAll', child: Text('Log out everywhere')),
      ],
    );
    if (selection == null || !context.mounted) return;
    if (selection == 'password') {
      context.go('/change-password');
      return;
    }
    await ref
        .read(authSessionControllerProvider.notifier)
        .logout(everywhere: selection == 'logoutAll');
  }
}
