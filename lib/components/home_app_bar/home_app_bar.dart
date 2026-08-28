import 'package:flutter/material.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../../models/auth/auth_models.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({
    super.key,
    required this.user,
    this.locationLabel = 'Your workspace',
    this.includeTopInset = true,
    this.isDetecting = false,
    this.showTapToSet = false,
    this.unreadCount = 0,
    this.onAvatarTap,
    this.leadingAction,
    this.onNotificationTap,
  });

  final AuthUser? user;
  final String locationLabel;
  final bool includeTopInset;
  final bool isDetecting;
  final bool showTapToSet;
  final int unreadCount;
  final VoidCallback? onAvatarTap;
  final Widget? leadingAction;
  final VoidCallback? onNotificationTap;

  @override
  Size get preferredSize => const Size.fromHeight(78);

  String get _firstName {
    final name = user?.displayName.trim() ?? '';
    if (name.isEmpty) return 'there';
    return name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final initials = user?.initials ?? '?';

    return Container(
      color: theme.secondaryBackground,
      padding: EdgeInsets.only(
        top: includeTopInset ? MediaQuery.of(context).padding.top : 0,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAvatarTap,
            child: _ProfileAvatar(theme: theme, initials: initials),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hi, $_firstName 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleSmall.override(
                    fontFamily: theme.titleSmallFamily,
                    color: theme.primaryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                _LocationRow(
                  theme: theme,
                  label: locationLabel,
                  isDetecting: isDetecting,
                  showTapToSet: showTapToSet,
                  onTap: showTapToSet ? onAvatarTap : null,
                ),
              ],
            ),
          ),
          if (leadingAction != null) ...[
            leadingAction!,
            const SizedBox(width: 8),
          ],
          _NotificationBell(
            theme: theme,
            unreadCount: unreadCount,
            onTap: onNotificationTap,
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.theme,
    required this.label,
    required this.isDetecting,
    required this.showTapToSet,
    this.onTap,
  });

  final FlutterFlowTheme theme;
  final String label;
  final bool isDetecting;
  final bool showTapToSet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        if (isDetecting)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(theme.secondaryText),
            ),
          )
        else
          Icon(
            Icons.location_on_outlined,
            size: 13,
            color: theme.secondaryText,
          ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall.override(
              fontFamily: theme.bodySmallFamily,
              color: theme.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (showTapToSet) ...[
          const SizedBox(width: 4),
          Text(
            '(tap to set)',
            style: theme.bodySmall.override(
              fontFamily: theme.bodySmallFamily,
              color: theme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );

    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.theme, required this.initials});

  final FlutterFlowTheme theme;
  final String initials;

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.alternate, width: 2),
          color: theme.primary.withValues(alpha: 0.12),
        ),
        child: Center(
          child: Text(
            initials,
            style: theme.titleSmall.override(
              fontFamily: theme.titleSmallFamily,
              fontWeight: FontWeight.w700,
              color: theme.primary,
              fontSize: 16,
            ),
          ),
        ),
      );
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({
    required this.theme,
    required this.unreadCount,
    this.onTap,
  });

  final FlutterFlowTheme theme;
  final int unreadCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Stack(
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
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Image.asset(
                'assets/images/notification.png',
                width: 22,
                height: 22,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.notifications_none_rounded,
                  color: theme.primaryText,
                  size: 22,
                ),
              ),
              onPressed: onTap ?? () {},
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: theme.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.primaryBackground,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      );
}
