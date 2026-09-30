import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../components/call_experience/call_session_controller.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../services/calls/call_log_store.dart';
import '../customer_details_page/customer_details_page_widget.dart';
import '../customer_editor_page/customer_editor_page_model.dart';
import 'phone_dial_pad_widget.dart';
import 'phone_page_model.dart';

export 'phone_page_model.dart';
export 'phone_dial_pad_widget.dart';

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
      body: state.viewMode == PhoneViewMode.dialPad
          ? PhoneDialPadWidget(
              state: state,
              theme: theme,
              onBack: ref.read(phonePageProvider.notifier).closeDialPad,
              onDigit: ref.read(phonePageProvider.notifier).appendDigit,
              onDelete: ref.read(phonePageProvider.notifier).deleteLastDigit,
              onClear: ref.read(phonePageProvider.notifier).clearDialedNumber,
              onCall: () => _handleDialCall(context),
            )
          : RefreshIndicator(
              onRefresh: ref.read(callLogStoreProvider.notifier).refresh,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (state.tab == PhoneTab.recents &&
                      state.historyHasMore &&
                      notification.metrics.extentAfter < 200) {
                    ref.read(callLogStoreProvider.notifier).loadMore();
                  }
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PhoneHeaderDelegate(
                        theme: theme,
                        topPadding: topPadding,
                        subtitle: state.subtitle,
                        searchActive: state.searchActive,
                        onSearch:
                            state.searchActive ? _closeSearch : _openSearch,
                        onAddContact: () => context.push('/customers/new'),
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
                          onChanged: ref
                              .read(phonePageProvider.notifier)
                              .setSearchQuery,
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
              ),
            ),
      floatingActionButton:
          state.viewMode == PhoneViewMode.list && state.tab == PhoneTab.recents
              ? FloatingActionButton(
                  tooltip: 'Open keypad',
                  onPressed: () =>
                      ref.read(phonePageProvider.notifier).openDialPad(),
                  backgroundColor: theme.primary,
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  child: const Icon(Icons.dialpad_rounded),
                )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _handleDialCall(BuildContext context) {
    final state = ref.read(phonePageProvider);
    if (state.dialedNumber.isEmpty) {
      _showSnack(context, 'Enter a phone number');
      return;
    }
    final contact = state.matchedContact;
    final started = _startOutgoing(
      context,
      CallParty(
        customerId: contact?.id,
        displayName: contact?.title ?? state.dialedNumber,
        phoneNumber: state.dialedNumber,
        avatar: contact?.avatar,
      ),
    );
    if (started) ref.read(phonePageProvider.notifier).closeDialPad();
  }

  bool _startOutgoing(BuildContext context, CallParty party) {
    final started =
        ref.read(callSessionControllerProvider.notifier).startOutgoing(party);
    if (!started) {
      final call = ref.read(callSessionControllerProvider);
      _showSnack(context, call.failureMessage ?? 'Call already in progress');
    }
    return started;
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<Widget> _recentsSlivers(
    PhonePageState state,
    FlutterFlowTheme theme,
  ) {
    final items = state.filteredRecents;
    final isSearching = state.query.trim().isNotEmpty;
    if (state.historyLoading && items.isEmpty) {
      return [_CallHistorySkeleton(theme: theme)];
    }
    if (state.historyError != null && items.isEmpty) {
      return [
        _CallHistoryError(
          theme: theme,
          message: state.historyError!,
          onRetry: ref.read(callLogStoreProvider.notifier).refresh,
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        _EmptyResults(
          theme: theme,
          label: isSearching ? 'No recent calls found' : 'No recent calls yet',
          description: isSearching
              ? 'Try a different phone number or contact name.'
              : 'Completed calls will appear here when call history is available.',
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          child: Text(
            'Recent calls',
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
              onPlay: () => _openRecording(context, recent),
              onTap: () => _openCallContact(context, recent),
              showPlayAction: recent.hasRecording,
              recordingOnlySwipe: true,
              child: _RecentRow(
                recent: recent,
                theme: theme,
                onCall: () => _startOutgoing(
                  context,
                  CallParty(
                    customerId: recent.customerId,
                    displayName: recent.name,
                    phoneNumber: recent.phone,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      if (state.historyLoadingMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.primary,
                ),
              ),
            ),
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
              onEdit: () => context
                  .push('/customers/${contact.id ?? contact.identifier}/edit'),
              onTap: () => context
                  .push('/customers/${contact.id ?? contact.identifier}'),
              child: _ContactRow(
                contact: contact,
                theme: theme,
                onCall: () => _startOutgoing(
                  context,
                  CallParty(
                    customerId: contact.id,
                    displayName: contact.title,
                    phoneNumber: contact.identifier,
                    avatar: contact.avatar,
                  ),
                ),
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

  void _openRecording(BuildContext context, PhoneRecent recent) {
    final recordingUrl = recent.recordingUrl;
    if (recordingUrl == null || !recent.hasRecording) return;
    final theme = FlutterFlowTheme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints.tightFor(
        width: MediaQuery.sizeOf(context).width,
      ),
      backgroundColor: theme.primaryBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PhoneRecordingSheet(
        title: recent.name,
        subtitle: '${recent.phone} · ${recent.detail}',
        recordingUrl: recordingUrl,
      ),
    );
  }

  void _openCallContact(BuildContext context, PhoneRecent recent) {
    final customerId = recent.customerId?.trim();
    final hasLinkedCustomer = customerId != null && customerId.isNotEmpty;
    // Keep unlinked callers local to this detail screen: a placeholder ID
    // must never cause an accidental GET/PUT against /customers.
    final detailId = hasLinkedCustomer
        ? customerId
        : 'call-contact-${recent.callLogId ?? recent.phone.hashCode}';
    final customer = CustomerRecord(
      id: detailId,
      name: recent.name,
      phone: recent.phone,
      email: recent.customerEmail ?? '',
    );
    final call = CustomerDetailCallLog(
      id: recent.callLogId ?? detailId,
      direction: recent.directionValue ?? recent.direction.name,
      status: recent.statusValue ?? 'unknown',
      fromNumber: recent.fromNumber ?? '',
      toNumber: recent.toNumber ?? '',
      durationSeconds: recent.durationSeconds,
      recordingUrl: recent.recordingUrl,
      transcript: recent.transcript,
      ticketId: recent.ticketId,
      ticketNumber: recent.ticket,
      ticketSubject: recent.ticketSubject,
      agentName: recent.agentName,
      createdAt: recent.occurredAt,
      endedAt: recent.endedAt,
    );
    context.push(
      '/customers/${Uri.encodeComponent(detailId)}',
      extra: CustomerDetailsRouteData(
        initialCustomer: customer,
        initialCallLog: call,
        loadRemoteProfile: hasLinkedCustomer,
      ),
    );
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
  const _RecentRow({
    required this.recent,
    required this.theme,
    required this.onCall,
  });

  final PhoneRecent recent;
  final FlutterFlowTheme theme;
  final VoidCallback onCall;

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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recent.ticket != null)
            Text(
              recent.ticket!,
              style: theme.bodySmall.override(
                fontFamily: theme.bodySmallFamily,
                color: theme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (recent.ticket != null) const SizedBox(width: 6),
          _CallButton(theme: theme, onTap: onCall),
        ],
      ),
    );
  }
}

class _PhoneRecordingSheet extends StatefulWidget {
  const _PhoneRecordingSheet({
    required this.title,
    required this.subtitle,
    required this.recordingUrl,
  });

  final String title;
  final String subtitle;
  final String recordingUrl;

  @override
  State<_PhoneRecordingSheet> createState() => _PhoneRecordingSheetState();
}

class _PhoneRecordingSheetState extends State<_PhoneRecordingSheet> {
  final _player = AudioPlayer();
  var _prepared = false;
  var _playing = false;
  var _loading = false;
  String? _error;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    unawaited(_configureAudioOutput());
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
    _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _player.durationStream.listen((duration) {
      if (mounted && duration != null) setState(() => _duration = duration);
    });
  }

  Future<void> _configureAudioOutput() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _player.setVolume(1.0);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (!_prepared) {
        setState(() {
          _loading = true;
          _error = null;
        });
        await _configureAudioOutput();
        await _player.setUrl(widget.recordingUrl);
        if (!mounted) return;
        setState(() {
          _prepared = true;
          _loading = false;
        });
      }
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load this call recording.';
      });
    }
  }

  Future<void> _skipBy(Duration amount) async {
    if (!_prepared || _duration <= Duration.zero) return;
    final next = _position + amount;
    await _player.seek(next.isNegative
        ? Duration.zero
        : next > _duration
            ? _duration
            : next);
  }

  Future<void> _seekFromWaveform(double value) async {
    if (_duration <= Duration.zero) return;
    await _player.seek(_duration * value.clamp(0, 1));
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final progress = _duration <= Duration.zero
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.titleMedium.override(
                  fontFamily: theme.titleMediumFamily,
                  color: theme.primaryText,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 4),
            Text(widget.subtitle,
                style: theme.bodySmall.override(
                  fontFamily: theme.bodySmallFamily,
                  color: theme.secondaryText,
                )),
            const SizedBox(height: 28),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final width = context.size?.width ?? 1;
                unawaited(_seekFromWaveform(details.localPosition.dx / width));
              },
              child: SizedBox(
                height: 78,
                width: double.infinity,
                child: CustomPaint(
                  painter: _RecordingWaveformPainter(
                    progress: progress,
                    activeColor: theme.primary,
                    inactiveColor: theme.alternate,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_position), style: theme.bodySmall),
                Text(_formatDuration(_duration), style: theme.bodySmall),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Back 10 seconds',
                  onPressed: _prepared
                      ? () => _skipBy(const Duration(seconds: -10))
                      : null,
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                const SizedBox(width: 18),
                IconButton.filled(
                  tooltip: _playing ? 'Pause recording' : 'Play recording',
                  onPressed: _toggle,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(64, 64),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 18),
                IconButton(
                  tooltip: 'Forward 10 seconds',
                  onPressed: _prepared
                      ? () => _skipBy(const Duration(seconds: 10))
                      : null,
                  icon: const Icon(Icons.forward_10_rounded),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: theme.bodySmall.override(
                    fontFamily: theme.bodySmallFamily,
                    color: theme.error,
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordingWaveformPainter extends CustomPainter {
  _RecordingWaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 64;
    final barWidth = size.width / (bars * 1.65);
    final gap = barWidth * .65;
    final heights = List<double>.generate(bars, (index) {
      final envelope = math.sin((index + 1) / (bars + 1) * math.pi) * .32 + .68;
      final variation = .35 + ((index * 37) % 61) / 100;
      return size.height * .86 * envelope * variation;
    });
    final activeBars = (bars * progress).floor();
    for (var index = 0; index < bars; index++) {
      final height = heights[index].clamp(8.0, size.height);
      final left = index * (barWidth + gap);
      final top = (size.height - height) / 2;
      final paint = Paint()
        ..color = index <= activeBars ? activeColor : inactiveColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;
      canvas.drawLine(Offset(left + barWidth / 2, top),
          Offset(left + barWidth / 2, top + height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RecordingWaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor;
}

class _ContactRow extends StatelessWidget {
  const _ContactRow(
      {required this.contact, required this.theme, required this.onCall});

  final PhoneContact contact;
  final FlutterFlowTheme theme;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) => _RowSurface(
        theme: theme,
        leading: _ContactAvatar(contact: contact, theme: theme),
        title: contact.title,
        subtitle: contact.subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CallButton(theme: theme, onTap: onCall),
            if (contact.ticketCount != null)
              _TicketCount(count: contact.ticketCount!, theme: theme),
          ],
        ),
      );
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.theme, required this.onTap});

  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Call',
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        icon: Icon(IconsaxPlusBroken.call, color: theme.primaryText, size: 19),
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
        decoration: BoxDecoration(color: theme.primaryBackground),
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
            border: Border.all(color: theme.alternate)),
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
    this.onTap,
    this.onEdit,
    this.onPlay,
    this.showPlayAction = false,
    this.recordingOnlySwipe = false,
  });

  final FlutterFlowTheme theme;
  final Widget child;
  final VoidCallback onAction;
  final String semanticsLabel;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onPlay;
  final bool showPlayAction;

  /// Recents do not expose fixture-like message/call swipe actions. A swipe
  /// is reserved exclusively for a recording when the server supplied one.
  final bool recordingOnlySwipe;

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
        onHorizontalDragUpdate:
            widget.recordingOnlySwipe && !widget.showPlayAction
                ? null
                : (details) => setState(() {
                      _offset = (_offset + details.delta.dx)
                          .clamp(-_maxOffset, _maxOffset);
                    }),
        onHorizontalDragEnd: widget.recordingOnlySwipe && !widget.showPlayAction
            ? null
            : (_) => setState(() {
                  _offset = _offset.abs() > _maxOffset * .45
                      ? _offset.sign * _maxOffset
                      : 0;
                }),
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.recordingOnlySwipe
                  ? Row(
                      children: [
                        _SwipeAction(
                          label: 'Play',
                          icon: IconsaxPlusBroken.play,
                          color: widget.theme.secondary,
                          onTap: () {
                            _reset();
                            (widget.onPlay ?? widget.onAction)();
                          },
                        ),
                        const Spacer(),
                        _SwipeAction(
                          label: 'Play',
                          icon: IconsaxPlusBroken.play,
                          color: widget.theme.secondary,
                          onTap: () {
                            _reset();
                            (widget.onPlay ?? widget.onAction)();
                          },
                        ),
                      ],
                    )
                  : _standardSwipeActions(),
            ),
            AnimatedContainer(
              duration: duration,
              transform: Matrix4.translationValues(_offset, 0, 0),
              child: IgnorePointer(
                ignoring: _offset != 0,
                child: Material(
                  color: widget.theme.primaryBackground,
                  child: InkWell(
                    onTap: _offset == 0 ? widget.onTap : _reset,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _standardSwipeActions() => Row(
        children: [
          _SwipeAction(
            label: widget.onEdit == null ? 'Message' : 'Edit',
            icon: widget.onEdit == null
                ? IconsaxPlusBroken.messages
                : IconsaxPlusBroken.edit,
            color: widget.onEdit == null
                ? widget.theme.secondary
                : widget.theme.primary,
            onTap: () {
              _reset();
              widget.onEdit?.call();
              if (widget.onEdit == null) widget.onAction();
            },
          ),
          _SwipeAction(
            label: widget.showPlayAction ? 'Play' : 'Message',
            icon: widget.showPlayAction
                ? IconsaxPlusBroken.play
                : IconsaxPlusBroken.messages,
            color: widget.theme.secondary,
            onTap: () {
              _reset();
              (widget.showPlayAction
                  ? widget.onPlay ?? widget.onAction
                  : widget.onAction)();
            },
          ),
          const Spacer(),
          _SwipeAction(
            label: widget.showPlayAction ? 'Play' : 'Message',
            icon: widget.showPlayAction
                ? IconsaxPlusBroken.play
                : IconsaxPlusBroken.messages,
            color: widget.theme.secondary,
            onTap: () {
              _reset();
              (widget.showPlayAction
                  ? widget.onPlay ?? widget.onAction
                  : widget.onAction)();
            },
          ),
          _SwipeAction(
            label: widget.onEdit == null ? 'Message' : 'Edit',
            icon: widget.onEdit == null
                ? IconsaxPlusBroken.messages
                : IconsaxPlusBroken.edit,
            color: widget.onEdit == null
                ? widget.theme.secondary
                : widget.theme.primary,
            onTap: () {
              _reset();
              widget.onEdit?.call();
              if (widget.onEdit == null) widget.onAction();
            },
          ),
        ],
      );
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
  const _EmptyResults({
    required this.theme,
    required this.label,
    this.description,
  });

  final FlutterFlowTheme theme;
  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.bodyMedium.override(
                  fontFamily: theme.bodyMediumFamily,
                  color: theme.secondaryText,
                  fontSize: 13,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: theme.bodySmall.override(
                    fontFamily: theme.bodySmallFamily,
                    color: theme.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _CallHistorySkeleton extends StatelessWidget {
  const _CallHistorySkeleton({required this.theme});

  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        sliver: SliverList.builder(
          itemCount: 5,
          itemBuilder: (context, index) => SizedBox(
            height: 74,
            child: Row(
              children: [
                Container(
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    color: theme.alternate,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 29),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBar(theme: theme, widthFactor: .46, height: 14),
                      const SizedBox(height: 8),
                      _SkeletonBar(theme: theme, widthFactor: .7, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.theme,
    required this.widthFactor,
    required this.height,
  });

  final FlutterFlowTheme theme;
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: Alignment.centerLeft,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: theme.alternate,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      );
}

class _CallHistoryError extends StatelessWidget {
  const _CallHistoryError({
    required this.theme,
    required this.message,
    required this.onRetry,
  });

  final FlutterFlowTheme theme;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
          child: Column(
            children: [
              Icon(Icons.error_outline, color: theme.secondaryText, size: 22),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.bodyMedium.override(
                  fontFamily: theme.bodyMediumFamily,
                  color: theme.secondaryText,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => onRetry(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
