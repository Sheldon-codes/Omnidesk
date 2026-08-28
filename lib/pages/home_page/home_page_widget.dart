import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/digistem_bottom_nav/digistem_bottom_nav.dart';
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
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    DigiStemBottomNavItem(
      id: 'phone',
      label: 'Phone',
      semanticLabel: 'Phone',
      icon: Icons.phone_outlined,
      selectedIcon: Icons.phone,
    ),
    DigiStemBottomNavItem(
      id: 'chats',
      label: 'Chats',
      semanticLabel: 'Chats',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    DigiStemBottomNavItem(
      id: 'email',
      label: 'Email',
      semanticLabel: 'Email',
      icon: Icons.mail_outline_rounded,
      selectedIcon: Icons.mail_rounded,
    ),
    DigiStemBottomNavItem(
      id: 'tickets',
      label: 'Tickets',
      semanticLabel: 'Tickets',
      icon: Icons.confirmation_number_outlined,
      selectedIcon: Icons.confirmation_number_rounded,
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
          title: const Text('Omnidesk Agent'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'password') {
                  context.go('/change-password');
                } else {
                  await ref
                      .read(authSessionControllerProvider.notifier)
                      .logout(everywhere: value == 'logoutAll');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'password',
                  child: Text('Change password'),
                ),
                PopupMenuItem(value: 'logout', child: Text('Log out')),
                PopupMenuItem(
                  value: 'logoutAll',
                  child: Text('Log out everywhere'),
                ),
              ],
            ),
          ],
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
}
