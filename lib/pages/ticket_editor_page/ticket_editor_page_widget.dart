import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../customer_editor_page/customer_editor_page_model.dart';
import '../tickets_page/ticket_store.dart';
import 'ticket_editor_page_model.dart';

export 'ticket_editor_page_model.dart';

class TicketEditorPageWidget extends ConsumerStatefulWidget {
  const TicketEditorPageWidget({super.key, this.ticketId});
  final String? ticketId;
  static const routeName = 'TicketEditorPage';

  @override
  ConsumerState<TicketEditorPageWidget> createState() =>
      _TicketEditorPageWidgetState();
}

class _TicketEditorPageWidgetState
    extends ConsumerState<TicketEditorPageWidget> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _subject;
  late final TextEditingController _description;
  late final TextEditingController _resolution;
  bool _seeded = false;
  bool get _editing => widget.ticketId != null;
  @override
  void initState() {
    super.initState();
    _subject = TextEditingController();
    _description = TextEditingController();
    _resolution = TextEditingController();
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    _resolution.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final provider = ticketEditorNotifierProvider(ticketId: widget.ticketId);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    if (_editing && state.initial == null) {
      return Scaffold(
          body: SafeArea(
              child: Column(children: [
        Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
                onPressed: context.pop, icon: const Icon(Icons.arrow_back))),
        const Expanded(child: Center(child: Text('Ticket not found')))
      ])));
    }
    if (!_seeded) {
      _seeded = true;
      _subject.text = state.subject;
      _description.text = state.description;
      _resolution.text = state.resolutionNote;
    }
    return PopScope(
      canPop: !state.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _attemptClose(state);
      },
      child: Scaffold(
        backgroundColor: theme.primaryBackground,
        body: SafeArea(
          bottom: false,
          child: Form(
            key: _formKey,
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TicketEditorHeaderDelegate(
                    theme: theme,
                    title: _editing ? 'Edit ticket' : 'Create ticket',
                    description: _editing
                        ? 'Update the ticket details and workflow.'
                        : 'Capture a customer issue for your team.',
                    onBack: () => _attemptClose(state),
                  ),
                ),
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
                    sliver: SliverList(
                        delegate: SliverChildListDelegate([
                      _SectionTitle('Ticket info', theme),
                      _PickerRow(
                          label: 'Customer',
                          value: state.customerLabel.isEmpty
                              ? 'Select customer'
                              : state.customerLabel,
                          requiredField: true,
                          error: state.errors['customer'],
                          onTap: _selectCustomer),
                      _PickerRow(
                          label: 'Assigned agent',
                          value: state.assignedAgent,
                          onTap: _selectAgent),
                      _Label('Subject', theme, true),
                      _Input(
                          controller: _subject,
                          hint: 'What does the customer need?',
                          icon: IconsaxPlusBroken.document,
                          error: state.errors['subject'],
                          onChanged: notifier.setSubject,
                          theme: theme),
                      _Label('Description', theme, false),
                      _Input(
                          controller: _description,
                          hint:
                              'Describe the issue, context, and desired outcome',
                          icon: IconsaxPlusBroken.note,
                          minLines: 5,
                          maxLines: 10,
                          onChanged: notifier.setDescription,
                          theme: theme),
                      const SizedBox(height: 28),
                      _SectionTitle('Classification', theme),
                      _PickerRow(
                          label: 'Department',
                          value: state.department,
                          onTap: _selectDepartment),
                      _PickerRow(
                          label: 'Category',
                          value: state.category,
                          requiredField: true,
                          error: state.errors['category'],
                          onTap: _selectCategory),
                      _PickerRow(
                          label: 'Priority',
                          value: state.priority.label,
                          requiredField: true,
                          onTap: _selectPriority),
                      _PickerRow(
                          label: 'Status',
                          value: state.status.label,
                          requiredField: true,
                          onTap: _selectStatus),
                      if (state.status == TicketStatus.resolved) ...[
                        const SizedBox(height: 28),
                        _SectionTitle('Resolution', theme),
                        _PickerRow(
                            label: 'Quick template',
                            value:
                                state.resolutionTemplate ?? 'Select template',
                            onTap: _selectTemplate),
                        _Label('How was this resolved?', theme, true),
                        _Input(
                            controller: _resolution,
                            hint: 'Describe the resolution',
                            icon: IconsaxPlusBroken.note,
                            error: state.errors['resolution'],
                            minLines: 4,
                            maxLines: 8,
                            onChanged: notifier.setResolution,
                            theme: theme),
                      ],
                      if (state.errors['form'] != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(state.errors['form']!,
                                style: TextStyle(color: theme.error))),
                      if (_editing)
                        Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                                onPressed: _delete,
                                icon: Icon(Icons.delete_outline,
                                    color: theme.error),
                                label: Text('Delete ticket',
                                    style: TextStyle(color: theme.error)))),
                    ]))),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: FilledButton(
              onPressed: state.submitting ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: theme.primary.withValues(alpha: .45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: state.submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_editing ? 'Save changes' : 'Create ticket'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _attemptClose(TicketEditorState state) async {
    if (!state.hasUnsavedChanges) {
      if (mounted) context.pop();
      return;
    }
    final discard = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Discard changes?'),
                content: const Text('You have unsaved changes.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep editing')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Discard'))
                ]));
    if (discard == true && mounted) context.pop();
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final notifier = ref
        .read(ticketEditorNotifierProvider(ticketId: widget.ticketId).notifier);
    final result = await notifier.submit();
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Ticket saved')));
    context.go('/tickets/${result.id}');
  }

  Future<void> _selectCustomer() async {
    final result = await Navigator.of(context).push<CustomerRecord>(
        MaterialPageRoute(builder: (_) => _CustomerPicker()));
    if (result != null && mounted) {
      ref
          .read(
              ticketEditorNotifierProvider(ticketId: widget.ticketId).notifier)
          .setCustomer(
              id: result.id,
              name: result.name,
              identifier:
                  result.phone.isNotEmpty ? result.phone : result.email);
    }
  }

  Future<void> _selectAgent() async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => _ValuePicker(title: 'Assign agent', items: [
              for (final item in ticketAgents) (item.name, item.availability)
            ])));
    if (result != null && mounted) {
      ref
          .read(
              ticketEditorNotifierProvider(ticketId: widget.ticketId).notifier)
          .setAgent(result);
    }
  }

  Future<void> _selectDepartment() async {
    final result = await _pick('Department', ticketDepartments);
    if (result != null && mounted) {
      ref
          .read(
              ticketEditorNotifierProvider(ticketId: widget.ticketId).notifier)
          .setDepartment(result);
    }
  }

  Future<void> _selectCategory() async {
    final state =
        ref.read(ticketEditorNotifierProvider(ticketId: widget.ticketId));
    final result = await _pick(
        'Category', ticketCategoriesByDepartment[state.department]!);
    if (result != null && mounted) {
      ref
          .read(
              ticketEditorNotifierProvider(ticketId: widget.ticketId).notifier)
          .setCategory(result);
    }
  }

  Future<void> _selectPriority() async {
    final result = await _pick(
        'Priority', TicketPriority.values.map((item) => item.label).toList());
    if (result != null && mounted) {
      ref
          .read(
              ticketEditorNotifierProvider(ticketId: widget.ticketId).notifier)
          .setPriority(
              TicketPriority.values.firstWhere((item) => item.label == result));
    }
  }

  Future<void> _selectStatus() async {
    final values = [
      TicketStatus.open,
      TicketStatus.inProgress,
      TicketStatus.resolved
    ];
    final result =
        await _pick('Status', values.map((item) => item.label).toList());
    if (result != null && mounted) {
      ref
          .read(
              ticketEditorNotifierProvider(ticketId: widget.ticketId).notifier)
          .setStatus(values.firstWhere((item) => item.label == result));
    }
  }

  Future<void> _selectTemplate() async {
    final result = await _pick('Quick template', const [
      'Solved',
      'Duplicate issue',
      'Customer educated',
      'Configuration corrected',
      'No issue found'
    ]);
    if (result != null && mounted) {
      final notifier = ref.read(
          ticketEditorNotifierProvider(ticketId: widget.ticketId).notifier);
      notifier.selectTemplate(result);
      _resolution.text = ref
          .read(ticketEditorNotifierProvider(ticketId: widget.ticketId))
          .resolutionNote;
    }
  }

  Future<String?> _pick(String title, List<String> values) =>
      Navigator.of(context).push<String>(MaterialPageRoute(
          builder: (_) => _ValuePicker(
              title: title,
              items: [for (final value in values) (value, null)])));
  Future<void> _delete() async {
    final state =
        ref.read(ticketEditorNotifierProvider(ticketId: widget.ticketId));
    final approved = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: Text('Delete ${state.initial!.id}?'),
                content: const Text('This cannot be undone.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'))
                ]));
    if (approved == true) {
      await ref
          .read(ticketStoreProvider.notifier)
          .delete(state.initial!.id, state.initial!.revision);
      if (mounted) context.go('/tickets');
    }
  }
}

class _TicketEditorHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TicketEditorHeaderDelegate({
    required this.theme,
    required this.title,
    required this.description,
    required this.onBack,
  });

  final FlutterFlowTheme theme;
  final String title;
  final String description;
  final VoidCallback onBack;

  static const _expandedContent = 112.0;

  @override
  double get minExtent => kToolbarHeight;

  @override
  double get maxExtent => kToolbarHeight + _expandedContent;

  @override
  bool shouldRebuild(covariant _TicketEditorHeaderDelegate oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.title != title ||
      oldDelegate.description != description ||
      oldDelegate.onBack != onBack;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / _expandedContent).clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        border: Border(
          bottom: BorderSide(
            color: theme.alternate.withValues(alpha: progress > .85 ? .7 : 0),
          ),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 0,
            child: SizedBox(
              width: 48,
              height: kToolbarHeight,
              child: IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: Icon(
                  IconsaxPlusBroken.arrow_left_2,
                  color: theme.primaryText,
                  size: 22,
                ),
              ),
            ),
          ),
          Positioned(
            left: lerpDouble(20, 58, progress)!,
            right: 20,
            top: lerpDouble(66, 16, progress)!,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.headlineMedium.override(
                color: theme.primaryText,
                fontSize: lerpDouble(36, 20, progress)!,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: 112,
            child: Opacity(
              opacity: (1 - progress * 1.35).clamp(0.0, 1.0),
              child: Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.bodyMedium.override(
                  color: theme.secondaryText,
                  fontSize: 15,
                  lineHeight: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.theme);
  final String text;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(text,
          style: theme.titleMedium.override(
              color: theme.primaryText, fontWeight: FontWeight.w700)));
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.theme, this.requiredField);
  final String text;
  final FlutterFlowTheme theme;
  final bool requiredField;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text.rich(TextSpan(
          text: text,
          style: theme.bodyMedium
              .override(color: theme.primaryText, fontWeight: FontWeight.w600),
          children: requiredField
              ? [TextSpan(text: ' *', style: TextStyle(color: theme.error))]
              : null)));
}

class _Input extends StatelessWidget {
  const _Input(
      {required this.controller,
      required this.hint,
      this.icon,
      this.error,
      this.minLines = 1,
      this.maxLines = 1,
      required this.onChanged,
      required this.theme});
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final String? error;
  final int minLines;
  final int maxLines;
  final ValueChanged<String> onChanged;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      style: theme.bodyLarge.override(color: theme.primaryText),
      decoration: InputDecoration(
          hintText: hint,
          hintStyle: theme.bodyMedium.override(color: theme.secondaryText),
          errorText: error,
          filled: true,
          fillColor: theme.secondaryBackground,
          alignLabelWithHint: minLines > 1,
          prefixIcon: icon == null
              ? null
              : Padding(
                  padding: EdgeInsets.only(
                    left: 14,
                    right: 6,
                    top: minLines > 1 ? 14 : 0,
                  ),
                  child: Icon(icon, color: theme.primary, size: 20),
                ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          contentPadding: const EdgeInsets.all(15),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: theme.alternate)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: theme.alternate))));
}

class _PickerRow extends StatelessWidget {
  const _PickerRow(
      {required this.label,
      required this.value,
      this.requiredField = false,
      this.error,
      required this.onTap});
  final String label;
  final String value;
  final bool requiredField;
  final String? error;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: 8,
              title: Text.rich(TextSpan(
                  text: label,
                  style: theme.bodyMedium.override(
                      color: theme.primaryText, fontWeight: FontWeight.w600),
                  children: requiredField
                      ? [
                          TextSpan(
                              text: ' *', style: TextStyle(color: theme.error))
                        ]
                      : null)),
              subtitle: Text(value,
                  style: theme.bodyMedium.override(color: theme.secondaryText)),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap),
          Divider(color: theme.alternate),
          if (error != null)
            Text(error!, style: TextStyle(color: theme.error, fontSize: 12))
        ]));
  }
}

class _ValuePicker extends StatefulWidget {
  const _ValuePicker({required this.title, required this.items});
  final String title;
  final List<(String, String?)> items;
  @override
  State<_ValuePicker> createState() => _ValuePickerState();
}

class _ValuePickerState extends State<_ValuePicker> {
  var query = '';
  @override
  Widget build(BuildContext context) {
    final values = widget.items
        .where((item) => item.$1.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        ),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search), hintText: 'Search'))),
          Expanded(
              child: ListView(children: [
            for (final item in values)
              ListTile(
                  title: Text(item.$1),
                  subtitle: item.$2 == null ? null : Text(item.$2!),
                  onTap: () => Navigator.pop(context, item.$1))
          ]))
        ]));
  }
}

class _CustomerPicker extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  var query = '';
  @override
  Widget build(BuildContext context) {
    final customers = ref
        .watch(customersStoreProvider)
        .where((item) => '${item.name} ${item.phone} ${item.email}'
            .toLowerCase()
            .contains(query.toLowerCase()))
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Select customer')),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search customers'))),
          ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: const Text('Create customer'),
              onTap: () async {
                final customer =
                    await context.push<CustomerRecord>('/customers/new');
                if (customer != null && context.mounted) {
                  Navigator.pop(context, customer);
                }
              }),
          Expanded(
              child: ListView(children: [
            for (final item in customers)
              ListTile(
                  title:
                      Text(item.name.isEmpty ? 'Unnamed customer' : item.name),
                  subtitle:
                      Text(item.phone.isNotEmpty ? item.phone : item.email),
                  onTap: () => Navigator.pop(context, item))
          ]))
        ]));
  }
}
