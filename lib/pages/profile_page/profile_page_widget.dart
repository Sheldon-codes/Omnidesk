import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../../models/auth/auth_models.dart';
import '../../services/auth_session_controller.dart';
import 'profile_page_model.dart';

export 'profile_page_model.dart';

class ProfilePageWidget extends ConsumerWidget {
  const ProfilePageWidget({super.key});

  static const routeName = 'ProfilePage';
  static const routePath = '/profile';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FlutterFlowTheme.of(context);
    final user = ref.watch(authSessionControllerProvider).session?.user;
    final presence = ref.watch(agentPresenceProvider);
    final appThemeMode = ref.watch(appThemeModeProvider);
    // `viewPadding` is the physical display cut-out/status-bar inset. Unlike
    // `padding`, it does not change when transient system UI changes, so the
    // pinned header cannot drift on Android gesture/navigation variants.
    final topInset = MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _ProfileHeaderDelegate(
              topInset: topInset,
              user: user,
              theme: theme,
              onBack: context.pop,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(label: 'Availability', theme: theme),
                  _SectionCard(
                    theme: theme,
                    children: [
                      _MenuTile(
                        icon: IconsaxPlusBroken.activity,
                        iconColor: _statusColor(presence.status, theme),
                        label: presence.status.label,
                        subtitle: presence.status.description,
                        theme: theme,
                        onTap: presence.isSaving
                            ? null
                            : () => _showAvailabilitySheet(context),
                        trailing: presence.isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                      ),
                      _ToggleTile(
                        icon: IconsaxPlusBroken.call,
                        label: 'Receive incoming calls',
                        subtitle: presence.receiveIncomingCalls
                            ? 'Calls can be routed to this device'
                            : 'Chats and tickets can still be routed to you',
                        value: presence.receiveIncomingCalls,
                        enabled: !presence.isSaving,
                        theme: theme,
                        onChanged: (enabled) => ref
                            .read(agentPresenceProvider.notifier)
                            .setReceiveIncomingCalls(enabled),
                      ),
                    ],
                  ),
                  if (presence.failure != null)
                    _FailureRow(
                      theme: theme,
                      onRetry: () =>
                          ref.read(agentPresenceProvider.notifier).retry(),
                    ),
                  _SectionHeader(label: 'Account', theme: theme),
                  _SectionCard(
                    theme: theme,
                    children: [
                      _MenuTile(
                        icon: IconsaxPlusBroken.lock,
                        label: 'Change password',
                        subtitle: 'Update your account security',
                        theme: theme,
                        onTap: () => context.push('/change-password'),
                      ),
                      if (user?.email.trim().isNotEmpty == true)
                        _MenuTile(
                          icon: IconsaxPlusBroken.sms,
                          label: 'Email',
                          subtitle: user!.email,
                          theme: theme,
                        ),
                      if (user?.phone?.trim().isNotEmpty == true)
                        _MenuTile(
                          icon: IconsaxPlusBroken.call,
                          label: 'Phone',
                          subtitle: user!.phone!,
                          theme: theme,
                        ),
                    ],
                  ),
                  _SectionHeader(label: 'Preferences', theme: theme),
                  _SectionCard(
                    theme: theme,
                    children: [
                      _MenuTile(
                        icon: Icons.brush_outlined,
                        label: 'App theme',
                        subtitle: _themeModeLabel(appThemeMode),
                        theme: theme,
                        onTap: () => _showThemeSheet(context),
                      ),
                    ],
                  ),
                  _SectionHeader(label: 'Workspace', theme: theme),
                  _SectionCard(
                    theme: theme,
                    children: [
                      _MenuTile(
                        icon: IconsaxPlusBroken.building_4,
                        label: user?.activeWorkspace?.name ??
                            'No active workspace',
                        subtitle: user?.activeWorkspace?.role ??
                            user?.role ??
                            'Agent',
                        theme: theme,
                      ),
                    ],
                  ),
                  _SectionHeader(label: 'Session', theme: theme),
                  _SectionCard(
                    theme: theme,
                    children: [
                      _MenuTile(
                        icon: IconsaxPlusBroken.logout,
                        iconColor: theme.error,
                        label: 'Sign out',
                        labelColor: theme.error,
                        theme: theme,
                        showArrow: false,
                        onTap: () => _confirmSignOut(context, ref),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAvailabilitySheet(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AvailabilitySheet(),
    );
  }

  Future<void> _showThemeSheet(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.secondaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ThemeSheet(),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You’ll stop receiving calls and assignments on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await ref.read(authSessionControllerProvider.notifier).logout();
    }
  }
}

class _ProfileHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ProfileHeaderDelegate({
    required this.topInset,
    required this.user,
    required this.theme,
    required this.onBack,
  });

  final double topInset;
  final AuthUser? user;
  final FlutterFlowTheme theme;
  final VoidCallback onBack;

  /// The cover finishes at the avatar midpoint. Keeping this relationship
  /// explicit prevents the profile identity from visually floating above or
  /// below the image when the status-bar inset changes between devices.
  static const _coverContentHeight = 202.0;
  static const _avatarSize = 112.0;

  @override
  double get minExtent => topInset + kToolbarHeight;

  @override
  double get maxExtent => topInset + 340;

  @override
  bool shouldRebuild(covariant _ProfileHeaderDelegate oldDelegate) =>
      oldDelegate.topInset != topInset ||
      oldDelegate.user != user ||
      oldDelegate.theme != theme;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final progress = (shrinkOffset / range).clamp(0.0, 1.0);
    final name = user?.displayName ?? 'Agent';
    final initials = user?.initials ?? 'A';
    final role = user?.role.trim().isNotEmpty == true ? user!.role : 'Agent';
    final workspace = user?.activeWorkspace?.name;
    final coverEnd = topInset + _coverContentHeight;
    final expandedAvatarTop = coverEnd - (_avatarSize / 2);
    final collapsedAvatarSize = 42.0;
    // The compact geometry is one safe toolbar coordinate system, mirroring
    // the customer editor header. No element has an independent status-bar
    // offset that could drift on a cut-out or Android navigation variant.
    final toolbarTop = minExtent - kToolbarHeight;
    final collapsedAvatarTop = toolbarTop + 7;

    return Material(
      color: theme.primaryBackground,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -shrinkOffset * .35,
            left: 0,
            right: 0,
            height: coverEnd + shrinkOffset,
            child: Opacity(
              opacity: 1 - progress,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=1200',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [theme.secondary, theme.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  // Deliberately shade only the status-bar edge. The lower
                  // edge remains true to the image and meets the avatar at
                  // its centre instead of dissolving into the page surface.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x80000000),
                          Color(0x24000000),
                          Color(0x00000000),
                        ],
                        stops: [0, .26, .56],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: toolbarTop + 4,
            child: _GlassIconButton(
              tooltip: 'Back',
              icon: IconsaxPlusBroken.arrow_left_2,
              onPressed: onBack,
            ),
          ),
          Positioned(
            top: lerpDouble(expandedAvatarTop, collapsedAvatarTop, progress)!,
            left: lerpDouble(
                24, MediaQuery.sizeOf(context).width - 58, progress)!,
            child: _Avatar(
              initials: initials,
              size: lerpDouble(_avatarSize, collapsedAvatarSize, progress)!,
              theme: theme,
            ),
          ),
          Positioned(
            top: lerpDouble(expandedAvatarTop + _avatarSize + 14,
                toolbarTop + 17, progress)!,
            left: lerpDouble(24, 62, progress)!,
            right: lerpDouble(20, 70, progress)!,
            child: Opacity(
              opacity: progress < .95 ? 1 : .96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.headlineMedium.override(
                      color: theme.primaryText,
                      fontSize: lerpDouble(28, 18, progress)!,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  if (progress < .82) ...[
                    const SizedBox(height: 3),
                    Text(
                      workspace == null || workspace.isEmpty
                          ? role
                          : '$role · $workspace',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          theme.bodyMedium.override(color: theme.secondaryText),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(
      {required this.initials, required this.size, required this.theme});
  final String initials;
  final double size;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.primary,
          border: Border.all(
              color: theme.primaryBackground, width: size > 60 ? 4 : 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: Text(initials,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * .34,
                  fontWeight: FontWeight.w800)),
        ),
      );
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton(
      {required this.tooltip, required this.icon, required this.onPressed});
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.white.withValues(alpha: .72),
            child: SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: tooltip,
                icon: Icon(icon, size: 21),
                onPressed: onPressed,
              ),
            ),
          ),
        ),
      );
}

class _AvailabilitySheet extends ConsumerWidget {
  const _AvailabilitySheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentPresenceProvider);
    return _ProfileSelectionSheetFrame(
      title: 'Set availability',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final status in PresenceStatus.values)
            _ProfileSelectionOption(
              icon: _availabilityIcon(status),
              title: status.label,
              subtitle: status.description,
              selected: status == state.status,
              enabled: !state.isSaving,
              onTap: () async {
                final changed = await ref
                    .read(agentPresenceProvider.notifier)
                    .setStatus(status);
                if (changed && context.mounted) Navigator.pop(context);
              },
            ),
          if (state.isSaving)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _ThemeSheet extends ConsumerWidget {
  const _ThemeSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appThemeModeProvider);
    return _ProfileSelectionSheetFrame(
      title: 'Select theme',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in ThemeMode.values)
            _ProfileSelectionOption(
              icon: _themeModeIcon(mode),
              title: _themeModeLabel(mode),
              subtitle: _themeModeDescription(mode),
              selected: mode == selected,
              onTap: () {
                ref.read(appThemeModeProvider.notifier).setThemeMode(mode);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}

/// Shared Dwellio-style selection surface: rounded at the top, a quiet title,
/// and simple icon rows with a checkmark for the active option.
class _ProfileSelectionSheetFrame extends StatelessWidget {
  const _ProfileSelectionSheetFrame({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                title,
                style: theme.headlineSmall.override(
                  color: theme.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProfileSelectionOption extends StatelessWidget {
  const _ProfileSelectionOption({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final foreground = selected ? theme.primary : theme.primaryText;
    final muted = theme.secondaryText;
    return Opacity(
      opacity: enabled ? 1 : .48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: selected ? theme.primary : muted, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.bodyLarge.override(
                          color: foreground,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.bodySmall
                              .override(color: theme.secondaryText),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: theme.primary, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.theme});
  final String label;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 7),
        child: Text(label,
            style: theme.bodyMedium.override(
                color: theme.secondaryText,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.theme, required this.children});
  final FlutterFlowTheme theme;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            border: Border.all(color: theme.alternate),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1)
                Divider(
                  height: 1,
                  indent: 64,
                  color: theme.alternate,
                ),
            ],
          ]),
        ),
      );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.theme,
    this.subtitle,
    this.iconColor,
    this.labelColor,
    this.trailing,
    this.onTap,
    this.showArrow = true,
  });
  final IconData icon;
  final String label;
  final FlutterFlowTheme theme;
  final String? subtitle;
  final Color? iconColor;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showArrow;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              SizedBox(
                width: 34,
                height: 34,
                child: Icon(icon, size: 22, color: iconColor ?? theme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: theme.bodyLarge.override(
                              color: labelColor ?? theme.primaryText,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodySmall
                                .override(color: theme.secondaryText)),
                      ],
                    ]),
              ),
              if (trailing != null)
                trailing!
              else if (showArrow && onTap != null)
                Icon(Icons.chevron_right, color: theme.secondaryText),
            ]),
          ),
        ),
      );
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.theme,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final bool enabled;
  final FlutterFlowTheme theme;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 22, color: theme.primary)),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: theme.bodyLarge.override(
                      color: theme.primaryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall.override(color: theme.secondaryText)),
            ]),
          ),
          Switch.adaptive(value: value, onChanged: enabled ? onChanged : null),
        ]),
      );
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.theme, required this.onRetry});
  final FlutterFlowTheme theme;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Expanded(
            child: Text('Could not update availability.',
                style: theme.bodySmall.override(color: theme.error)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      );
}

Color _statusColor(PresenceStatus status, FlutterFlowTheme theme) =>
    switch (status) {
      PresenceStatus.available => theme.success,
      PresenceStatus.busy => theme.warning,
      PresenceStatus.away => theme.secondaryText,
      PresenceStatus.offline => theme.error,
    };

IconData _availabilityIcon(PresenceStatus status) => switch (status) {
      PresenceStatus.available => Icons.check_circle_outline,
      PresenceStatus.busy => Icons.do_not_disturb_on_outlined,
      PresenceStatus.away => Icons.schedule_outlined,
      PresenceStatus.offline => Icons.power_settings_new_outlined,
    };

IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.auto_mode_outlined,
    };

String _themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System default',
    };

String _themeModeDescription(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'Always use the light appearance.',
      ThemeMode.dark => 'Always use the dark appearance.',
      ThemeMode.system => 'Match your device appearance.',
    };
