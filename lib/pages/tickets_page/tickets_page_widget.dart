// ignore_for_file: deprecated_member_use

import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.initialStatus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(ticketsPageProvider.notifier)
              .selectStatus(widget.initialStatus);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  void _selectStatus(TicketStatus? status) {
    _searchController.clear();
    ref.read(ticketsPageProvider.notifier).selectStatus(status);
  }

  Future<void> _openFilters() async {
    final state = ref.read(ticketsPageProvider);
    final result = await _TicketFilterSheet.show(
      context: context,
      initial: _TicketFilterSelection(
        status: state.selectedStatus,
        priorities: state.priorities,
        departments: state.departments,
        categories: state.categories,
      ),
    );
    if (!mounted || result == null) return;
    ref.read(ticketsPageProvider.notifier).applyFilters(
          status: result.status,
          priorities: result.priorities,
          departments: result.departments,
          categories: result.categories,
        );
  }

  void _showComingSoon() => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Coming soon')));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ticketsPageProvider);
    final theme = FlutterFlowTheme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
              pinned: true,
              delegate: _TicketHeaderDelegate(
                  theme: theme,
                  topPadding: topPadding,
                  searchActive: state.searchActive,
                  filtersActive: state.filtersActive,
                  onSearch: state.searchActive ? _closeSearch : _openSearch,
                  onFilter: _openFilters)),
          SliverPersistentHeader(
              pinned: true,
              delegate: _TicketTabsDelegate(
                  theme: theme,
                  selected: state.selectedStatus,
                  onSelected: _selectStatus)),
          if (state.searchActive)
            SliverToBoxAdapter(
                child: _TicketSearchField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged:
                        ref.read(ticketsPageProvider.notifier).setSearchQuery,
                    onClose: _closeSearch,
                    theme: theme)),
          _ticketList(state, theme),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _ticketList(TicketsPageState state, FlutterFlowTheme theme) {
    final tickets = state.filteredTickets;
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
            itemCount: tickets.length,
            itemBuilder: (_, index) {
              final ticket = tickets[index];
              return _TicketSwipeRow(
                  theme: theme,
                  status: ticket.status,
                  onAction: _showComingSoon,
                  child: _TicketRow(ticket: ticket, theme: theme));
            }));
  }
}

class _TicketHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TicketHeaderDelegate(
      {required this.theme,
      required this.topPadding,
      required this.searchActive,
      required this.filtersActive,
      required this.onSearch,
      required this.onFilter});
  final FlutterFlowTheme theme;
  final double topPadding;
  final bool searchActive;
  final bool filtersActive;
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
                      child: Text('7 open · 2 overdue',
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
      theme != oldDelegate.theme;
}

class _TicketTabsDelegate extends SliverPersistentHeaderDelegate {
  const _TicketTabsDelegate(
      {required this.theme, required this.selected, required this.onSelected});
  final FlutterFlowTheme theme;
  final TicketStatus? selected;
  final ValueChanged<TicketStatus?> onSelected;
  @override
  double get minExtent => 46;
  @override
  double get maxExtent => 46;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    const items = [
      (null, 'All'),
      (TicketStatus.open, 'Open'),
      (TicketStatus.inProgress, 'In progress'),
      (TicketStatus.overdue, 'Overdue'),
      (TicketStatus.escalated, 'Escalated'),
      (TicketStatus.resolved, 'Resolved')
    ];
    return ColoredBox(
        color: theme.primaryBackground,
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 20, right: 20),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final item in items)
                SizedBox(
                    width: 110,
                    child: _TicketTab(
                        label: item.$2,
                        selected: selected == item.$1,
                        theme: theme,
                        onTap: () => onSelected(item.$1)))
            ])));
  }

  @override
  bool shouldRebuild(covariant _TicketTabsDelegate oldDelegate) =>
      selected != oldDelegate.selected || theme != oldDelegate.theme;
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
  const _TicketRow({required this.ticket, required this.theme});
  final TicketRecord ticket;
  final FlutterFlowTheme theme;
  String get _source => switch (ticket.source) {
        TicketSource.widget => 'Widget',
        TicketSource.call => 'Call',
        TicketSource.whatsapp => 'WhatsApp',
        TicketSource.email => 'Email'
      };
  String get _priority =>
      ticket.priority.name[0].toUpperCase() + ticket.priority.name.substring(1);
  Color _statusColor() => switch (ticket.status) {
        TicketStatus.overdue || TicketStatus.escalated => theme.error,
        TicketStatus.inProgress => theme.primary,
        TicketStatus.resolved => theme.success,
        TicketStatus.open => theme.primaryText
      };
  String _statusLabel() => switch (ticket.status) {
        TicketStatus.inProgress => 'In progress',
        TicketStatus.overdue => 'Overdue',
        TicketStatus.escalated => 'Escalated',
        TicketStatus.resolved => 'Resolved',
        TicketStatus.open => 'Open'
      };
  @override
  Widget build(BuildContext context) => Semantics(
      label:
          '${ticket.id}, ${ticket.subject}, ${ticket.customer}, ${_statusLabel()}',
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(ticket.id,
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
          ])));
}

class _TicketSwipeRow extends StatefulWidget {
  const _TicketSwipeRow(
      {required this.theme,
      required this.status,
      required this.onAction,
      required this.child});
  final FlutterFlowTheme theme;
  final TicketStatus status;
  final VoidCallback onAction;
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
    final resolved = widget.status == TicketStatus.resolved;
    final firstLabel = resolved ? 'Reopen' : 'Resolve';
    final secondLabel = resolved ? 'View' : 'Assign';
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
              widget.onAction();
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
  const _TicketFilterSelection(
      {this.status,
      this.priorities = const {},
      this.departments = const {},
      this.categories = const {}});
  final TicketStatus? status;
  final Set<TicketPriority> priorities;
  final Set<String> departments;
  final Set<String> categories;
}

class _TicketFilterSheet extends StatefulWidget {
  const _TicketFilterSheet({required this.theme, required this.initial});
  final FlutterFlowTheme theme;
  final _TicketFilterSelection initial;
  static Future<_TicketFilterSelection?> show({
    required BuildContext context,
    required _TicketFilterSelection initial,
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
        ),
      );
  @override
  State<_TicketFilterSheet> createState() => _TicketFilterSheetState();
}

class _TicketFilterSheetState extends State<_TicketFilterSheet> {
  late TicketStatus? _status = widget.initial.status;
  late Set<TicketPriority> _priorities = {...widget.initial.priorities};
  late Set<String> _departments = {...widget.initial.departments};
  late Set<String> _categories = {...widget.initial.categories};
  @override
  Widget build(BuildContext context) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: DraggableScrollableSheet(
          initialChildSize: .60,
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
                        _field(
                            'Status',
                            IconsaxPlusBroken.toggle_on_circle,
                            _status == null
                                ? 'All statuses'
                                : _statusLabel(_status!),
                            () => _chooseStatus()),
                        _field(
                            'Priority',
                            IconsaxPlusBroken.chart,
                            _summary(_priorities.map(_priorityLabel).toSet(),
                                'All priorities'),
                            () => _chooseMulti(
                                    'Priority',
                                    ['Low', 'Medium', 'High'],
                                    _priorities.map(_priorityLabel).toSet(),
                                    (values) {
                                  setState(() => _priorities = values
                                      .map((v) => TicketPriority.values
                                          .firstWhere(
                                              (e) => _priorityLabel(e) == v))
                                      .toSet());
                                })),
                        _field(
                            'Department',
                            IconsaxPlusBroken.building,
                            _summary(_departments, 'All departments'),
                            () => _chooseMulti(
                                'Department',
                                ['General', 'Finance', 'Technical support'],
                                _departments,
                                (values) =>
                                    setState(() => _departments = values))),
                        _field(
                            'Category',
                            IconsaxPlusBroken.tag,
                            _summary(_categories, 'All categories'),
                            () => _chooseMulti(
                                'Category',
                                [
                                  'Accounting',
                                  'Billing and payments',
                                  'Technical support'
                                ],
                                _categories,
                                (values) =>
                                    setState(() => _categories = values))),
                      ])),
                  Padding(
                      padding: EdgeInsets.fromLTRB(20, 10, 20,
                          14 + MediaQuery.viewPaddingOf(context).bottom),
                      child: Row(children: [
                        TextButton(
                            onPressed: () => setState(() {
                                  _status = null;
                                  _priorities = {};
                                  _departments = {};
                                  _categories = {};
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
                                        status: _status,
                                        priorities: _priorities,
                                        departments: _departments,
                                        categories: _categories)),
                                child: const Text('Apply'))),
                      ])),
                ]),
              )));

  int get _activeCount =>
      (_status == null ? 0 : 1) +
      _priorities.length +
      _departments.length +
      _categories.length;
  String _summary(Set<String> values, String all) =>
      values.isEmpty ? all : values.join(', ');
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

  Future<void> _chooseStatus() async {
    final value = await showModalBottomSheet<String?>(
        context: context,
        backgroundColor: Colors.transparent,
        useSafeArea: false,
        builder: (_) => _TicketOptionSheet(
            title: 'Status',
            values: TicketStatus.values,
            selected: _status,
            label: _statusLabel));
    if (mounted && value != null) {
      setState(() => _status = value.isEmpty
          ? null
          : TicketStatus.values.firstWhere((status) => status.name == value));
    }
  }

  Future<void> _chooseMulti(String title, List<String> values,
      Set<String> selected, ValueChanged<Set<String>> done) async {
    final result = await showModalBottomSheet<Set<String>>(
        context: context,
        backgroundColor: Colors.transparent,
        useSafeArea: false,
        builder: (_) => _TicketMultiOptionSheet(
            title: title, values: values, selected: selected));
    if (mounted && result != null) done(result);
  }

  String _priorityLabel(TicketPriority value) =>
      value.name[0].toUpperCase() + value.name.substring(1);
  String _statusLabel(TicketStatus status) => switch (status) {
        TicketStatus.inProgress => 'In progress',
        TicketStatus.overdue => 'Overdue',
        TicketStatus.escalated => 'Escalated',
        TicketStatus.resolved => 'Resolved',
        TicketStatus.open => 'Open'
      };
}

class _TicketOptionSheet<T> extends StatelessWidget {
  const _TicketOptionSheet(
      {required this.title,
      required this.values,
      required this.selected,
      required this.label});
  final String title;
  final List<T> values;
  final T? selected;
  final String Function(T) label;
  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    return Material(
      color: t.primaryBackground,
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
                  style: t.titleMedium.override(
                      color: t.primaryText, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              title: const Text('All'),
              trailing: Icon(
                  selected == null ? Icons.check_circle : Icons.circle_outlined,
                  color: selected == null ? t.primary : t.secondaryText),
              onTap: () => Navigator.pop(context, ''),
            ),
            ...values.map((v) => ListTile(
                  title: Text(label(v)),
                  trailing: Icon(
                      selected == v
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: selected == v ? t.primary : t.secondaryText),
                  onTap: () => Navigator.pop(context, (v as dynamic).name),
                )),
          ],
        ),
      ),
    );
  }
}

class _TicketMultiOptionSheet extends StatefulWidget {
  const _TicketMultiOptionSheet(
      {required this.title, required this.values, required this.selected});
  final String title;
  final List<String> values;
  final Set<String> selected;
  @override
  State<_TicketMultiOptionSheet> createState() =>
      _TicketMultiOptionSheetState();
}

class _TicketMultiOptionSheetState extends State<_TicketMultiOptionSheet> {
  late Set<String> selected = {...widget.selected};
  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    return Material(
      color: t.primaryBackground,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              0, 12, 0, 12 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(widget.title,
                  style: t.titleMedium.override(
                      color: t.primaryText, fontWeight: FontWeight.w700)),
            ),
            ...widget.values.map((v) => CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                dense: true,
                value: selected.contains(v),
                title: Text(v),
                onChanged: (_) => setState(() => selected.contains(v)
                    ? selected.remove(v)
                    : selected.add(v)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: FilledButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('Done')),
            ),
          ],
        ),
      ),
    );
  }
}
