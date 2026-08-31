import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../components/home_app_bar/home_app_bar.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../services/auth_session_controller.dart';
import 'home_dashboard_store.dart';

export 'home_page_model.dart';

class HomePageWidget extends ConsumerWidget {
  const HomePageWidget({super.key});
  static const routeName = 'HomePage';
  static const routePath = '/home';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionControllerProvider).session!.user;
    final theme = FlutterFlowTheme.of(context);
    final dashboard = ref.watch(homeDashboardProvider);
    final stats = dashboard.stats;
    final greeting = stats?.greeting;
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
          onAvatarTap: () => context.push('/profile'),
          onNotificationTap: () {},
        ),
        actions: const [],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(homeDashboardProvider.notifier).load(force: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((greeting?.urgentCount ?? 0) > 0 ||
                    (stats?.overdue ?? greeting?.overdueCount ?? 0) > 0) ...[
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
                            iconColor: theme.warning,
                            title: 'Escalated',
                            count: greeting?.urgentCount ?? 0,
                            onTap: () =>
                                context.go('/tickets?filter=escalated'),
                          ),
                          const SizedBox(height: 10),
                          _AttentionRow(
                            theme: theme,
                            icon: IconsaxPlusBroken.clock,
                            iconColor: theme.error,
                            title: 'Overdue',
                            count:
                                stats?.overdue ?? greeting?.overdueCount ?? 0,
                            onTap: () => context.go('/tickets?filter=overdue'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
                _SectionLabel('Channels', theme: theme),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ChannelCell(
                        theme: theme,
                        icon: IconsaxPlusBroken.call,
                        value: '${stats?.channels.calls.total ?? 0}',
                        label:
                            'Calls · ${stats?.channels.calls.open ?? 0} open',
                        overdueLabel: stats == null
                            ? null
                            : '${stats.channels.calls.overdue} overdue',
                        onTap: () => context.go('/phone'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ChannelCell(
                        theme: theme,
                        icon: IconsaxPlusBroken.messages,
                        value:
                            '${(stats?.channels.whatsapp.total ?? 0) + (stats?.channels.widget.total ?? 0)}',
                        label: 'Chats · ${stats?.unreadMessages ?? 0} unread',
                        overdueLabel: stats == null
                            ? null
                            : '${stats.channels.whatsapp.overdue + stats.channels.widget.overdue} overdue',
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
                        value: '${stats?.channels.email.total ?? 0}',
                        label: 'Email · ${stats?.unreadMessages ?? 0} unread',
                        overdueLabel: stats == null
                            ? null
                            : '${stats.channels.email.overdue} overdue',
                        onTap: () => context.go('/email'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ChannelCell(
                        theme: theme,
                        icon: IconsaxPlusBroken.ticket,
                        value: '${stats?.myOpen ?? 0}',
                        label: 'Tickets · open',
                        overdueLabel:
                            stats == null ? null : '${stats.overdue} overdue',
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
                if (dashboard.tickets.isNotEmpty) ...[
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
                      children: dashboard.tickets
                          .take(3)
                          .map((ticket) => _TicketRow(
                                theme: theme,
                                ticketId: ticket.displayNumber,
                                status: ticket.isOverdue
                                    ? 'Overdue'
                                    : ticket.status,
                                statusColor: ticket.isOverdue
                                    ? theme.error
                                    : const {
                                        'resolved',
                                        'closed'
                                      }.contains(ticket.status.toLowerCase())
                                        ? theme.success
                                        : theme.secondaryText,
                                subject: ticket.subject,
                                meta:
                                    '${ticket.priority} · ${ticket.customerName}',
                                onTap: () =>
                                    context.push('/tickets/${ticket.id}'),
                              ))
                          .toList(growable: false),
                    ),
                  ),
                ],
                if ((stats?.recentCallers.isNotEmpty ?? false) ||
                    (stats?.recentCalls.isNotEmpty ?? false)) ...[
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
                        ...?stats?.recentCallers
                            .take(2)
                            .map((caller) => _ActivityRow(
                                  theme: theme,
                                  icon: IconsaxPlusBroken.call_incoming,
                                  text: '${caller.label} · ${caller.phone}',
                                  time:
                                      caller.timestamp?.toLocal().toString() ??
                                          'Recent',
                                  isLast: false,
                                )),
                        ...?stats?.recentCalls
                            .take(1)
                            .map((call) => _ActivityRow(
                                  theme: theme,
                                  icon: call.missed
                                      ? IconsaxPlusBroken.call_slash
                                      : IconsaxPlusBroken.call_incoming,
                                  iconColor: call.missed ? theme.error : null,
                                  text: call.label,
                                  time: call.timestamp?.toLocal().toString() ??
                                      'Recent',
                                  isLast: true,
                                )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
    required this.iconColor,
    required this.title,
    required this.count,
    required this.onTap,
  });

  final FlutterFlowTheme theme;
  final IconData icon;
  final Color iconColor;
  final String title;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
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
