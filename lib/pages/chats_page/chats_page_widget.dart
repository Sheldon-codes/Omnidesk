import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import 'chats_page_model.dart';

export 'chats_page_model.dart';

class ChatsPageWidget extends ConsumerStatefulWidget {
  const ChatsPageWidget({super.key});

  static const routeName = 'ChatsPage';
  static const routePath = '/chats';

  @override
  ConsumerState<ChatsPageWidget> createState() => _ChatsPageWidgetState();
}

class _ChatsPageWidgetState extends ConsumerState<ChatsPageWidget> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    ref.read(chatsPageProvider.notifier).openSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(chatsPageProvider.notifier).closeSearch();
  }

  void _selectChannel(ChatChannel channel) {
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(chatsPageProvider.notifier).selectChannel(channel);
  }

  Future<void> _openFilters() async {
    final state = ref.read(chatsPageProvider);
    final selection = await showModalBottomSheet<ChatFilterSelection>(
      context: context,
      showDragHandle: true,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      builder: (context) => _ChatFilterSheet(
        initial: state.filterSelection,
        theme: FlutterFlowTheme.of(context),
      ),
    );
    if (!mounted || selection == null) return;
    ref.read(chatsPageProvider.notifier).applyFilters(
          type: selection.type,
          status: selection.status,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatsPageProvider);
    final theme = FlutterFlowTheme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    final filtersActive = state.type != ChatConversationType.all ||
        state.status != ChatConversationStatus.all;

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _ChatsHeaderDelegate(
              theme: theme,
              topPadding: topPadding,
              subtitle: state.subtitle,
              searchActive: state.searchActive,
              filtersActive: filtersActive,
              onSearch: state.searchActive ? _closeSearch : _openSearch,
              onFilter: _openFilters,
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _ChatsTabsDelegate(
              theme: theme,
              selected: state.channel,
              onSelected: _selectChannel,
            ),
          ),
          if (state.searchActive)
            SliverToBoxAdapter(
              child: _SearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: state.channel == ChatChannel.whatsapp
                    ? 'Search WhatsApp chats'
                    : 'Search live chats',
                onChanged: ref.read(chatsPageProvider.notifier).setSearchQuery,
                onClose: _closeSearch,
                theme: theme,
              ),
            ),
          ..._conversationSliver(state, theme),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  List<Widget> _conversationSliver(
    ChatsPageState state,
    FlutterFlowTheme theme,
  ) {
    final conversations = state.filteredConversations;
    if (conversations.isEmpty) {
      return [
        _EmptyChats(
          theme: theme,
          label: state.query.trim().isEmpty
              ? 'No conversations found'
              : 'No matching conversations',
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        sliver: SliverList.builder(
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            final conversation = conversations[index];
            return _ChatSwipeRow(
              key: ValueKey(
                '${conversation.channel}-${conversation.name}-${conversation.time}',
              ),
              theme: theme,
              semanticsLabel:
                  '${conversation.name}, ${conversation.preview}, ${conversation.time}',
              onAction: () => _showComingSoon(context),
              child: _ConversationRow(
                conversation: conversation,
                theme: theme,
              ),
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

class _ChatsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ChatsHeaderDelegate({
    required this.theme,
    required this.topPadding,
    required this.subtitle,
    required this.searchActive,
    required this.filtersActive,
    required this.onSearch,
    required this.onFilter,
  });

  static const _toolbarHeight = 56.0;
  static const _expandedContentHeight = 65.0;

  final FlutterFlowTheme theme;
  final double topPadding;
  final String subtitle;
  final bool searchActive;
  final bool filtersActive;
  final VoidCallback onSearch;
  final VoidCallback onFilter;

  @override
  double get minExtent => topPadding + _toolbarHeight;

  @override
  double get maxExtent => minExtent + _expandedContentHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
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
                  onPressed: onSearch,
                  icon: Icon(
                    searchActive
                        ? IconsaxPlusBroken.close_circle
                        : IconsaxPlusBroken.search_normal_1,
                    color: theme.primaryText,
                    size: 21,
                  ),
                ),
                IconButton(
                  tooltip: 'Filter conversations',
                  onPressed: onFilter,
                  icon: Icon(
                    IconsaxPlusBroken.setting_4,
                    color: filtersActive ? theme.primary : theme.primaryText,
                    size: 21,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: titleTop,
            left: 20,
            right: 112,
            child: Transform.scale(
              scale: titleScale,
              alignment: Alignment.topLeft,
              child: Text(
                'Chats',
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
              child: ColoredBox(color: theme.alternate.withValues(alpha: .65)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ChatsHeaderDelegate oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.subtitle != subtitle ||
      oldDelegate.searchActive != searchActive ||
      oldDelegate.filtersActive != filtersActive ||
      oldDelegate.onSearch != onSearch ||
      oldDelegate.onFilter != onFilter;
}

class _ChatsTabsDelegate extends SliverPersistentHeaderDelegate {
  const _ChatsTabsDelegate({
    required this.theme,
    required this.selected,
    required this.onSelected,
  });

  final FlutterFlowTheme theme;
  final ChatChannel selected;
  final ValueChanged<ChatChannel> onSelected;

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(
        color: theme.primaryBackground,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 220,
            height: 46,
            child: Row(
              children: [
                _ChatTabButton(
                  label: 'WhatsApp',
                  selected: selected == ChatChannel.whatsapp,
                  onTap: () => onSelected(ChatChannel.whatsapp),
                  theme: theme,
                ),
                _ChatTabButton(
                  label: 'Live Chat',
                  selected: selected == ChatChannel.liveChat,
                  onTap: () => onSelected(ChatChannel.liveChat),
                  theme: theme,
                ),
              ],
            ),
          ),
        ),
      );

  @override
  bool shouldRebuild(covariant _ChatsTabsDelegate oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.selected != selected ||
      oldDelegate.onSelected != onSelected;
}

class _ChatTabButton extends StatelessWidget {
  const _ChatTabButton({
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
              Icon(IconsaxPlusBroken.search_normal_1,
                  color: theme.primary, size: 18),
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
                      fontSize: 13),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: hintText,
                    hintStyle: theme.bodyMedium.override(
                        fontFamily: theme.bodyMediumFamily,
                        color: theme.secondaryText,
                        fontSize: 13),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close search',
                onPressed: onClose,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                icon: Icon(IconsaxPlusBroken.close_circle,
                    color: theme.secondaryText, size: 19),
              ),
            ],
          ),
        ),
      );
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation, required this.theme});

  final ChatConversation conversation;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          border: Border(bottom: BorderSide(color: theme.alternate)),
        ),
        child: Row(
          children: [
            _Avatar(conversation: conversation, theme: theme),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.name,
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
                    conversation.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall.override(
                      fontFamily: theme.bodySmallFamily,
                      color: theme.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                  if (conversation.ticketId != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      conversation.ticketId!,
                      style: theme.bodySmall.override(
                        fontFamily: theme.bodySmallFamily,
                        color: theme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  conversation.time,
                  style: theme.bodySmall.override(
                    fontFamily: theme.bodySmallFamily,
                    color: theme.secondaryText,
                    fontSize: 11,
                  ),
                ),
                if (conversation.unreadCount > 0) ...[
                  const SizedBox(height: 7),
                  _UnreadCount(
                    count: conversation.unreadCount,
                    theme: theme,
                  ),
                ],
              ],
            ),
          ],
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.conversation, required this.theme});

  final ChatConversation conversation;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          shape: BoxShape.circle,
        ),
        child: Text(
          conversation.avatar ?? conversation.initials,
          style: theme.bodyMedium.override(
            fontFamily: theme.bodyMediumFamily,
            color: theme.secondaryText,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _UnreadCount extends StatelessWidget {
  const _UnreadCount({required this.count, required this.theme});

  final int count;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: theme.primary,
          shape: BoxShape.circle,
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: theme.labelSmall.override(
            fontFamily: theme.labelSmallFamily,
            color: theme.primaryBackground,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _ChatSwipeRow extends StatefulWidget {
  const _ChatSwipeRow({
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
  State<_ChatSwipeRow> createState() => _ChatSwipeRowState();
}

class _ChatSwipeRowState extends State<_ChatSwipeRow> {
  static const _maxOffset = 144.0;
  double _offset = 0;

  void _reset() => setState(() => _offset = 0);

  Widget _action(String label, IconData icon, Color color) => _SwipeAction(
        label: label,
        icon: icon,
        color: color,
        onTap: () {
          _reset();
          widget.onAction();
        },
      );

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
                  _action('Mark read', Icons.mark_email_read_outlined,
                      widget.theme.primary),
                  _action('Archive', Icons.archive_outlined,
                      widget.theme.secondary),
                  const Spacer(),
                  _action('Archive', Icons.archive_outlined,
                      widget.theme.secondary),
                  _action('Mark read', Icons.mark_email_read_outlined,
                      widget.theme.primary),
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
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ChatFilterSheet extends StatefulWidget {
  const _ChatFilterSheet({required this.initial, required this.theme});

  final ChatFilterSelection initial;
  final FlutterFlowTheme theme;

  @override
  State<_ChatFilterSheet> createState() => _ChatFilterSheetState();
}

class _ChatFilterSheetState extends State<_ChatFilterSheet> {
  late ChatConversationType _type = widget.initial.type;
  late ChatConversationStatus _status = widget.initial.status;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filter conversations',
                  style: widget.theme.titleMedium.override(
                      fontFamily: widget.theme.titleMediumFamily,
                      color: widget.theme.primaryText,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              _FilterSectionLabel(
                  label: 'Conversation type', theme: widget.theme),
              _FilterChoice<ChatConversationType>(
                value: ChatConversationType.all,
                selected: _type,
                label: 'All',
                onSelected: (value) => setState(() => _type = value),
                theme: widget.theme,
              ),
              _FilterChoice<ChatConversationType>(
                value: ChatConversationType.dms,
                selected: _type,
                label: 'DMs',
                onSelected: (value) => setState(() => _type = value),
                theme: widget.theme,
              ),
              _FilterChoice<ChatConversationType>(
                value: ChatConversationType.groups,
                selected: _type,
                label: 'Groups',
                onSelected: (value) => setState(() => _type = value),
                theme: widget.theme,
              ),
              const SizedBox(height: 10),
              _FilterSectionLabel(label: 'Status', theme: widget.theme),
              _FilterChoice<ChatConversationStatus>(
                value: ChatConversationStatus.all,
                selected: _status,
                label: 'All',
                onSelected: (value) => setState(() => _status = value),
                theme: widget.theme,
              ),
              _FilterChoice<ChatConversationStatus>(
                value: ChatConversationStatus.open,
                selected: _status,
                label: 'Open',
                onSelected: (value) => setState(() => _status = value),
                theme: widget.theme,
              ),
              _FilterChoice<ChatConversationStatus>(
                value: ChatConversationStatus.resolved,
                selected: _status,
                label: 'Resolved',
                onSelected: (value) => setState(() => _status = value),
                theme: widget.theme,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const ChatFilterSelection(
                        type: ChatConversationType.all,
                        status: ChatConversationStatus.all,
                      ),
                    ),
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      ChatFilterSelection(type: _type, status: _status),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel({required this.label, required this.theme});

  final String label;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(label,
            style: theme.bodySmall.override(
                fontFamily: theme.bodySmallFamily,
                color: theme.secondaryText,
                fontWeight: FontWeight.w600)),
      );
}

class _FilterChoice<T> extends StatelessWidget {
  const _FilterChoice({
    required this.value,
    required this.selected,
    required this.label,
    required this.onSelected,
    required this.theme,
  });

  final T value;
  final T selected;
  final String label;
  final ValueChanged<T> onSelected;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onSelected(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Icon(
                value == selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: value == selected ? theme.primary : theme.secondaryText,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(label,
                  style: theme.bodyMedium.override(
                      fontFamily: theme.bodyMediumFamily,
                      color: theme.primaryText,
                      fontSize: 14)),
            ],
          ),
        ),
      );
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.theme, required this.label});

  final FlutterFlowTheme theme;
  final String label;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Text(label,
              textAlign: TextAlign.center,
              style: theme.bodyMedium.override(
                  fontFamily: theme.bodyMediumFamily,
                  color: theme.secondaryText,
                  fontSize: 13)),
        ),
      );
}
