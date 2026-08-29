import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import 'email_page_model.dart';

export 'email_page_model.dart';

class EmailPageWidget extends ConsumerStatefulWidget {
  const EmailPageWidget({super.key});

  static const routeName = 'EmailPage';
  static const routePath = '/email';

  @override
  ConsumerState<EmailPageWidget> createState() => _EmailPageWidgetState();
}

class _EmailPageWidgetState extends ConsumerState<EmailPageWidget> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _fabExtended = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    final extended =
        _scrollController.hasClients && _scrollController.offset < 20;
    if (extended != _fabExtended && mounted) {
      setState(() => _fabExtended = extended);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _openSearch() {
    ref.read(emailPageProvider.notifier).openSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(emailPageProvider.notifier).closeSearch();
  }

  void _selectFolder(EmailFolder folder) {
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(emailPageProvider.notifier).selectFolder(folder);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailPageProvider);
    final theme = FlutterFlowTheme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: _fabExtended
            ? FloatingActionButton.extended(
                key: const ValueKey('compose-extended'),
                tooltip: 'Compose email',
                onPressed: () => _showComingSoon(context),
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                icon: const Icon(IconsaxPlusBroken.edit_2),
                label: const Text('Compose'),
              )
            : FloatingActionButton(
                key: const ValueKey('compose-collapsed'),
                tooltip: 'Compose email',
                onPressed: () => _showComingSoon(context),
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                child: const Icon(IconsaxPlusBroken.edit_2),
              ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _EmailHeaderDelegate(
              theme: theme,
              topPadding: topPadding,
              subtitle: state.subtitle,
              searchActive: state.searchActive,
              onSearch: state.searchActive ? _closeSearch : _openSearch,
              onCompose: () => _showComingSoon(context),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _EmailTabsDelegate(
              theme: theme,
              selected: state.folder,
              onSelected: _selectFolder,
            ),
          ),
          if (state.searchActive)
            SliverToBoxAdapter(
              child: _EmailSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: ref.read(emailPageProvider.notifier).setSearchQuery,
                onClose: _closeSearch,
                theme: theme,
              ),
            ),
          _emailList(state, theme),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _emailList(EmailPageState state, FlutterFlowTheme theme) {
    final messages = state.filteredMessages;
    if (messages.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 44, 20, 20),
          child: Center(
            child: Text(
              state.query.trim().isEmpty
                  ? 'No messages in this folder'
                  : 'No matching messages',
              style: theme.bodyMedium.override(
                fontFamily: theme.bodyMediumFamily,
                color: theme.secondaryText,
              ),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      sliver: SliverList.builder(
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          return _EmailSwipeRow(
            key: ValueKey(
                '${message.sender}-${message.subject}-${message.time}'),
            theme: theme,
            onAction: () => _showComingSoon(context),
            child: _EmailRow(message: message, theme: theme),
          );
        },
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Coming soon')));
  }
}

class _EmailHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _EmailHeaderDelegate({
    required this.theme,
    required this.topPadding,
    required this.subtitle,
    required this.searchActive,
    required this.onSearch,
    required this.onCompose,
  });

  final FlutterFlowTheme theme;
  final double topPadding;
  final String subtitle;
  final bool searchActive;
  final VoidCallback onSearch;
  final VoidCallback onCompose;

  static const toolbarHeight = 56.0;
  static const expandedContentHeight = 65.0;

  @override
  double get minExtent => topPadding + toolbarHeight;

  @override
  double get maxExtent => minExtent + expandedContentHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final titleSize = lerpDouble(32, 18, progress)!;
    final titleTop = lerpDouble(
      topPadding + toolbarHeight,
      topPadding + (toolbarHeight - 18) / 2,
      progress,
    )!;
    final subtitleOpacity = (1 - progress / .60).clamp(0.0, 1.0);

    return ColoredBox(
      color: theme.primaryBackground,
      child: Stack(
        children: [
          Positioned(
            top: titleTop,
            left: 20,
            right: 70,
            child: Text(
              'Email',
              style: theme.displaySmall.override(
                fontFamily: theme.displaySmallFamily,
                color: theme.primaryText,
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
                lineHeight: 1,
              ),
            ),
          ),
          Positioned(
            top: topPadding + toolbarHeight + 43,
            left: 20,
            child: Opacity(
              opacity: subtitleOpacity,
              child: Text(
                subtitle,
                style: theme.titleMedium.override(
                  fontFamily: theme.titleMediumFamily,
                  color: theme.secondaryText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Positioned(
            top: topPadding,
            right: 52,
            height: toolbarHeight,
            child: IconButton(
              tooltip: 'Compose email',
              onPressed: onCompose,
              icon: Icon(
                Icons.edit_outlined,
                color: theme.primaryText,
                size: 21,
              ),
            ),
          ),
          Positioned(
            top: topPadding,
            right: 12,
            height: toolbarHeight,
            child: IconButton(
              tooltip: searchActive ? 'Close search' : 'Search email',
              onPressed: onSearch,
              icon: Icon(
                searchActive ? Icons.close : IconsaxPlusBroken.search_normal_1,
                color: theme.primaryText,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _EmailHeaderDelegate oldDelegate) =>
      subtitle != oldDelegate.subtitle ||
      searchActive != oldDelegate.searchActive ||
      theme != oldDelegate.theme;
}

class _EmailTabsDelegate extends SliverPersistentHeaderDelegate {
  const _EmailTabsDelegate({
    required this.theme,
    required this.selected,
    required this.onSelected,
  });

  final FlutterFlowTheme theme;
  final EmailFolder selected;
  final ValueChanged<EmailFolder> onSelected;

  @override
  double get minExtent => 54;

  @override
  double get maxExtent => 54;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    const items = [
      (EmailFolder.inbox, 'Inbox'),
      (EmailFolder.pending, 'Pending'),
      (EmailFolder.sent, 'Sent'),
      (EmailFolder.starred, 'Starred'),
      (EmailFolder.archived, 'Archived'),
    ];
    return ColoredBox(
      color: theme.primaryBackground,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 20, right: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _EmailTab(
                  label: item.$2,
                  selected: selected == item.$1,
                  theme: theme,
                  onTap: () => onSelected(item.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _EmailTabsDelegate oldDelegate) =>
      selected != oldDelegate.selected || theme != oldDelegate.theme;
}

class _EmailTab extends StatelessWidget {
  const _EmailTab({
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    label,
                    style: theme.bodyMedium.override(
                      fontFamily: theme.bodyMediumFamily,
                      color: selected ? theme.primary : theme.secondaryText,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 2,
                  width: selected ? 42 : 0,
                  color: theme.primary,
                ),
              ],
            ),
          ),
        ),
      );
}

class _EmailSearchField extends StatelessWidget {
  const _EmailSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
    required this.theme,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          onChanged: onChanged,
          style: theme.bodyMedium.override(
            fontFamily: theme.bodyMediumFamily,
            color: theme.primaryText,
          ),
          decoration: InputDecoration(
            hintText: 'Search email',
            hintStyle: theme.bodyMedium.override(
              fontFamily: theme.bodyMediumFamily,
              color: theme.secondaryText,
            ),
            prefixIcon: Icon(IconsaxPlusBroken.search_normal_1,
                color: theme.secondaryText, size: 19),
            suffixIcon: IconButton(
              tooltip: 'Close search',
              onPressed: onClose,
              icon: Icon(Icons.close, color: theme.secondaryText, size: 19),
            ),
            filled: true,
            fillColor: theme.secondaryBackground,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );
}

class _EmailRow extends StatelessWidget {
  const _EmailRow({required this.message, required this.theme});

  final EmailMessage message;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    final textColor = message.isRead ? theme.secondaryText : theme.primaryText;
    final weight = message.isRead ? FontWeight.w400 : FontWeight.w600;
    return Semantics(
      label: '${message.sender}, ${message.subject}, ${message.time}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium.override(
                        fontFamily: theme.bodyMediumFamily,
                        color: textColor,
                        fontWeight: weight,
                      )),
                  const SizedBox(height: 3),
                  Text(message.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium.override(
                        fontFamily: theme.bodyMediumFamily,
                        color: textColor,
                        fontWeight: weight,
                      )),
                  const SizedBox(height: 3),
                  Text(message.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall.override(
                        fontFamily: theme.bodySmallFamily,
                        color: theme.secondaryText,
                      )),
                  if (message.ticketId != null || message.label != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (message.ticketId != null)
                          Text(message.ticketId!,
                              style: theme.labelSmall.override(
                                fontFamily: theme.labelSmallFamily,
                                color: theme.primary,
                                fontWeight: FontWeight.w600,
                              )),
                        if (message.ticketId != null && message.label != null)
                          const SizedBox(width: 8),
                        if (message.label != null)
                          Text(message.label!,
                              style: theme.labelSmall.override(
                                fontFamily: theme.labelSmallFamily,
                                color: theme.secondaryText,
                              )),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(message.time,
                style: theme.labelSmall.override(
                  fontFamily: theme.labelSmallFamily,
                  color: message.isRead ? theme.secondaryText : theme.primary,
                  fontWeight:
                      message.isRead ? FontWeight.w400 : FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}

class _EmailSwipeRow extends StatefulWidget {
  const _EmailSwipeRow(
      {super.key,
      required this.theme,
      required this.onAction,
      required this.child});

  final FlutterFlowTheme theme;
  final VoidCallback onAction;
  final Widget child;

  @override
  State<_EmailSwipeRow> createState() => _EmailSwipeRowState();
}

class _EmailSwipeRowState extends State<_EmailSwipeRow>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 80.0;
  static const _snapDistance = 42.0;
  double _offset = 0;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    late final Animation<double> animation;
    animation = Tween<double>(begin: _offset, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    )..addListener(() => setState(() => _offset = animation.value));
    _controller
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                if (_offset > 0) ...[
                  SizedBox(
                    width: _actionWidth,
                    child: _SwipeAction(
                      label: 'Mark read',
                      icon: Icons.mark_email_read_outlined,
                      color: widget.theme.primary,
                      onTap: () {
                        _reset();
                        widget.onAction();
                      },
                    ),
                  ),
                  SizedBox(
                    width: _actionWidth,
                    child: _SwipeAction(
                      label: 'Archive',
                      icon: Icons.archive_outlined,
                      color: widget.theme.secondaryText,
                      onTap: () {
                        _reset();
                        widget.onAction();
                      },
                    ),
                  ),
                ],
                const Spacer(),
                if (_offset < 0) ...[
                  SizedBox(
                    width: _actionWidth,
                    child: _SwipeAction(
                      label: 'Archive',
                      icon: Icons.archive_outlined,
                      color: widget.theme.secondaryText,
                      onTap: () {
                        _reset();
                        widget.onAction();
                      },
                    ),
                  ),
                  SizedBox(
                    width: _actionWidth,
                    child: _SwipeAction(
                      label: 'Mark read',
                      icon: Icons.mark_email_read_outlined,
                      color: widget.theme.primary,
                      onTap: () {
                        _reset();
                        widget.onAction();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onHorizontalDragUpdate: (details) => setState(() {
              _offset = (_offset + details.delta.dx).clamp(-160.0, 160.0);
            }),
            onHorizontalDragEnd: (_) {
              if (_offset.abs() < _snapDistance) {
                _reset();
              } else {
                setState(() => _offset = _offset.sign * 160.0);
              }
            },
            onTap: _offset == 0 ? null : _reset,
            child: Transform.translate(
              offset: Offset(_offset, 0),
              child: ColoredBox(
                color: widget.theme.primaryBackground,
                child: Column(
                  children: [
                    widget.child,
                    Divider(height: 1, color: widget.theme.alternate)
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: .10),
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 9, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}
