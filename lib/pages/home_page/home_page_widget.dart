import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../components/home_app_bar/home_app_bar.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../services/auth_session_controller.dart';

export 'home_page_model.dart';

/// Local placeholder for the agent's availability status.
/// TODO: replace with the real availability provider once one exists.
final _agentAvailabilityProvider =
    NotifierProvider<_AgentAvailabilityController, bool>(
  _AgentAvailabilityController.new,
);

class _AgentAvailabilityController extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

class HomePageWidget extends ConsumerWidget {
  const HomePageWidget({super.key});
  static const routeName = 'HomePage';
  static const routePath = '/home';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionControllerProvider).session!.user;
    final theme = FlutterFlowTheme.of(context);
    final isAvailable = ref.watch(_agentAvailabilityProvider);
    return Scaffold(
      backgroundColor: theme.secondaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        surfaceTintColor: theme.secondaryBackground,
        elevation: 0,
        titleSpacing: 0,
        toolbarHeight: 84,
        title: HomeAppBar(
          user: user,
          includeTopInset: false,
          locationLabel: user.activeWorkspace?.name ?? 'Your workspace',
          onAvatarTap: () => _showAccountMenu(context, ref),
          leadingAction: _AvailabilityButton(
            isAvailable: isAvailable,
            onPressed: () =>
                ref.read(_agentAvailabilityProvider.notifier).toggle(),
          ),
          onNotificationTap: () {},
        ),
        actions: const [],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel('Needs attention', theme: theme),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                    color: theme.primaryBackground,
                    border: Border.all(color: theme.alternate),
                    borderRadius: BorderRadius.all(Radius.circular(12))),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      _AttentionRow(
                        theme: theme,
                        icon: IconsaxPlusBroken.danger,
                        title: 'Escalated',
                        count: 7,
                        onTap: () => context.go('/tickets?filter=escalated'),
                      ),
                      SizedBox(
                        height: 10,
                      ),
                      _AttentionRow(
                        theme: theme,
                        icon: IconsaxPlusBroken.clock,
                        title: 'Overdue',
                        count: 7,
                        onTap: () => context.go('/tickets?filter=overdue'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _SectionLabel('Channels', theme: theme),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ChannelCell(
                      theme: theme,
                      icon: IconsaxPlusBroken.call,
                      value: '9',
                      label: 'Calls · 3 missed',
                      overdueLabel: '3 missed',
                      onTap: () => context.go('/phone'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ChannelCell(
                      theme: theme,
                      icon: IconsaxPlusBroken.messages,
                      value: '3',
                      label: 'Chats · unread',
                      overdueLabel: '3 overdue',
                      onTap: () => context.go('/chats'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ChannelCell(
                      theme: theme,
                      icon: IconsaxPlusBroken.sms,
                      value: '11',
                      label: 'Email · unread',
                      overdueLabel: '4 overdue',
                      onTap: () => context.go('/email'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ChannelCell(
                      theme: theme,
                      icon: IconsaxPlusBroken.ticket,
                      value: '8',
                      label: 'Tickets · open',
                      overdueLabel: '7 overdue',
                      onTap: () => context.go('/tickets'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionButton(
                      theme: theme,
                      icon: IconsaxPlusBroken.call,
                      label: 'Call',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickActionButton(
                      theme: theme,
                      icon: IconsaxPlusBroken.messages,
                      label: 'Chat',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickActionButton(
                      theme: theme,
                      icon: IconsaxPlusBroken.sms,
                      label: 'Email',
                      onTap: () {},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SectionHeader(
                theme: theme,
                title: 'My work',
                actionLabel: 'View all',
                onActionTap: () => context.go('/tickets'),
              ),
              const SizedBox(height: 12),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: theme.primaryBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.alternate),
                ),
                child: Column(
                  children: [
                    _TicketRow(
                      theme: theme,
                      ticketId: 'DGKSL-802',
                      status: 'Escalated',
                      statusColor: theme.error,
                      subject: 'Billing dispute follow-up needed',
                      meta: 'High · SLA 2h 10m',
                      onTap: () {},
                    ),
                    _TicketRow(
                      theme: theme,
                      ticketId: 'DGKSL-378',
                      status: 'Overdue',
                      statusColor: theme.error,
                      subject: 'Technical support call from caller 1967',
                      meta: 'Medium · SLA 23h 55m',
                      onTap: () {},
                    ),
                    _TicketRow(
                      theme: theme,
                      ticketId: 'DGKSL-376',
                      status: 'Open',
                      statusColor: theme.secondaryText,
                      subject: 'Good morning Hillary — Nana',
                      meta: 'Low priority',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _SectionLabel('Recent activity', theme: theme),
              const SizedBox(height: 2),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: theme.primaryBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.alternate),
                ),
                child: Column(
                  children: [
                    _ActivityRow(
                      theme: theme,
                      icon: IconsaxPlusBroken.call_incoming,
                      text: 'Ann Riena Admin · 0790584913',
                      time: '18 min ago · 8:46',
                      isLast: false,
                    ),
                    _ActivityRow(
                      theme: theme,
                      icon: IconsaxPlusBroken.call_slash,
                      iconColor: theme.error,
                      text: 'Missed call · Riena School',
                      time: '33 min ago',
                      isLast: false,
                    ),
                    _ActivityRow(
                      theme: theme,
                      icon: IconsaxPlusBroken.sms,
                      text: 'New email · Fwd: School Management...',
                      time: '1 hour ago',
                      isLast: true,
                    ),
                  ],
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

class _AvailabilityButton extends StatelessWidget {
  const _AvailabilityButton(
      {required this.isAvailable, required this.onPressed});

  final bool isAvailable;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Semantics(
      button: true,
      toggled: isAvailable,
      label: isAvailable ? 'Agent available' : 'Agent unavailable',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: theme.alternate, width: 1),
            ),
            child: IconButton(
              tooltip: isAvailable
                  ? 'Available — tap to go unavailable'
                  : 'Unavailable — tap to go available',
              onPressed: onPressed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                IconsaxPlusBroken.headphone,
                size: 22,
                color: theme.primaryText,
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAvailable ? theme.success : theme.secondaryText,
                border: Border.all(
                  color: theme.primaryBackground,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.theme});

  final String text;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: theme.labelSmall.copyWith(
        color: theme.primaryText,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.theme,
    required this.title,
    required this.actionLabel,
    required this.onActionTap,
  });

  final FlutterFlowTheme theme;
  final String title;
  final String actionLabel;
  final VoidCallback onActionTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _SectionLabel(title, theme: theme),
        GestureDetector(
          onTap: onActionTap,
          child: Text(
            actionLabel,
            style: theme.bodySmall.copyWith(color: theme.primary),
          ),
        ),
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.theme,
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
  });

  final FlutterFlowTheme theme;
  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: theme.bodyMedium.copyWith(
                color: theme.primaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.bodyLarge.copyWith(
              color: theme.error,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: theme.secondaryText),
        ],
      ),
    );
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({
    required this.theme,
    required this.icon,
    required this.value,
    required this.label,
    this.overdueLabel,
    required this.onTap,
  });

  final FlutterFlowTheme theme;
  final IconData icon;
  final String value;
  final String label;
  final String? overdueLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.alternate),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: theme.headlineSmall.copyWith(
                    color: theme.primaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(icon, size: 18, color: theme.secondaryText),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.bodySmall.copyWith(color: theme.secondaryText),
            ),
            if (overdueLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                overdueLabel!,
                style: theme.bodySmall.copyWith(
                  color: theme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.theme,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final FlutterFlowTheme theme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
          foregroundColor: theme.primaryText,
          side: BorderSide(color: theme.alternate),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          backgroundColor: theme.primaryBackground),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: theme.bodySmall.copyWith(color: theme.primaryText)),
        ],
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({
    required this.theme,
    required this.ticketId,
    required this.status,
    required this.statusColor,
    required this.subject,
    required this.meta,
    required this.onTap,
  });

  final FlutterFlowTheme theme;
  final String ticketId;
  final String status;
  final Color statusColor;
  final String subject;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.alternate)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  ticketId,
                  style: theme.bodyMedium.copyWith(
                    color: theme.primaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  status,
                  style: theme.bodySmall.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subject,
              style: theme.bodySmall.copyWith(color: theme.secondaryText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              meta,
              style: theme.bodySmall
                  .copyWith(color: theme.secondaryText.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.theme,
    required this.icon,
    this.iconColor,
    required this.text,
    required this.time,
    required this.isLast,
  });

  final FlutterFlowTheme theme;
  final IconData icon;
  final Color? iconColor;
  final String text;
  final String time;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        border:
            isLast ? null : Border(bottom: BorderSide(color: theme.alternate)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor ?? theme.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: theme.bodySmall.copyWith(color: theme.primaryText),
                ),
                Text(
                  time,
                  style: theme.bodySmall.copyWith(
                    color: theme.secondaryText.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
