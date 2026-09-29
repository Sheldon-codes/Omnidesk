// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import 'tickets_page_model.dart';

export 'tickets_page_model.dart';

class TicketsPageWidget extends ConsumerStatefulWidget {
  const TicketsPageWidget({super.key, this.initialStatus});

  final TicketStatus? initialStatus;

  static const routeName = 'TicketsPage';
  static const routePath = '/tickets';

  @override
  ConsumerState<TicketsPageWidget> createState() => _TicketsPageWidgetState();
}

class _TicketsPageWidgetState extends ConsumerState<TicketsPageWidget> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreIfNeeded);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final notifier = ref.read(ticketsPageProvider.notifier);
      await notifier.load();
      if (mounted && widget.initialStatus != null) {
        final value = widget.initialStatus!.apiValue;
        if (value == 'overdue' ||
            value == 'escalated' ||
            ref
                .read(ticketsPageProvider)
                .filterOptions
                .statuses
                .any((option) => option.value == value)) {
          notifier.selectStatus(value);
        }
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController
      ..removeListener(_loadMoreIfNeeded)
      ..dispose();
    super.dispose();
  }

  void _loadMoreIfNeeded() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 400) {
      unawaited(ref.read(ticketsPageProvider.notifier).loadMore());
    }
  }

  void _openSearch() {
    ref.read(ticketsPageProvider.notifier).openSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(ticketsPageProvider.notifier).closeSearch();
  }

  void _selectStatus(String? status) {
    _searchController.clear();
    ref.read(ticketsPageProvider.notifier).selectStatus(status);
  }

  Future<void> _openFilters() async {
    final state = ref.read(ticketsPageProvider);
    final result = await _TicketFilterSheet.show(
      context: context,
      initial: _TicketFilterSelection(
        status: state.selectedStatus,
        source: state.selectedSource,
        priority: state.selectedPriority,
        departmentId: state.selectedDepartmentId,
        categoryId: state.selectedCategoryId,
        assignment: state.selectedAssignment,
        period: state.period,
        fromDate: state.fromDate,
        toDate: state.toDate,
      ),
      options: state.filterOptions,
    );
    if (!mounted || result == null) return;
    await ref.read(ticketsPageProvider.notifier).applyFilters(
          status: result.status,
          source: result.source,
          priority: result.priority,
          departmentId: result.departmentId,
          categoryId: result.categoryId,
          assignment: result.assignment,
          period: result.period,
          fromDate: result.fromDate,
          toDate: result.toDate,
          clearDates: result.clearDates,
        );
  }

  Future<void> _handleSwipeAction(TicketRecord ticket, String action) async {
    if (action == 'Details') {
      context.push('/tickets/${ticket.id}');
      return;
    }
    final target = action == 'Resolve' ? 'resolved' : 'open';
    try {
      await ref
          .read(ticketsPageProvider.notifier)
          .changeStatus(ticket.id, target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                action == 'Resolve' ? 'Ticket resolved' : 'Ticket reopened')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update ticket: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ticketsPageProvider);
    final theme = FlutterFlowTheme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: RefreshIndicator.adaptive(
          onRefresh: () => ref.read(ticketsPageProvider.notifier).refresh(),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPersistentHeader(
                  pinned: true,
                  delegate: _TicketHeaderDelegate(
                      theme: theme,
                      topPadding: topPadding,
                      searchActive: state.searchActive,
                      filtersActive: state.filtersActive,
                      subtitle: state.subtitleFor(state.tickets),
                      onSearch: state.searchActive ? _closeSearch : _openSearch,
                      onFilter: _openFilters)),
              SliverPersistentHeader(
                  pinned: false,
                  delegate: _TicketTabsDelegate(
                      theme: theme,
                      selected: state.selectedStatus,
                      statuses: state.filterOptions.statuses,
                      onSelected: _selectStatus)),
              if (state.searchActive)
                SliverToBoxAdapter(
                    child: _TicketSearchField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: ref
                            .read(ticketsPageProvider.notifier)
                            .setSearchQuery,
                        onClose: _closeSearch,
                        theme: theme)),
              _ticketList(state, theme),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          )),
    );
  }

  Widget _ticketList(TicketsPageState state, FlutterFlowTheme theme) {
    if ((state.loading || !state.hasLoaded) && state.tickets.isEmpty) {
      return const _TicketListSkeleton();
    }
    if (state.error != null && state.tickets.isEmpty) {
      return SliverFillRemaining(
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(IconsaxPlusBroken.wifi_square, color: theme.secondaryText),
        const SizedBox(height: 12),
        Text('Could not load tickets',
            style: TextStyle(color: theme.primaryText)),
        const SizedBox(height: 6),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(state.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.secondaryText))),
        TextButton(
            onPressed: () =>
                unawaited(ref.read(ticketsPageProvider.notifier).retry()),
            child: const Text('Retry')),
      ])));
    }
    final tickets = state.tickets;
    if (tickets.isEmpty) {
      return SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 44, 20, 20),
              child: Center(
                  child: Text(
                      state.query.trim().isEmpty
                          ? 'No tickets in this view'
                          : 'No matching tickets',
                      style: theme.bodyMedium.override(
                          fontFamily: theme.bodyMediumFamily,
                          color: theme.secondaryText)))));
    }
    return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        sliver: SliverList.builder(
            itemCount: tickets.length +
                (state.loadingMore ? 3 : 0) +
                (state.error != null ? 1 : 0),
            itemBuilder: (_, index) {
              if (state.error != null && index == tickets.length) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Could not load more tickets',
                      style: TextStyle(color: theme.error)),
                  trailing: TextButton(
                    onPressed: () => unawaited(
                        ref.read(ticketsPageProvider.notifier).retry()),
                    child: const Text('Retry'),
                  ),
                );
              }
              if (index >= tickets.length) return const _TicketRowSkeleton();
              final ticket = tickets[index];
              return _TicketSwipeRow(
                  theme: theme,
                  status: ticket.status,
                  onAction: (action) => _handleSwipeAction(ticket, action),
                  child: _TicketRow(
                      ticket: ticket,
                      theme: theme,
                      onTap: () => context.push('/tickets/${ticket.id}')));
            }));
  }
}

class _TicketHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TicketHeaderDelegate(
      {required this.theme,
      required this.topPadding,
      required this.searchActive,
      required this.filtersActive,
      required this.subtitle,
      required this.onSearch,
      required this.onFilter});
  final FlutterFlowTheme theme;
  final double topPadding;
  final bool searchActive;
  final bool filtersActive;
  final String subtitle;
  final VoidCallback onSearch;
  final VoidCallback onFilter;
  @override
  double get minExtent => topPadding + 56;
  @override
  double get maxExtent => minExtent + 65;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final titleSize = lerpDouble(32, 18, progress)!;
    final titleTop = lerpDouble(topPadding + 56, topPadding + 19, progress)!;
    final subtitleOpacity = (1 - progress / .6).clamp(0.0, 1.0);
    return ColoredBox(
        color: theme.primaryBackground,
        child: Stack(children: [
          Positioned(
              top: titleTop,
              left: 20,
              right: 110,
              child: Text('Tickets',
                  style: theme.titleLarge.override(
                      fontFamily: theme.titleLargeFamily,
                      color: theme.primaryText,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -.8,
                      lineHeight: 1))),
          Positioned(
              top: topPadding + 99,
              left: 20,
              right: 20,
              child: IgnorePointer(
                  child: Opacity(
                      opacity: subtitleOpacity,
                      child: Text(subtitle,
                          style: theme.bodyMedium.override(
                              fontFamily: theme.bodyMediumFamily,
                              color: theme.secondaryText,
                              fontSize: 13,
                              fontWeight: FontWeight.w500))))),
          Positioned(
              top: topPadding,
              right: 52,
              height: 56,
              child: IconButton(
                  tooltip: 'Search tickets',
                  onPressed: onSearch,
                  icon: Icon(
                      searchActive
                          ? Icons.close
                          : IconsaxPlusBroken.search_normal_1,
                      color: theme.primaryText,
                      size: 22))),
          Positioned(
              top: topPadding,
              right: 8,
              height: 56,
              child: IconButton(
                  tooltip: 'Filter tickets',
                  onPressed: onFilter,
                  icon: Icon(IconsaxPlusBroken.setting_4,
                      color: filtersActive ? theme.primary : theme.primaryText,
                      size: 21))),
          Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 1,
              child: Opacity(
                  opacity: progress,
                  child: ColoredBox(
                      color: theme.alternate.withValues(alpha: .65)))),
        ]));
  }

  @override
  bool shouldRebuild(covariant _TicketHeaderDelegate oldDelegate) =>
      searchActive != oldDelegate.searchActive ||
      filtersActive != oldDelegate.filtersActive ||
      subtitle != oldDelegate.subtitle ||
      theme != oldDelegate.theme;
}

class _TicketTabsDelegate extends SliverPersistentHeaderDelegate {
  const _TicketTabsDelegate(
      {required this.theme,
      required this.selected,
      required this.statuses,
      required this.onSelected});
  final FlutterFlowTheme theme;
  final String? selected;
  final List<TicketFilterOption> statuses;
  final ValueChanged<String?> onSelected;
  @override
  double get minExtent => 46;
  @override
  double get maxExtent => 46;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
        color: theme.primaryBackground,
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 20, right: 20),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final item in statuses)
                SizedBox(
                    width: item.label.length > 14 ? 160 : 110,
                    child: _TicketTab(
                        label: item.label,
                        selected: selected == item.value,
                        theme: theme,
                        onTap: () => onSelected(item.value)))
            ])));
  }

  @override
  bool shouldRebuild(covariant _TicketTabsDelegate oldDelegate) =>
      selected != oldDelegate.selected ||
      statuses != oldDelegate.statuses ||
      theme != oldDelegate.theme;
}

class _TicketTab extends StatelessWidget {
  const _TicketTab(
      {required this.label,
      required this.selected,
      required this.theme,
      required this.onTap});
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
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onTap: onTap,
          child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: selected ? theme.primary : Colors.transparent,
                          width: 2))),
              child: Text(label,
                  style: theme.bodyMedium.override(
                      fontFamily: theme.bodyMediumFamily,
                      color: selected ? theme.primary : theme.secondaryText,
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500)))));
}

class _TicketSearchField extends StatelessWidget {
  const _TicketSearchField(
      {required this.controller,
      required this.focusNode,
      required this.onChanged,
      required this.onClose,
      required this.theme});
  final TextEditingController controller;
  final FocusNode focusNode;
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
              border: Border.all(color: theme.primary, width: 1.25)),
          child: Row(children: [
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
                        color: theme.primaryText),
                    decoration: InputDecoration(
                        hintText: 'Search tickets...',
                        hintStyle: theme.bodyMedium.override(
                            fontFamily: theme.bodyMediumFamily,
                            color: theme.secondaryText),
                        border: InputBorder.none,
                        isDense: true))),
            IconButton(
                tooltip: 'Close search',
                onPressed: onClose,
                icon: Icon(Icons.close, color: theme.primary, size: 18))
          ])));
}

class _TicketRow extends StatelessWidget {
  const _TicketRow(
      {required this.ticket, required this.theme, required this.onTap});
  final TicketRecord ticket;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;
  String get _source => ticket.sourceRaw == null
      ? switch (ticket.source) {
          TicketSource.manual => 'Manual',
          TicketSource.widget => 'Widget Chat',
          TicketSource.call => 'Call',
          TicketSource.whatsapp => 'WhatsApp',
          TicketSource.email => 'Email'
        }
      : switch (ticket.sourceRaw!.toLowerCase()) {
          'phone' => 'Phone',
          'whatsapp' => 'WhatsApp',
          'email' => 'Email',
          'widget' => 'Widget / Chat',
          'manual' => 'Manual',
          final value => _humanize(value),
        };
  String get _priority => ticket.priorityRaw == null
      ? ticket.priority.label
      : ticket.priorityRaw![0].toUpperCase() + ticket.priorityRaw!.substring(1);
  String get _status => ticket.statusRaw ?? ticket.status.apiValue;
  String _statusLabel() => ticket.statusRaw == null
      ? ticket.status.label
      : _humanize(ticket.statusRaw!);
  Color _statusColor() =>
      ticket.isOverdue || _status == 'overdue' || _status == 'escalated'
          ? theme.error
          : _status == 'resolved' || _status == 'closed'
              ? theme.success
              : _status == 'in_progress' || _status == 'pending'
                  ? theme.primary
                  : theme.primaryText;
  /*Color _statusColor() => switch (ticket.status) {
        TicketStatus.overdue || TicketStatus.escalated => theme.error,
        TicketStatus.inProgress => theme.primary,
        TicketStatus.resolved => theme.success,
        TicketStatus.open => theme.primaryText
      };*/
  @override
  Widget build(BuildContext context) => Semantics(
      label:
          '${ticket.id}, ${ticket.subject}, ${ticket.customer}, ${_statusLabel()}',
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(ticket.displayId ?? ticket.id,
                          style: theme.bodySmall.override(
                              fontFamily: theme.bodySmallFamily,
                              color: theme.primary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(ticket.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodyMedium.override(
                              fontFamily: theme.bodyMediumFamily,
                              color: theme.primaryText,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(ticket.customer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodySmall.override(
                              fontFamily: theme.bodySmallFamily,
                              color: theme.secondaryText)),
                      const SizedBox(height: 5),
                      Text(
                          [
                            _source,
                            ticket.department,
                            _priority,
                            if (ticket.sla != null) ticket.sla!
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.labelSmall.override(
                              fontFamily: theme.labelSmallFamily,
                              color: theme.secondaryText))
                    ])),
                const SizedBox(width: 10),
                Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_statusLabel(),
                        style: theme.labelSmall.override(
                            fontFamily: theme.labelSmallFamily,
                            color: _statusColor(),
                            fontWeight: FontWeight.w600)))
              ]))));
}

String _humanize(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .map((part) =>
        part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

class _TicketSwipeRow extends StatefulWidget {
  const _TicketSwipeRow(
      {required this.theme,
      required this.status,
      required this.onAction,
      required this.child});
  final FlutterFlowTheme theme;
  final TicketStatus status;
  final ValueChanged<String> onAction;
  final Widget child;
  @override
  State<_TicketSwipeRow> createState() => _TicketSwipeRowState();
}

class _TicketSwipeRowState extends State<_TicketSwipeRow>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 80.0;
  double _offset = 0;
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180));
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    late final Animation<double> animation;
    animation = Tween<double>(begin: _offset, end: 0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut))
      ..addListener(() => setState(() => _offset = animation.value));
    _controller
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.status == TicketStatus.resolved ||
        widget.status == TicketStatus.closed;
    final firstLabel = resolved ? 'Reopen' : 'Resolve';
    const secondLabel = 'Details';
    final firstIcon = resolved ? Icons.refresh : Icons.check_circle_outline;
    final secondIcon =
        resolved ? Icons.open_in_new : Icons.person_add_alt_outlined;
    Widget action(String label, IconData icon) => SizedBox(
        width: _actionWidth,
        child: _TicketSwipeAction(
            label: label,
            icon: icon,
            theme: widget.theme,
            onTap: () {
              _reset();
              widget.onAction(label);
            }));
    return Stack(children: [
      Positioned.fill(
          child: Row(children: [
        if (_offset > 0) ...[
          action(firstLabel, firstIcon),
          action(secondLabel, secondIcon)
        ],
        const Spacer(),
        if (_offset < 0) ...[
          action(secondLabel, secondIcon),
          action(firstLabel, firstIcon)
        ],
      ])),
      GestureDetector(
        onHorizontalDragUpdate: (details) => setState(
            () => _offset = (_offset + details.delta.dx).clamp(-160.0, 160.0)),
        onHorizontalDragEnd: (_) => _offset.abs() < 42
            ? _reset()
            : setState(() => _offset = _offset.sign * 160.0),
        onTap: _offset == 0 ? null : _reset,
        child: Transform.translate(
            offset: Offset(_offset, 0),
            child: ColoredBox(
                color: widget.theme.primaryBackground,
                child: Column(children: [
                  widget.child,
                  Divider(height: 1, color: widget.theme.alternate)
                ]))),
      ),
    ]);
  }
}

class _TicketSwipeAction extends StatelessWidget {
  const _TicketSwipeAction(
      {required this.label,
      required this.icon,
      required this.theme,
      required this.onTap});
  final String label;
  final IconData icon;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: theme.primary.withValues(alpha: .10),
      child: InkWell(
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: theme.primary, size: 19),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    color: theme.primary,
                    fontSize: 9,
                    fontWeight: FontWeight.w600))
          ])));
}

class _TicketFilterSelection {
  const _TicketFilterSelection({
    this.status,
    this.source,
    this.priority,
    this.departmentId,
    this.categoryId,
    this.assignment,
    this.period,
    this.fromDate,
    this.toDate,
    this.clearDates = false,
  });
  final String? status;
  final String? source;
  final String? priority;
  final String? departmentId;
  final String? categoryId;
  final String? assignment;
  final String? period;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool clearDates;
}

class _TicketFilterSheet extends StatefulWidget {
  const _TicketFilterSheet(
      {required this.theme, required this.initial, required this.options});
  final FlutterFlowTheme theme;
  final _TicketFilterSelection initial;
  final TicketFilterOptions options;
  static Future<_TicketFilterSelection?> show({
    required BuildContext context,
    required _TicketFilterSelection initial,
    required TicketFilterOptions options,
  }) =>
      showModalBottomSheet<_TicketFilterSelection>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useSafeArea: false,
        barrierColor: Colors.black.withValues(alpha: .24),
        builder: (_) => _TicketFilterSheet(
          theme: FlutterFlowTheme.of(context),
          initial: initial,
          options: options,
        ),
      );
  @override
  State<_TicketFilterSheet> createState() => _TicketFilterSheetState();
}

class _TicketFilterSheetState extends State<_TicketFilterSheet> {
  late String? _status = widget.initial.status;
  late String? _source = widget.initial.source;
  late String? _priority = widget.initial.priority;
  late String? _departmentId = widget.initial.departmentId;
  late String? _categoryId = widget.initial.categoryId;
  late String? _assignment = widget.initial.assignment;
  late String? _period = widget.initial.period;
  late DateTime? _fromDate = widget.initial.fromDate;
  late DateTime? _toDate = widget.initial.toDate;
  bool _clearDates = false;
  @override
  Widget build(BuildContext context) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: DraggableScrollableSheet(
          initialChildSize: .64,
          minChildSize: .42,
          maxChildSize: .86,
          expand: false,
          builder: (context, scroll) => Material(
                color: widget.theme.primaryBackground,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  const SizedBox(height: 10),
                  Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8))),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 10, 14),
                      child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Filter tickets',
                                  style: widget.theme.titleLarge.override(
                                      color: widget.theme.primaryText,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(
                                  _activeCount == 0
                                      ? 'Narrow your ticket list'
                                      : '$_activeCount filters selected',
                                  style: widget.theme.bodySmall.override(
                                      color: widget.theme.secondaryText)),
                            ])),
                        IconButton(
                            tooltip: 'Close filters',
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(IconsaxPlusBroken.close_circle,
                                color: widget.theme.primaryText)),
                      ])),
                  Divider(height: 1, color: widget.theme.alternate),
                  Expanded(
                      child: ListView(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                          children: [
                        if (widget.options.statuses.isNotEmpty)
                          _singleField(
                              'Status',
                              IconsaxPlusBroken.toggle_on_circle,
                              widget.options.statuses,
                              _status,
                              (value) => setState(() => _status = value)),
                        if (widget.options.sources.isNotEmpty)
                          _singleField(
                              'Source',
                              IconsaxPlusBroken.message,
                              widget.options.sources,
                              _source,
                              (value) => setState(() => _source = value)),
                        if (widget.options.priorities.isNotEmpty)
                          _singleField(
                              'Priority',
                              IconsaxPlusBroken.chart,
                              widget.options.priorities,
                              _priority,
                              (value) => setState(() => _priority = value)),
                        if (widget.options.departments.isNotEmpty)
                          _singleField(
                              'Department',
                              IconsaxPlusBroken.building,
                              widget.options.departments,
                              _departmentId,
                              (value) => setState(() => _departmentId = value)),
                        if (widget.options.categories.isNotEmpty)
                          _singleField(
                              'Category',
                              IconsaxPlusBroken.tag,
                              widget.options.categories,
                              _categoryId,
                              (value) => setState(() => _categoryId = value)),
                        if (widget.options.assignments.isNotEmpty)
                          _singleField(
                              'Assignment',
                              IconsaxPlusBroken.people,
                              widget.options.assignments,
                              _assignment,
                              (value) => setState(() => _assignment = value)),
                        if (widget.options.periods.isNotEmpty)
                          _singleField('Period', IconsaxPlusBroken.calendar,
                              widget.options.periods, _period, (value) {
                            setState(() => _period = value);
                            if (value == 'custom') unawaited(_pickDateRange());
                          }),
                        _dateRangeField(),
                      ])),
                  Padding(
                      padding: EdgeInsets.fromLTRB(20, 10, 20,
                          14 + MediaQuery.viewPaddingOf(context).bottom),
                      child: Row(children: [
                        TextButton(
                            onPressed: () => setState(() {
                                  _source = null;
                                  _status = null;
                                  _priority = null;
                                  _departmentId = null;
                                  _categoryId = null;
                                  _assignment = 'me';
                                  _period = null;
                                  _fromDate = null;
                                  _toDate = null;
                                  _clearDates = true;
                                }),
                            child: Text('Reset',
                                style: TextStyle(color: widget.theme.primary))),
                        const Spacer(),
                        SizedBox(
                            height: 50,
                            width: 150,
                            child: FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: widget.theme.primary,
                                    foregroundColor:
                                        widget.theme.primaryBackground,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(25))),
                                onPressed: () => Navigator.pop(
                                    context,
                                    _TicketFilterSelection(
                                        source: _source,
                                        status: _status,
                                        priority: _priority,
                                        departmentId: _departmentId,
                                        categoryId: _categoryId,
                                        assignment: _assignment,
                                        period: _period,
                                        fromDate: _fromDate,
                                        toDate: _toDate,
                                        clearDates: _clearDates)),
                                child: const Text('Apply'))),
                      ])),
                ]),
              )));

  int get _activeCount => [
        _status,
        _source,
        _priority,
        _departmentId,
        _categoryId,
        if (_assignment != null && _assignment != 'me') _assignment,
        if (_period != null && _period != 'all') _period,
        if (_fromDate != null || _toDate != null) 'date',
      ].whereType<String>().length;

  Widget _singleField(
      String label,
      IconData icon,
      List<TicketFilterOption> options,
      String? selected,
      ValueChanged<String?> onSelected) {
    String? selectedLabel;
    for (final option in options) {
      if (option.value == selected) {
        selectedLabel = option.label;
        break;
      }
    }
    return _field(label, icon, selectedLabel ?? 'All $label', () async {
      final result = await showModalBottomSheet<String?>(
          context: context,
          backgroundColor: Colors.transparent,
          useSafeArea: false,
          builder: (_) => _DynamicOptionSheet(
                title: label,
                options: options,
                selected: selected,
                iconFor: _iconFor,
              ));
      if (mounted && result != null) onSelected(result.isEmpty ? null : result);
    });
  }

  Widget _dateRangeField() => _field(
        'Date range',
        IconsaxPlusBroken.calendar,
        _fromDate == null && _toDate == null
            ? 'Any time'
            : '${_formatDate(_fromDate)} – ${_formatDate(_toDate)}',
        _pickDateRange,
      );

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );
    if (!mounted || range == null) return;
    setState(() {
      _period = 'custom';
      _fromDate = range.start;
      _toDate = range.end;
      _clearDates = false;
    });
  }

  String _formatDate(DateTime? date) => date == null
      ? '—'
      : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  IconData _iconFor(String value) => switch (value.toLowerCase()) {
        'open' || 'open_all' || 'in_progress' => IconsaxPlusBroken.timer_1,
        'pending' => IconsaxPlusBroken.clock,
        'resolved' || 'closed' || 'closed_all' => IconsaxPlusBroken.tick_circle,
        'phone' => IconsaxPlusBroken.call,
        'whatsapp' || 'widget' || 'email' => IconsaxPlusBroken.message,
        'manual' => IconsaxPlusBroken.note_2,
        'low' || 'medium' || 'high' || 'urgent' => IconsaxPlusBroken.chart,
        'today' ||
        'week' ||
        'month' ||
        'quarter' ||
        'custom' ||
        'all' =>
          IconsaxPlusBroken.calendar,
        'me' || 'all' || 'unassigned' => IconsaxPlusBroken.people,
        _ => IconsaxPlusBroken.setting_2,
      };
  Widget _field(
          String label, IconData icon, String value, VoidCallback onTap) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: label,
                      prefixIcon: Icon(icon, color: widget.theme.primary),
                      suffixIcon: Icon(IconsaxPlusBroken.arrow_down_1,
                          color: widget.theme.secondaryText),
                      filled: true,
                      fillColor: widget.theme.secondaryBackground,
                      labelStyle: TextStyle(color: widget.theme.secondaryText),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide:
                              BorderSide(color: widget.theme.alternate)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                              color: widget.theme.primary, width: 1.5))),
                  child: Text(value,
                      style: widget.theme.bodyLarge
                          .override(color: widget.theme.primaryText)))));
}

class _DynamicOptionSheet extends StatelessWidget {
  const _DynamicOptionSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.iconFor,
  });
  final String title;
  final List<TicketFilterOption> options;
  final String? selected;
  final IconData Function(String) iconFor;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Material(
      color: theme.primaryBackground,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              0, 12, 0, 12 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(title,
                  style: theme.titleMedium.override(
                      color: theme.primaryText, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading:
                  Icon(IconsaxPlusBroken.setting_2, color: theme.secondaryText),
              title: const Text('All'),
              trailing: Icon(selected == null
                  ? Icons.check_circle
                  : Icons.circle_outlined),
              onTap: () => Navigator.pop(context, ''),
            ),
            ...options.map((option) => ListTile(
                  leading: Icon(iconFor(option.value), color: theme.primary),
                  title: Text(option.label),
                  trailing: Icon(selected == option.value
                      ? Icons.check_circle
                      : Icons.circle_outlined),
                  onTap: () => Navigator.pop(context, option.value),
                )),
          ],
        ),
      ),
    );
  }
}

class _TicketListSkeleton extends StatelessWidget {
  const _TicketListSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      sliver: SliverList.builder(
        itemCount: 6,
        itemBuilder: (_, __) => _TicketRowSkeleton(theme: theme),
      ),
    );
  }
}

class _TicketRowSkeleton extends StatelessWidget {
  const _TicketRowSkeleton({this.theme});
  final FlutterFlowTheme? theme;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? FlutterFlowTheme.of(context);
    final fill = t.alternate.withValues(alpha: .62);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        );
    return ExcludeSemantics(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(68, 11),
                    const SizedBox(height: 7),
                    bar(235, 15),
                    const SizedBox(height: 7),
                    bar(125, 12),
                    const SizedBox(height: 8),
                    bar(190, 10),
                  ]),
            ),
            const SizedBox(width: 10),
            Padding(padding: const EdgeInsets.only(top: 2), child: bar(58, 11)),
          ]),
        ),
        Divider(height: 1),
      ]),
    );
  }
}
