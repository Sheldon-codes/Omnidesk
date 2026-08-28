import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import 'phone_page_model.dart';

export 'phone_page_model.dart';

class PhonePageWidget extends ConsumerStatefulWidget {
  const PhonePageWidget({super.key});

  static const routeName = 'PhonePage';
  static const routePath = '/phone';

  @override
  ConsumerState<PhonePageWidget> createState() => _PhonePageWidgetState();
}

class _PhonePageWidgetState extends ConsumerState<PhonePageWidget> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    ref.read(phonePageProvider.notifier).openSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(phonePageProvider.notifier).closeSearch();
  }

  void _selectTab(PhoneTab tab) {
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(phonePageProvider.notifier).selectTab(tab);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phonePageProvider);
    final theme = FlutterFlowTheme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _PhoneHeaderDelegate(
              theme: theme,
              topPadding: topPadding,
              subtitle: state.subtitle,
              searchActive: state.searchActive,
              onSearch: state.searchActive ? _closeSearch : _openSearch,
              onAddContact: () => _showComingSoon(context),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PhoneTabsDelegate(
              theme: theme,
              selected: state.tab,
              onSelected: _selectTab,
            ),
          ),
          if (state.searchActive)
            SliverToBoxAdapter(
              child: _SearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: state.tab == PhoneTab.contacts
                    ? 'Search contacts'
                    : 'Search recent calls',
                onChanged: ref.read(phonePageProvider.notifier).setSearchQuery,
                onClose: _closeSearch,
                theme: theme,
              ),
            ),
          if (state.tab == PhoneTab.recents)
            ..._recentsSlivers(state, theme)
          else
            ..._contactSlivers(state, theme),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
      floatingActionButton: state.tab == PhoneTab.recents
          ? FloatingActionButton(
              tooltip: 'Open keypad',
              onPressed: () => _showComingSoon(context),
              backgroundColor: theme.primary,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              child: const Icon(Icons.dialpad_rounded),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  List<Widget> _recentsSlivers(
    PhonePageState state,
    FlutterFlowTheme theme,
  ) {
    final items = state.filteredRecents;
    if (items.isEmpty) {
      return [_EmptyResults(theme: theme, label: 'No recent calls found')];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          child: Text(
            'Today',
            style: theme.bodyMedium.override(
              fontFamily: theme.bodyMediumFamily,
              color: theme.secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final recent = items[index];
            return _PhoneSwipeRow(
              key: ValueKey('recent-${recent.phone}-${recent.time}'),
              theme: theme,
              semanticsLabel: '${recent.name}, ${recent.phone}, '
                  '${recent.time}, ${recent.detail}',
              onAction: () => _showComingSoon(context),
              child: _RecentRow(recent: recent, theme: theme),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _contactSlivers(
    PhonePageState state,
    FlutterFlowTheme theme,
  ) {
    final items = state.filteredContacts;
    if (items.isEmpty) {
      return [_EmptyResults(theme: theme, label: 'No contacts found')];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        sliver: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final contact = items[index];
            return _PhoneSwipeRow(
              key: ValueKey('contact-${contact.identifier}'),
              theme: theme,
              semanticsLabel: '${contact.title}, ${contact.subtitle}',
              onAction: () => _showComingSoon(context),
              child: _ContactRow(contact: contact, theme: theme),
            );
          },
        ),
      ),
    ];
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Coming soon')));
  }
}

class _PhoneHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PhoneHeaderDelegate({
    required this.theme,
    required this.topPadding,
    required this.subtitle,
    required this.searchActive,
    required this.onSearch,
    required this.onAddContact,
  });

  static const _toolbarHeight = 56.0;
  static const _expandedContentHeight = 65.0;

  final FlutterFlowTheme theme;
  final double topPadding;
  final String subtitle;
  final bool searchActive;
  final VoidCallback onSearch;
  final VoidCallback onAddContact;

  @override
  double get minExtent => topPadding + _toolbarHeight;

  @override
  double get maxExtent => minExtent + _expandedContentHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    const expandedFontSize = 32.0;
    const collapsedFontSize = 18.0;
    final titleScale = lerpDouble(
      1,
      collapsedFontSize / expandedFontSize,
      progress,
    )!;
    final expandedTop = topPadding + _toolbarHeight;
    final collapsedTop = topPadding + (_toolbarHeight - collapsedFontSize) / 2;
    final titleTop = lerpDouble(expandedTop, collapsedTop, progress)!;
    final subtitleOpacity = (1 - progress / .60).clamp(0.0, 1.0);

    return ColoredBox(
      color: theme.primaryBackground,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: topPadding,
            right: 8,
            height: _toolbarHeight,
            child: Row(
              children: [
                IconButton(
                  tooltip: searchActive ? 'Close search' : 'Search',
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: onSearch,
                  icon: Icon(
                    searchActive
                        ? IconsaxPlusBroken.close_circle
                        : IconsaxPlusBroken.search_normal_1,
                    color: theme.primaryText,
                    size: 22,
                  ),
                ),
                IconButton(
                  tooltip: 'Add contact',
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: onAddContact,
                  icon: Icon(IconsaxPlusBroken.user_add,
                      color: theme.primaryText, size: 22),
                ),
              ],
            ),
          ),
          Positioned(
            top: titleTop,
            left: 20,
            right: 108,
            child: Transform.scale(
              scale: titleScale,
              alignment: Alignment.topLeft,
              child: Text(
                'Phone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.titleLarge.override(
                  fontFamily: theme.titleLargeFamily,
                  color: theme.primaryText,
                  fontSize: expandedFontSize,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -.8,
                  lineHeight: 1,
                ),
              ),
            ),
          ),
          Positioned(
            top: topPadding + _toolbarHeight + 43,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Opacity(
                opacity: subtitleOpacity,
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyMedium.override(
                    fontFamily: theme.bodyMediumFamily,
                    color: theme.secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 1,
            child: Opacity(
              opacity: progress,
              child: ColoredBox(
                color: theme.alternate.withValues(alpha: .65),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PhoneHeaderDelegate oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.subtitle != subtitle ||
      oldDelegate.searchActive != searchActive ||
      oldDelegate.onSearch != onSearch ||
      oldDelegate.onAddContact != onAddContact;
}

class _PhoneTabsDelegate extends SliverPersistentHeaderDelegate {
  const _PhoneTabsDelegate({
    required this.theme,
    required this.selected,
    required this.onSelected,
  });

  final FlutterFlowTheme theme;
  final PhoneTab selected;
  final ValueChanged<PhoneTab> onSelected;

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      ColoredBox(
        color: theme.primaryBackground,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 220,
            height: 46,
            child: Row(
              children: [
                _PhoneTabButton(
                  label: 'Recents',
                  selected: selected == PhoneTab.recents,
                  onTap: () => onSelected(PhoneTab.recents),
                  theme: theme,
                ),
                _PhoneTabButton(
                  label: 'Contacts',
                  selected: selected == PhoneTab.contacts,
                  onTap: () => onSelected(PhoneTab.contacts),
                  theme: theme,
                ),
              ],
            ),
          ),
        ),
      );

  @override
  bool shouldRebuild(covariant _PhoneTabsDelegate oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.selected != selected ||
      oldDelegate.onSelected != onSelected;
}

class _PhoneTabButton extends StatelessWidget {
  const _PhoneTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: onTap,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? theme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                label,
                style: theme.bodyMedium.override(
                  fontFamily: theme.bodyMediumFamily,
                  color: selected ? theme.primary : theme.secondaryText,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onClose,
    required this.theme,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: 13, right: 4),
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.primary, width: 1.25),
          ),
          child: Row(
            children: [
              Icon(
                IconsaxPlusBroken.search_normal_1,
                color: theme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  onChanged: onChanged,
                  style: theme.bodyMedium.override(
                    fontFamily: theme.bodyMediumFamily,
                    color: theme.primaryText,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: hintText,
                    hintStyle: theme.bodyMedium.override(
                      fontFamily: theme.bodyMediumFamily,
                      color: theme.secondaryText,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close search',
                onPressed: onClose,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                icon: Icon(
                  IconsaxPlusBroken.close_circle,
                  color: theme.secondaryText,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      );
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.recent, required this.theme});

  final PhoneRecent recent;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    final missed = recent.direction == PhoneCallDirection.missed;
    final icon = switch (recent.direction) {
      PhoneCallDirection.missed => Icons.phone_missed_outlined,
      PhoneCallDirection.inbound => IconsaxPlusBroken.call_incoming,
      PhoneCallDirection.outbound => IconsaxPlusBroken.call_outgoing,
    };
    return _RowSurface(
      theme: theme,
      leading: Icon(
        icon,
        color: missed
            ? theme.error
            : recent.direction == PhoneCallDirection.outbound
                ? theme.success
                : theme.secondaryText,
        size: 19,
      ),
      title: recent.name,
      subtitle: '${recent.phone} · ${recent.time} · ${recent.detail}',
      trailing: recent.ticket == null
          ? null
          : Text(
              recent.ticket!,
              style: theme.bodySmall.override(
                fontFamily: theme.bodySmallFamily,
                color: theme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.theme});

  final PhoneContact contact;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => _RowSurface(
        theme: theme,
        leading: _ContactAvatar(contact: contact, theme: theme),
        title: contact.title,
        subtitle: contact.subtitle,
        trailing: contact.ticketCount == null
            ? null
            : _TicketCount(count: contact.ticketCount!, theme: theme),
      );
}

class _RowSurface extends StatelessWidget {
  const _RowSurface({
    required this.theme,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final FlutterFlowTheme theme;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          border: Border(bottom: BorderSide(color: theme.alternate)),
        ),
        child: Row(
          children: [
            SizedBox(width: 38, child: Center(child: leading)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium.override(
                      fontFamily: theme.bodyMediumFamily,
                      color: theme.primaryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall.override(
                      fontFamily: theme.bodySmallFamily,
                      color: theme.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        ),
      );
}

class _ContactAvatar extends StatelessWidget {
  const _ContactAvatar({required this.contact, required this.theme});

  final PhoneContact contact;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.accent1,
          shape: BoxShape.circle,
          border: Border.all(color: theme.alternate)
        ),
        child: Text(
          contact.avatar ?? contact.initials,
          style: theme.bodyMedium.override(
            fontFamily: theme.bodyMediumFamily,
            color: theme.primaryText,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _TicketCount extends StatelessWidget {
  const _TicketCount({required this.count, required this.theme});

  final int count;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$count',
          style: theme.bodySmall.override(
            fontFamily: theme.bodySmallFamily,
            color: theme.primaryText,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _PhoneSwipeRow extends StatefulWidget {
  const _PhoneSwipeRow({
    super.key,
    required this.theme,
    required this.child,
    required this.onAction,
    required this.semanticsLabel,
  });

  final FlutterFlowTheme theme;
  final Widget child;
  final VoidCallback onAction;
  final String semanticsLabel;

  @override
  State<_PhoneSwipeRow> createState() => _PhoneSwipeRowState();
}

class _PhoneSwipeRowState extends State<_PhoneSwipeRow> {
  static const _maxOffset = 144.0;
  double _offset = 0;

  void _reset() => setState(() => _offset = 0);

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Semantics(
      label: widget.semanticsLabel,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => setState(() {
          _offset = (_offset + details.delta.dx).clamp(-_maxOffset, _maxOffset);
        }),
        onHorizontalDragEnd: (_) => setState(() {
          _offset =
              _offset.abs() > _maxOffset * .45 ? _offset.sign * _maxOffset : 0;
        }),
        child: Stack(
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  _SwipeAction(
                    label: 'Call',
                    icon: IconsaxPlusBroken.call,
                    color: widget.theme.primary,
                    onTap: () {
                      _reset();
                      widget.onAction();
                    },
                  ),
                  _SwipeAction(
                    label: 'Message',
                    icon: IconsaxPlusBroken.messages,
                    color: widget.theme.secondary,
                    onTap: () {
                      _reset();
                      widget.onAction();
                    },
                  ),
                  const Spacer(),
                  _SwipeAction(
                    label: 'Message',
                    icon: IconsaxPlusBroken.messages,
                    color: widget.theme.secondary,
                    onTap: () {
                      _reset();
                      widget.onAction();
                    },
                  ),
                  _SwipeAction(
                    label: 'Call',
                    icon: IconsaxPlusBroken.call,
                    color: widget.theme.primary,
                    onTap: () {
                      _reset();
                      widget.onAction();
                    },
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: duration,
              transform: Matrix4.translationValues(_offset, 0, 0),
              child: Material(
                color: widget.theme.primaryBackground,
                child: InkWell(
                  onTap: _offset == 0 ? null : _reset,
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 72,
        child: Material(
          color: color,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.theme, required this.label});

  final FlutterFlowTheme theme;
  final String label;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.bodyMedium.override(
              fontFamily: theme.bodyMediumFamily,
              color: theme.secondaryText,
              fontSize: 13,
            ),
          ),
        ),
      );
}
