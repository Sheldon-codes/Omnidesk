import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:just_audio/just_audio.dart';

import '../../components/call_experience/call_session_controller.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../email_page/email_page_model.dart';
import '../email_page/widgets/email_body_renderer.dart';
import '../tickets_page/ticket_store.dart';
import 'ticket_details_page_model.dart';

export 'ticket_details_page_model.dart';

class TicketDetailsPageWidget extends ConsumerWidget {
  const TicketDetailsPageWidget({super.key, required this.ticketId});
  final String ticketId;
  static const routeName = 'TicketDetailsPage';
  static const routePath = '/tickets/:ticketId';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FlutterFlowTheme.of(context);
    final state = ref.watch(ticketDetailsNotifierProvider(ticketId: ticketId));
    final notifier =
        ref.read(ticketDetailsNotifierProvider(ticketId: ticketId).notifier);
    if (state.loading) {
      return Scaffold(
          backgroundColor: theme.primaryBackground,
          body: const Center(child: CircularProgressIndicator()));
    }
    if (state.notFound) {
      return _MessagePage(label: 'Ticket not found', onBack: context.pop);
    }
    if (state.failure != null || state.ticket == null) {
      return _MessagePage(
          label: 'Unable to load ticket',
          onBack: context.pop,
          onRetry: notifier.load);
    }
    final ticket = state.ticket!;
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: theme.primaryBackground,
            surfaceTintColor: theme.primaryBackground,
            elevation: 0,
            leading: IconButton(
                tooltip: 'Back',
                onPressed: context.pop,
                icon: Icon(IconsaxPlusBroken.arrow_left_2,
                    color: theme.primaryText)),
            actions: [
              IconButton(
                  tooltip: 'Ticket actions',
                  onPressed: () => _actions(context, ref, ticket),
                  icon: Icon(IconsaxPlusBroken.more, color: theme.primaryText))
            ],
          ),
          SliverToBoxAdapter(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: _TicketIdentity(ticket: ticket, theme: theme),
          )),
          SliverToBoxAdapter(
              child: _Section(
                  title: 'Customer',
                  theme: theme,
                  child: _CustomerRow(ticket: ticket, theme: theme))),
          SliverToBoxAdapter(
              child: _Section(
                  title: 'Description',
                  theme: theme,
                  child: SanitizedEmailBodyRenderer(
                    body: EmailBody(
                        plainText: ticket.description.plainText,
                        html: ticket.description.html),
                    theme: theme,
                    showRemoteImages: false,
                    onLoadRemoteImages: () =>
                        _snack(context, 'Remote images are blocked'),
                    onLinkTap: (_) => _snack(context, 'Coming soon'),
                  ))),
          SliverToBoxAdapter(
              child: _Section(
                  title: 'Details',
                  theme: theme,
                  child: _Details(ticket: ticket, theme: theme))),
          if (ticket.resolution != null)
            SliverToBoxAdapter(
                child: _Section(
                    title: 'Resolution',
                    theme: theme,
                    child: _Resolution(
                        ticket: ticket,
                        theme: theme,
                        onReopen: ticket.capabilities.canResolve
                            ? () => _confirmReopen(context, ref, ticket)
                            : null))),
          SliverToBoxAdapter(
              child: _Section(
                  title: ticket.source == TicketSource.call
                      ? 'Calls'
                      : ticket.source == TicketSource.email
                          ? 'Email thread'
                          : ticket.source == TicketSource.manual
                              ? 'Source'
                              : 'Conversation',
                  theme: theme,
                  child: _Source(ticket: ticket, theme: theme))),
          SliverToBoxAdapter(
              child: _Section(
                  title: 'Activity',
                  theme: theme,
                  child: _Activity(
                      items: state.activity,
                      loadingMore: state.loadingMore,
                      canLoadMore: state.nextActivityCursor != null,
                      onLoadMore: notifier.loadMore,
                      theme: theme))),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ]),
      ),
      bottomNavigationBar: ticket.capabilities.canResolve &&
              ticket.status != TicketStatus.resolved
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: FilledButton(
                  onPressed: () => _resolve(context, ref, ticket),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white),
                  child: const Text('Resolve ticket'),
                ),
              ))
          : null,
    );
  }

  Future<void> _actions(
      BuildContext context, WidgetRef ref, TicketRecord ticket) async {
    final action = await showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (_) => SafeArea(
                child: Wrap(children: [
              if (ticket.capabilities.canEdit)
                ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit ticket'),
                    onTap: () => Navigator.pop(context, 'edit')),
              ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(ticket.customerId == null
                      ? 'Add customer'
                      : 'View customer'),
                  onTap: () => Navigator.pop(context, 'customer')),
              if (ticket.contactIdentifier != null &&
                  !ticket.contactIdentifier!.contains('@'))
                ListTile(
                    leading: const Icon(Icons.call_outlined),
                    title: const Text('Call customer'),
                    onTap: () => Navigator.pop(context, 'call')),
              if (ticket.sourceContext is TicketConversationSourceContext ||
                  ticket.sourceContext is TicketEmailSourceContext)
                ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('Open source'),
                    onTap: () => Navigator.pop(context, 'source')),
              if (ticket.capabilities.canReassign)
                ListTile(
                    leading: const Icon(Icons.person_add_alt_1_outlined),
                    title: const Text('Reassign'),
                    onTap: () => Navigator.pop(context, 'reassign')),
              if (ticket.capabilities.canDelete)
                ListTile(
                    leading: Icon(Icons.delete_outline,
                        color: FlutterFlowTheme.of(context).error),
                    title: Text('Delete ticket',
                        style: TextStyle(
                            color: FlutterFlowTheme.of(context).error)),
                    onTap: () => Navigator.pop(context, 'delete')),
            ])));
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'edit':
        context.push('/tickets/${ticket.id}/edit');
      case 'customer':
        _openCustomer(context, ticket);
      case 'call':
        final started = ref
            .read(callSessionControllerProvider.notifier)
            .startOutgoing(CallParty(
              customerId: ticket.customerId,
              displayName: ticket.customerLabel,
              phoneNumber: ticket.contactIdentifier!,
            ));
        if (!started) {
          _snack(context, 'Call already in progress');
        }
      case 'source':
        _openSource(context, ticket);
      case 'reassign':
        _reassign(context, ref, ticket);
      case 'delete':
        _delete(context, ref, ticket);
    }
  }

  void _openCustomer(BuildContext context, TicketRecord ticket) {
    if (ticket.customerId != null) {
      context.push('/customers/${ticket.customerId}');
      return;
    }
    context.push(Uri(path: '/customers/new', queryParameters: {
      'name': ticket.customerLabel,
      if (ticket.contactIdentifier?.contains('@') ?? false)
        'email': ticket.contactIdentifier!
    }).toString());
  }

  void _openSource(BuildContext context, TicketRecord ticket) =>
      switch (ticket.sourceContext) {
        TicketConversationSourceContext source =>
          context.push('/chats/${source.conversationId}'),
        TicketEmailSourceContext source =>
          context.push('/email/${source.threadId}'),
        _ => _snack(context, 'No source to open'),
      };
  Future<void> _reassign(
      BuildContext context, WidgetRef ref, TicketRecord ticket) async {
    final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
                child: Wrap(children: [
              for (final agent in ticketAgents)
                ListTile(
                    title: Text(agent.name),
                    subtitle: Text(agent.availability),
                    onTap: () => Navigator.pop(context, agent.name))
            ])));
    if (selected == null) return;
    await ref.read(ticketStoreProvider.notifier).reassign(ticket.id, selected);
    if (context.mounted) _snack(context, 'Ticket reassigned');
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, TicketRecord ticket) async {
    final delete = await _confirm(
        context, 'Delete ${ticket.id}?', 'This cannot be undone.', 'Delete');
    if (delete != true) return;
    await ref
        .read(ticketStoreProvider.notifier)
        .delete(ticket.id, ticket.revision);
    if (context.mounted) context.go('/tickets');
  }

  Future<void> _resolve(
      BuildContext context, WidgetRef ref, TicketRecord ticket) async {
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ResolutionSheet(),
    );
    if (note == null || note.isEmpty) return;
    await ref.read(ticketStoreProvider.notifier).resolve(ticket.id, note);
    if (context.mounted) _snack(context, 'Ticket resolved');
  }

  Future<void> _confirmReopen(
      BuildContext context, WidgetRef ref, TicketRecord ticket) async {
    if (await _confirm(context, 'Reopen ticket?',
            'The ticket will return to the open queue.', 'Reopen') ==
        true) {
      await ref.read(ticketStoreProvider.notifier).reopen(ticket.id);
      if (context.mounted) _snack(context, 'Ticket reopened');
    }
  }
}

class _ResolutionSheet extends StatefulWidget {
  const _ResolutionSheet();

  @override
  State<_ResolutionSheet> createState() => _ResolutionSheetState();
}

class _ResolutionSheetState extends State<_ResolutionSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Resolve ticket',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'How was this resolved?',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _controller.text.trim()),
                child: const Text('Resolve ticket'),
              ),
            ],
          ),
        ),
      );
}

class _MessagePage extends StatelessWidget {
  const _MessagePage({required this.label, required this.onBack, this.onRetry});
  final String label;
  final VoidCallback onBack;
  final Future<void> Function()? onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: Column(children: [
        Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
                onPressed: onBack, icon: const Icon(Icons.arrow_back))),
        Expanded(
            child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry'))
        ])))
      ])));
}

class _TicketIdentity extends StatelessWidget {
  const _TicketIdentity({required this.ticket, required this.theme});
  final TicketRecord ticket;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ticket.id,
            style: theme.labelLarge
                .override(color: theme.primary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(ticket.subject,
            style: theme.headlineSmall.override(
                color: theme.primaryText,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4)),
        const SizedBox(height: 9),
        Text(
            '${ticket.status.label} · ${ticket.priority.label} · ${ticket.source.label}',
            style: theme.bodySmall.override(
                color: ticket.status == TicketStatus.resolved
                    ? theme.success
                    : ticket.status == TicketStatus.overdue ||
                            ticket.status == TicketStatus.escalated
                        ? theme.error
                        : theme.secondaryText,
                fontWeight: FontWeight.w600))
      ]);
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title, required this.theme, required this.child});
  final String title;
  final FlutterFlowTheme theme;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: theme.titleMedium.override(
                color: theme.primaryText, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        child
      ]));
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.ticket, required this.theme});
  final TicketRecord ticket;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: () => ticket.customerId == null
          ? context.push('/customers/new')
          : context.push('/customers/${ticket.customerId}'),
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            CircleAvatar(
                radius: 20,
                backgroundColor: theme.accent1,
                child: Text(
                    ticket.customerLabel.isEmpty
                        ? '?'
                        : ticket.customerLabel.characters.first.toUpperCase(),
                    style: TextStyle(color: theme.primary))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(ticket.customerLabel,
                      style: theme.bodyMedium.override(
                          color: theme.primaryText,
                          fontWeight: FontWeight.w600)),
                  if (ticket.contactIdentifier != null)
                    Text(ticket.contactIdentifier!,
                        style: theme.bodySmall
                            .override(color: theme.secondaryText))
                ])),
            Icon(Icons.chevron_right, color: theme.secondaryText)
          ])));
}

class _Details extends StatelessWidget {
  const _Details({required this.ticket, required this.theme});
  final TicketRecord ticket;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Column(
          children: [
        ('Department', ticket.department),
        ('Category', ticket.category ?? 'Not provided'),
        ('Assigned to', ticket.assignedAgent),
        ('Priority', ticket.priority.label),
        ('Source', ticket.source.label),
        ('Created', _date(ticket.createdAt)),
        ('Updated', _date(ticket.updatedAt))
      ]
              .map((row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                        child: Text(row.$1,
                            style: theme.bodySmall
                                .override(color: theme.secondaryText))),
                    Text(row.$2,
                        style: theme.bodySmall.override(
                            color: theme.primaryText,
                            fontWeight: FontWeight.w600))
                  ])))
              .toList());
}

class _Resolution extends StatelessWidget {
  const _Resolution(
      {required this.ticket, required this.theme, required this.onReopen});
  final TicketRecord ticket;
  final FlutterFlowTheme theme;
  final VoidCallback? onReopen;
  @override
  Widget build(BuildContext context) {
    final value = ticket.resolution!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value.note,
          style: theme.bodyMedium.override(color: theme.primaryText)),
      const SizedBox(height: 8),
      Text('Resolved by ${value.resolvedBy} · ${_date(value.resolvedAt)}',
          style: theme.bodySmall.override(color: theme.secondaryText)),
      if (onReopen != null) ...[
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onReopen,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Reopen ticket'),
        ),
      ],
    ]);
  }
}

class _Source extends StatelessWidget {
  const _Source({required this.ticket, required this.theme});
  final TicketRecord ticket;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => switch (ticket.sourceContext) {
        TicketPhoneSourceContext source => Column(children: [
            for (final call in source.calls) _CallRow(call: call, theme: theme)
          ]),
        TicketConversationSourceContext source => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(source.channel.label),
            subtitle: Text(source.preview,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/chats/${source.conversationId}')),
        TicketEmailSourceContext source => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline),
            title: Text(source.from),
            subtitle: Text(source.preview,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/email/${source.threadId}')),
        _ => Text('Created manually',
            style: theme.bodyMedium.override(color: theme.secondaryText)),
      };
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call, required this.theme});
  final TicketCall call;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(call.connected ? Icons.call_made : Icons.phone_missed_outlined,
            color: call.connected ? theme.success : theme.error),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(call.direction,
              style: theme.bodyMedium.override(
                  color: theme.primaryText, fontWeight: FontWeight.w600)),
          Text(
              '${_date(call.occurredAt)}${call.connected ? ' · ${_duration(call.duration)}' : ' · No recording — call was not connected.'}',
              style: theme.bodySmall.override(color: theme.secondaryText))
        ])),
        if (call.hasRecording) _RecordingButton(asset: call.recordingAsset!)
      ]));
}

class _RecordingButton extends StatefulWidget {
  const _RecordingButton({required this.asset});
  final String asset;
  @override
  State<_RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<_RecordingButton> {
  final _player = AudioPlayer();
  var _playing = false;
  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.setAsset(widget.asset);
        await _player.play();
      }
    } catch (_) {
      if (mounted) _snack(context, 'Unable to play recording');
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: _playing ? 'Pause recording' : 'Play recording',
      onPressed: _toggle,
      icon: Icon(
          _playing ? Icons.pause_circle_outline : Icons.play_circle_outline));
}

class _Activity extends StatelessWidget {
  const _Activity(
      {required this.items,
      required this.loadingMore,
      required this.canLoadMore,
      required this.onLoadMore,
      required this.theme});
  final List<TicketActivity> items;
  final bool loadingMore;
  final bool canLoadMore;
  final Future<void> Function() onLoadMore;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final item in items)
          Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: theme.primary)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(item.title,
                          style: theme.bodyMedium.override(
                              color: theme.primaryText,
                              fontWeight: FontWeight.w600)),
                      if (item.description != null)
                        Text(item.description!,
                            style: theme.bodySmall
                                .override(color: theme.secondaryText)),
                      Text(_date(item.timestamp),
                          style: theme.labelSmall
                              .override(color: theme.secondaryText))
                    ]))
              ])),
        if (canLoadMore)
          TextButton(
              onPressed: loadingMore ? null : onLoadMore,
              child: Text(loadingMore ? 'Loading…' : 'Load older activity'))
      ]);
}

String _date(DateTime date) => '${date.day}/${date.month}/${date.year}';
String _duration(Duration value) =>
    '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
Future<bool?> _confirm(
        BuildContext context, String title, String body, String confirm) =>
    showDialog<bool>(
        context: context,
        builder: (_) =>
            AlertDialog(title: Text(title), content: Text(body), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirm))
            ]));
