import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../components/home_app_bar/home_app_bar.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../services/auth_session_controller.dart';

export 'home_page_model.dart';

class HomePageWidget extends ConsumerWidget {
  const HomePageWidget({super.key});
  static const routeName = 'HomePage';
  static const routePath = '/home';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionControllerProvider).session!.user;
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
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
      body: Center(
        child: Semantics(
          label: 'Coming soon',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: theme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  IconsaxPlusBroken.timer_1,
                  size: 48,
                  color: theme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Coming soon',
                style: theme.headlineSmall.copyWith(
                  color: theme.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
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
