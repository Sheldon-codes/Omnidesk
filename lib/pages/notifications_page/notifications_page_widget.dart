import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../components/omni_skeleton.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import 'notification_target_resolver.dart';
import 'notifications_models.dart';
import 'notifications_page_model.dart';

class NotificationsPageWidget extends ConsumerStatefulWidget {
  const NotificationsPageWidget({super.key});
  static const routeName = 'NotificationsPage';
  static const routePath = '/notifications';

  @override
  ConsumerState<NotificationsPageWidget> createState() =>
      _NotificationsPageWidgetState();
}

class _NotificationsPageWidgetState
    extends ConsumerState<NotificationsPageWidget> {
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final state = ref.watch(notificationsPageProvider);
    final notifier = ref.read(notificationsPageProvider.notifier);
    final groups = _groups(state.items);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: theme.primaryBackground,
              elevation: 0,
              leading: IconButton(
                tooltip: 'Back',
                onPressed: context.pop,
                icon: Icon(
                  IconsaxPlusBroken.arrow_left_2,
                  color: theme.primaryText,
                ),
              ),
              title: Text(
                'Notifications',
                style: theme.titleMedium.override(
                  color: theme.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              centerTitle: true,
              actions: [
                if (state.unreadCount > 0)
                  TextButton(
                    onPressed: notifier.markAllRead,
                    child: Text(
                      'Mark all read',
                      style: theme.bodySmall.override(color: theme.primary),
                    ),
                  ),
              ],
            ),
            if (state.loading && state.items.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverList.builder(
                  itemCount: 6,
                  itemBuilder: (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      OmniSkeleton(
                          width: 40,
                          height: 40,
                          circle: true,
                          baseTint: theme.alternate),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OmniSkeleton(
                                  width: 188,
                                  height: 13,
                                  baseTint: theme.alternate),
                              const SizedBox(height: 8),
                              OmniSkeleton(
                                  width: 180,
                                  height: 11,
                                  baseTint: theme.alternate),
                              const SizedBox(height: 7),
                              OmniSkeleton(
                                  width: 72,
                                  height: 10,
                                  baseTint: theme.alternate),
                            ]),
                      ),
                    ]),
                  ),
                ),
              )
            else if (state.error != null && state.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _StateMessage(
                  title: 'Could not load notifications',
                  action: 'Retry',
                  onTap: notifier.refresh,
                ),
              )
            else if (groups.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _StateMessage(title: 'You’re all caught up'),
              )
            else
              for (final group in groups)
                SliverList.builder(
                  itemCount: group.items.length + 1,
                  itemBuilder: (_, index) => index == 0
                      ? _GroupHeader(label: group.label)
                      : _NotificationTile(
                          item: group.items[index - 1],
                          onTap: () => _open(group.items[index - 1], notifier),
                          onDismiss: () =>
                              notifier.dismiss(group.items[index - 1]),
                        ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(
    AppNotification item,
    NotificationsPageNotifier notifier,
  ) async {
    await notifier.markRead(item);
    if (!mounted) return;
    context.push(notificationRoute(item));
  }
}

class _Group {
  const _Group(this.label, this.items);
  final String label;
  final List<AppNotification> items;
}

List<_Group> _groups(List<AppNotification> items) {
  final today = <AppNotification>[];
  final earlier = <AppNotification>[];
  final start = DateTime.now();
  final day = DateTime(start.year, start.month, start.day);
  for (final item in items) {
    final date = item.createdAt?.toLocal();
    if (date != null && !date.isBefore(day)) {
      today.add(item);
    } else {
      earlier.add(item);
    }
  }
  return [
    if (today.isNotEmpty) _Group('Today', today),
    if (earlier.isNotEmpty) _Group('Earlier', earlier),
  ];
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(
          label.toUpperCase(),
          style: FlutterFlowTheme.of(context).bodySmall.override(
                color: FlutterFlowTheme.of(context).secondaryText,
                fontWeight: FontWeight.w600,
                letterSpacing: .8,
              ),
        ),
      );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onTap,
    required this.onDismiss,
  });
  final AppNotification item;
  final VoidCallback onTap;
  final Future<void> Function() onDismiss;
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await onDismiss();
        return false;
      },
      background: Container(
        color: theme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(IconsaxPlusBroken.trash, color: Colors.white),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        leading: CircleAvatar(
          backgroundColor: item.severity == 'danger'
              ? theme.error.withValues(alpha: .12)
              : theme.primary.withValues(alpha: .12),
          child: Icon(
            item.severity == 'danger'
                ? IconsaxPlusBroken.danger
                : IconsaxPlusBroken.notification,
            color: item.severity == 'danger' ? theme.error : theme.primary,
            size: 20,
          ),
        ),
        title: Text(
          item.title,
          style: theme.bodyMedium.override(
            color: theme.primaryText,
            fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
        subtitle: Text(
          item.body,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.bodySmall.override(color: theme.secondaryText),
        ),
        trailing: item.isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.primary,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            if (action != null)
              TextButton(onPressed: onTap, child: Text(action!)),
          ],
        ),
      );
}
