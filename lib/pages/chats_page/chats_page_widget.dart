import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../components/user_avatar/user_avatar.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../services/realtime/connection_monitor.dart';
import '../../services/realtime/realtime_event.dart';
import '../../services/realtime/realtime_service.dart';
import '../conversation_room_page/whatsapp_live_store.dart';
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
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(whatsAppInboxProvider.notifier).load();
    });
    _scrollController.addListener(_loadMoreWhenNeeded);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.dispose();
  }

  void _loadMoreWhenNeeded() {
    if (!_scrollController.hasClients ||
        ref.read(chatsPageProvider).channel != ChatChannel.whatsapp) {
      return;
    }
    if (_scrollController.position.extentAfter < 240) {
      ref.read(whatsAppInboxProvider.notifier).loadMore();
    }
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
    if (channel == ChatChannel.whatsapp) {
      ref.read(whatsAppInboxProvider.notifier).load();
    }
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
    if (state.channel == ChatChannel.whatsapp) {
      ref.read(whatsAppInboxProvider.notifier).load(
            status: selection.status,
            query: state.query,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatsPageProvider);
    final threads = ref.watch(conversationStoreProvider);
    final whatsApp = ref.watch(whatsAppInboxProvider);
    final online = ref.watch(connectionMonitorProvider);
    final connState = ref.watch(realtimeConnectionProvider).value;
    final theme = FlutterFlowTheme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    final filtersActive = state.type != ChatConversationType.all ||
        state.status != ChatConversationStatus.all;
    final showDegraded = state.channel == ChatChannel.whatsapp &&
        (!online || connState == RealtimeConnectionState.degraded);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: RefreshIndicator(
        onRefresh: () async {
          if (state.channel == ChatChannel.whatsapp) {
            await ref.read(whatsAppInboxProvider.notifier).load(
                  status: state.status,
                  query: state.query,
                );
          }
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _ChatsHeaderDelegate(
                theme: theme,
                topPadding: topPadding,
                subtitle:
                    state.channel == ChatChannel.whatsapp && whatsApp.total > 0
                        ? '${whatsApp.total} conversations${whatsApp.live ? ' · Live' : ''}'
                        : state.subtitle,
                searchActive: state.searchActive,
                filtersActive: filtersActive,
                onSearch: state.searchActive ? _closeSearch : _openSearch,
                onFilter: _openFilters,
              ),
            ),
            if (showDegraded)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                      color: theme.secondaryBackground,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Icon(Icons.cloud_off_outlined,
                        color: theme.secondaryText, size: 15),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                          online
                              ? 'Reconnecting live updates…'
                              : 'Offline — showing your last conversations',
                          style: TextStyle(
                              color: theme.secondaryText, fontSize: 12)),
                    ),
                    if (whatsApp.live)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: theme.primary, shape: BoxShape.circle),
                      ),
                  ]),
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
                      : 'Search Widget Chats',
                  onChanged: (value) {
                    ref.read(chatsPageProvider.notifier).setSearchQuery(value);
                    if (state.channel == ChatChannel.whatsapp) {
                      ref.read(whatsAppInboxProvider.notifier).load(
                            status: state.status,
                            query: value,
                          );
                    }
                  },
                  onClose: _closeSearch,
                  theme: theme,
                ),
              ),
            if (state.channel == ChatChannel.whatsapp)
              ..._whatsAppSliver(whatsApp, state, theme)
            else
              ..._conversationSliver(
                filterChatConversations(
                  threads.map((thread) => thread.conversation),
                  state,
                ),
                state,
                theme,
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _whatsAppSliver(
    WhatsAppInboxState inbox,
    ChatsPageState state,
    FlutterFlowTheme theme,
  ) {
    if (inbox.loading && inbox.threads.isEmpty) {
      return [const _WhatsAppInboxSkeleton()];
    }
    if (inbox.error != null && inbox.threads.isEmpty) {
      return [
        _ChatErrorState(
            theme: theme,
            onRetry: () => ref
                .read(whatsAppInboxProvider.notifier)
                .load(status: state.status, query: state.query))
      ];
    }
    if (inbox.threads.isEmpty) {
      return [
        _EmptyChats(
            theme: theme,
            label: state.query.trim().isEmpty
                ? 'No WhatsApp conversations yet'
                : 'No matching conversations')
      ];
    }
    return [
      if (inbox.isOffline)
        SliverToBoxAdapter(child: _OfflineBanner(theme: theme)),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        sliver: SliverList.builder(
          itemCount: inbox.threads.length + (inbox.loadingMore ? 3 : 0),
          itemBuilder: (context, index) {
            if (index >= inbox.threads.length) {
              return const _ConversationRowSkeleton();
            }
            final conversation = inbox.threads[index].conversation;
            return _ChatSwipeRow(
              key: ValueKey('whatsapp-${conversation.id}'),
              theme: theme,
              semanticsLabel:
                  '${conversation.name}, ${conversation.preview}, ${conversation.time}',
              onAction: () => _showComingSoon(context),
              onOpen: () => context.push('/chats/${conversation.id}'),
              child: _ConversationRow(conversation: conversation, theme: theme),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _conversationSliver(
    List<ChatConversation> conversations,
    ChatsPageState state,
    FlutterFlowTheme theme,
  ) {
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
              onOpen: () => context.push('/chats/${conversation.id}'),
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
                  label: 'Widget Chat',
                  selected: selected == ChatChannel.widgetChat,
                  onTap: () => onSelected(ChatChannel.widgetChat),
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
  Widget build(BuildContext context) => UserAvatar(
        imageUrl: conversation.avatarUrl,
        initials: conversation.avatar ?? conversation.initials,
        radius: 21,
        backgroundColor: theme.secondaryBackground,
        foregroundColor: theme.secondaryText,
        fontSize: 14,
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
    required this.onOpen,
    required this.semanticsLabel,
  });

  final FlutterFlowTheme theme;
  final Widget child;
  final VoidCallback onAction;
  final VoidCallback onOpen;
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
                  onTap: _offset == 0 ? widget.onOpen : _reset,
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

class _WhatsAppInboxSkeleton extends StatelessWidget {
  const _WhatsAppInboxSkeleton();
  @override
  Widget build(BuildContext context) => const SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
        sliver: SliverList(
          delegate: SliverChildListDelegate.fixed([
            _ConversationRowSkeleton(),
            _ConversationRowSkeleton(),
            _ConversationRowSkeleton(),
            _ConversationRowSkeleton(),
            _ConversationRowSkeleton(),
          ]),
        ),
      );
}

class _ConversationRowSkeleton extends StatelessWidget {
  const _ConversationRowSkeleton();
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final color = theme.alternate.withValues(alpha: .55);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          CircleAvatar(radius: 23, backgroundColor: color),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _SkeletonBar(color: color, width: 120, height: 13),
                const SizedBox(height: 9),
                _SkeletonBar(color: color, width: 188, height: 11),
              ])),
          const SizedBox(width: 12),
          _SkeletonBar(color: color, width: 28, height: 10),
        ]),
      ),
    );
  }
}

class _SkeletonBar extends StatefulWidget {
  const _SkeletonBar(
      {required this.color, required this.width, required this.height});
  final Color color;
  final double width;
  final double height;

  @override
  State<_SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<_SkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(widget.height),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (context, value) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            widget.color,
            widget.color.withValues(alpha: .32),
            widget.color
          ],
          stops: const [0, .5, 1],
          begin: Alignment(-1.5 + _controller.value * 3, 0),
          end: Alignment(-.5 + _controller.value * 3, 0),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _ChatErrorState extends StatelessWidget {
  const _ChatErrorState({required this.theme, required this.onRetry});
  final FlutterFlowTheme theme;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 42, 24, 20),
          child: Column(children: [
            Icon(Icons.cloud_off_outlined, color: theme.secondaryText),
            const SizedBox(height: 10),
            Text('Unable to load WhatsApp conversations',
                style: TextStyle(
                    color: theme.primaryText, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Check your connection and try again.',
                style: TextStyle(color: theme.secondaryText, fontSize: 13)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.theme});
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(Icons.cloud_off_outlined, color: theme.secondaryText, size: 16),
          const SizedBox(width: 7),
          Text('Offline — showing your last conversations',
              style: TextStyle(color: theme.secondaryText, fontSize: 12)),
        ]),
      );
}
