import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/call_experience/call_session_controller.dart';
import '../../components/omni_skeleton.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../customer_editor_page/customer_editor_page_model.dart';
import '../conversation_room_page/whatsapp_compose_sheet.dart';
import '../conversation_room_page/whatsapp_live_store.dart';
import '../phone_page/call_recording_player.dart';
import 'customer_details_page_model.dart';

export 'customer_details_page_model.dart';

/// Typed navigation handoff for opening a customer/contact from Call History.
/// A call can be linked to a CRM customer or be an unlinked contact known only
/// from its call record. The latter deliberately avoids a synthetic API lookup.
class CustomerDetailsRouteData {
  const CustomerDetailsRouteData({
    required this.initialCustomer,
    required this.initialCallLog,
    required this.loadRemoteProfile,
  });

  final CustomerRecord initialCustomer;
  final CustomerDetailCallLog initialCallLog;
  final bool loadRemoteProfile;
}

class CustomerDetailsPageWidget extends ConsumerStatefulWidget {
  const CustomerDetailsPageWidget(
      {super.key,
      required this.customerId,
      this.initialCustomer,
      this.initialCallLog,
      this.loadRemoteProfile = true});

  final String customerId;
  final CustomerRecord? initialCustomer;
  final CustomerDetailCallLog? initialCallLog;
  final bool loadRemoteProfile;
  static const routeName = 'CustomerDetailsPage';

  @override
  ConsumerState<CustomerDetailsPageWidget> createState() =>
      _CustomerDetailsPageWidgetState();
}

class _CustomerDetailsPageWidgetState
    extends ConsumerState<CustomerDetailsPageWidget> {
  @override
  void initState() {
    super.initState();
    final customer = widget.initialCustomer;
    if (customer != null && widget.loadRemoteProfile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(customersStoreProvider.notifier).upsert(customer);
          ref
              .read(customerDetailProvider(customerId: widget.customerId)
                  .notifier)
              .seedCustomer(customer);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final state = widget.loadRemoteProfile
        ? ref.watch(customerDetailProvider(customerId: widget.customerId))
        : CustomerDetailState(
            customerId: widget.customerId,
            customer: widget.initialCustomer,
            callLogs: widget.initialCallLog == null
                ? const []
                : [widget.initialCallLog!],
            hasLoaded: true,
          );
    if (state.notFound) {
      return Scaffold(
        backgroundColor: theme.primaryBackground,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: context.pop,
                  icon: Icon(IconsaxPlusBroken.arrow_left_2,
                      color: theme.primaryText),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text('Customer not found',
                      style: theme.bodyLarge.override(
                          fontFamily: theme.bodyLargeFamily,
                          color: theme.secondaryText)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final customer = state.customer ?? widget.initialCustomer;
    if (customer == null) {
      return Scaffold(
        backgroundColor: theme.primaryBackground,
        body: SafeArea(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Row(children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: context.pop,
                  icon: Icon(IconsaxPlusBroken.arrow_left_2,
                      color: theme.primaryText),
                ),
                const Text('Customer'),
              ]),
            ),
            SliverToBoxAdapter(child: _ProfileSkeleton(theme: theme)),
            if (state.error != null)
              SliverToBoxAdapter(
                child: _InlineFailure(
                  message: state.error!,
                  onRetry: () => ref
                      .read(
                          customerDetailProvider(customerId: widget.customerId)
                              .notifier)
                      .load(),
                  theme: theme,
                ),
              ),
          ]),
        ),
      );
    }
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _DetailsHeaderDelegate(
                theme: theme,
                customer: customer,
                onBack: context.pop,
                onEdit: widget.loadRemoteProfile
                    ? () async {
                        final updated = await context.push<CustomerRecord>(
                            '/customers/${widget.customerId}/edit');
                        if (mounted && updated != null) {
                          ref
                              .read(customerDetailProvider(
                                      customerId: widget.customerId)
                                  .notifier)
                              .seedCustomer(updated);
                        }
                      }
                    : null,
                onDownload: () => _showComingSoon(context),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: _QuickActions(
                  theme: theme,
                  hasPhone: customer.phone.trim().isNotEmpty,
                  hasEmail: customer.email.trim().isNotEmpty,
                  onCall: () {
                    final started = ref
                        .read(callSessionControllerProvider.notifier)
                        .startOutgoing(CallParty(
                          customerId: customer.id,
                          displayName: customer.name,
                          phoneNumber: customer.phone,
                        ));
                    if (!started) {
                      _showMessage(
                        context,
                        ref
                                .read(callSessionControllerProvider)
                                .failureMessage ??
                            'Call already in progress',
                      );
                    }
                  },
                  canMessage: widget.loadRemoteProfile,
                  onMessage: () => _composeWhatsApp(customer),
                  onEmail: () => launchUrl(
                    Uri(scheme: 'mailto', path: customer.email.trim()),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ),
            if (state.error != null)
              SliverToBoxAdapter(
                child: _InlineFailure(
                  message: state.error!,
                  onRetry: () => ref
                      .read(
                          customerDetailProvider(customerId: widget.customerId)
                              .notifier)
                      .load(),
                  theme: theme,
                ),
              ),
            SliverToBoxAdapter(
                child: _Section(
                    theme: theme,
                    title: 'Details',
                    child: _DetailsSection(
                        customer: customer,
                        loading: state.loading,
                        theme: theme))),
            SliverToBoxAdapter(
                child: _Section(
                    theme: theme,
                    title: 'Tickets',
                    child: _TicketsSection(
                        tickets: state.tickets,
                        loading: state.loading,
                        theme: theme))),
            SliverToBoxAdapter(
                child: _Section(
                    theme: theme,
                    title: 'Recent activity',
                    child: _ActivitySection(
                        tickets: state.tickets,
                        callLogs: _mergedCallLogs(
                            state.callLogs, widget.initialCallLog),
                        loading: state.loading,
                        theme: theme))),
            const SliverToBoxAdapter(child: SizedBox(height: 36)),
          ],
        ),
      ),
    );
  }

  Future<void> _composeWhatsApp(CustomerRecord customer) async {
    final ticketId = await WhatsAppComposeSheet.show(
      context,
      customerId: customer.id,
      customerName: customer.name,
      phone: customer.phone,
    );
    if (!mounted || ticketId == null) return;
    unawaited(ref.read(whatsAppInboxProvider.notifier).load());
    context.push('/chats/whatsapp/$ticketId');
  }

  List<CustomerDetailCallLog> _mergedCallLogs(
    List<CustomerDetailCallLog> callLogs,
    CustomerDetailCallLog? selectedCall,
  ) {
    if (selectedCall == null ||
        callLogs.any((call) => call.id == selectedCall.id)) {
      return callLogs;
    }
    return [selectedCall, ...callLogs];
  }
}

class _DetailsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DetailsHeaderDelegate({
    required this.theme,
    required this.customer,
    required this.onBack,
    required this.onEdit,
    required this.onDownload,
  });

  final FlutterFlowTheme theme;
  final CustomerRecord customer;
  final VoidCallback onBack;
  final VoidCallback? onEdit;
  final VoidCallback onDownload;

  static const _expanded = 184.0;

  @override
  double get minExtent => kToolbarHeight;

  @override
  double get maxExtent => kToolbarHeight + _expanded;

  @override
  bool shouldRebuild(covariant _DetailsHeaderDelegate old) =>
      old.customer != customer || old.theme != theme;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / _expanded).clamp(0.0, 1.0);
    final title = customer.name.trim().isEmpty ? 'Customer' : customer.name;
    final identifier = customer.phone.isNotEmpty
        ? customer.phone
        : customer.email.isNotEmpty
            ? customer.email
            : 'No contact details';
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
            child: IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: Icon(IconsaxPlusBroken.arrow_left_2,
                  color: theme.primaryText, size: 22),
            ),
          ),
          if (onEdit != null)
            Positioned(
              right: 52,
              top: 0,
              child: IconButton(
                tooltip: 'Edit customer',
                onPressed: onEdit,
                icon: Icon(IconsaxPlusBroken.edit,
                    color: theme.primaryText, size: 20),
              ),
            ),
          Positioned(
            right: 8,
            top: 0,
            child: IconButton(
              tooltip: 'Download customer report',
              onPressed: onDownload,
              icon: Icon(IconsaxPlusBroken.document_download,
                  color: theme.primaryText, size: 20),
            ),
          ),
          Positioned(
            left: lerpDouble(20, 58, progress)!,
            right: 56,
            top: lerpDouble(190, 16, progress)!,
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.headlineMedium.override(
                    fontFamily: theme.headlineMediumFamily,
                    color: theme.primaryText,
                    fontSize: lerpDouble(30, 20, progress)!,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7)),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: 54,
            child: Opacity(
              opacity: (1 - progress * 1.35).clamp(0.0, 1.0),
              child: Column(
                children: [
                  _Avatar(customer: customer, theme: theme),
                  const SizedBox(height: 8),
                  Text(identifier,
                      style: theme.bodyMedium.override(
                          fontFamily: theme.bodyMediumFamily,
                          color: theme.primaryText,
                          fontSize: 14)),
                  if (customer.phone.isNotEmpty && customer.email.isNotEmpty)
                    Text(customer.email,
                        style: theme.bodySmall.override(
                            fontFamily: theme.bodySmallFamily,
                            color: theme.secondaryText,
                            fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showComingSoon(BuildContext context) => ScaffoldMessenger.of(context)
    .showSnackBar(const SnackBar(content: Text('Coming soon')));

void _showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class _Avatar extends StatelessWidget {
  const _Avatar({required this.customer, required this.theme});
  final CustomerRecord customer;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    final value = customer.name.trim().isEmpty
        ? '?'
        : String.fromCharCode(customer.name.trim().runes.first).toUpperCase();
    return CircleAvatar(
      radius: 32,
      backgroundColor: theme.accent1,
      child: Text(value,
          style: theme.titleLarge.override(
              fontFamily: theme.titleLargeFamily,
              color: theme.primary,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.theme,
    required this.hasPhone,
    required this.hasEmail,
    required this.onCall,
    required this.onMessage,
    required this.onEmail,
    this.canMessage = true,
  });
  final FlutterFlowTheme theme;
  final bool hasPhone;
  final bool hasEmail;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onEmail;
  final bool canMessage;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (hasPhone && canMessage)
        _QuickAction(
            label: 'Call',
            icon: IconsaxPlusBroken.call,
            theme: theme,
            onTap: onCall),
      if (hasPhone)
        _QuickAction(
            label: 'WhatsApp',
            icon: IconsaxPlusBroken.messages,
            theme: theme,
            onTap: onMessage),
      if (hasEmail)
        _QuickAction(
            label: 'Email',
            icon: IconsaxPlusBroken.sms,
            theme: theme,
            onTap: onEmail),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: actions);
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.label,
      required this.icon,
      required this.theme,
      required this.onTap});
  final String label;
  final IconData icon;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(
              children: [
                Icon(icon, color: theme.primaryText, size: 20),
                const SizedBox(height: 5),
                Text(label,
                    style: theme.bodySmall.override(
                        fontFamily: theme.bodySmallFamily,
                        color: theme.primaryText,
                        fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.theme, required this.title, required this.child});
  final FlutterFlowTheme theme;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.bodyMedium.override(
                    fontFamily: theme.bodyMediumFamily,
                    color: theme.secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 9),
            child,
          ],
        ),
      );
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection(
      {required this.customer, required this.loading, required this.theme});
  final CustomerRecord customer;
  final bool loading;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (customer.company.trim().isNotEmpty) {
      rows.add(
          _InfoRow(label: 'Company', value: customer.company, theme: theme));
    }
    if (customer.ticketsCount != null) {
      rows.add(_InfoRow(
          label: 'Tickets', value: '${customer.ticketsCount}', theme: theme));
    }
    if (customer.createdAt != null) {
      rows.add(_InfoRow(
          label: 'Customer since',
          value: _dateLabel(customer.createdAt!),
          theme: theme));
    }
    if (rows.isEmpty && loading) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DetailSkeletonLine(theme: theme, width: 100),
        const SizedBox(height: 14),
        _DetailSkeletonLine(theme: theme, width: 160),
      ]);
    }
    if (rows.isEmpty) {
      return Text('No additional details',
          style: theme.bodySmall.override(
              fontFamily: theme.bodySmallFamily, color: theme.secondaryText));
    }
    return Column(children: rows);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.label, required this.value, required this.theme});
  final String label;
  final String value;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.bodySmall.override(
                    fontFamily: theme.bodySmallFamily,
                    color: theme.secondaryText,
                    fontSize: 12)),
            const SizedBox(height: 3),
            Text(value,
                style: theme.bodyMedium.override(
                    fontFamily: theme.bodyMediumFamily,
                    color: theme.primaryText,
                    fontSize: 14)),
          ],
        ),
      );
}

class _TicketsSection extends StatelessWidget {
  const _TicketsSection(
      {required this.tickets, required this.loading, required this.theme});
  final List<CustomerDetailTicket> tickets;
  final bool loading;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty && loading) {
      return Column(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) Divider(height: 1, color: theme.alternate),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _DetailSkeletonLine(theme: theme, width: 82),
              const SizedBox(height: 7),
              _DetailSkeletonLine(theme: theme, width: 218),
              const SizedBox(height: 7),
              _DetailSkeletonLine(theme: theme, width: 156),
            ]),
          ),
        ],
      ]);
    }
    if (tickets.isEmpty) {
      return _MutedText(theme: theme, text: 'No tickets yet');
    }
    return Column(
      children: [
        for (final ticket in tickets)
          _DenseRow(
            theme: theme,
            title: ticket.displayNumber,
            subtitle: ticket.subject,
            metadata:
                '${_humanize(ticket.status)} · ${_humanize(ticket.priority)} · ${_humanize(ticket.source)}',
            trailing: _humanize(ticket.status),
            trailingColor: _statusColor(ticket.status, theme),
            onTap: () =>
                context.push('/tickets/${Uri.encodeComponent(ticket.id)}'),
          ),
      ],
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection(
      {required this.tickets,
      required this.callLogs,
      required this.loading,
      required this.theme});
  final List<CustomerDetailTicket> tickets;
  final List<CustomerDetailCallLog> callLogs;
  final bool loading;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty && callLogs.isEmpty && loading) {
      return Column(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) Divider(height: 1, color: theme.alternate),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                _DetailSkeletonLine(
                    theme: theme, width: 30, height: 30, radius: 10),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      _DetailSkeletonLine(theme: theme, width: 132),
                      const SizedBox(height: 7),
                      _DetailSkeletonLine(theme: theme, width: 196),
                    ])),
              ])),
        ],
      ]);
    }
    if (tickets.isEmpty && callLogs.isEmpty) {
      return _MutedText(theme: theme, text: 'No recent activity');
    }
    final entries = <({DateTime? at, Widget row})>[
      for (final ticket in tickets)
        (
          at: ticket.createdAt,
          row: _DenseRow(
            theme: theme,
            icon: IconsaxPlusBroken.ticket,
            title: ticket.subject,
            subtitle: '${ticket.displayNumber} · ${_humanize(ticket.status)}',
            metadata: _dateLabel(ticket.createdAt),
            onTap: () =>
                context.push('/tickets/${Uri.encodeComponent(ticket.id)}'),
          )
        ),
      for (final call in callLogs)
        (at: call.createdAt, row: _CallActivityRow(call: call, theme: theme)),
    ]..sort((a, b) => (b.at ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(a.at ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return Column(
      children: [
        for (final entry in entries) entry.row,
      ],
    );
  }
}

class _CallActivityRow extends StatelessWidget {
  const _CallActivityRow({required this.call, required this.theme});

  final CustomerDetailCallLog call;
  final FlutterFlowTheme theme;

  void _openRecording(BuildContext context) {
    final url = call.recordingUrl;
    if (url == null || url.trim().isEmpty) return;
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
      builder: (_) => CallRecordingPlayerSheet(
        title: 'Call recording',
        subtitle:
            '${call.fromNumber.isNotEmpty ? call.fromNumber : call.toNumber} · '
            '${_humanize(call.status)}',
        recordingUrl: url,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final number = call.fromNumber.isNotEmpty ? call.fromNumber : call.toNumber;
    final metadata = [
      if (call.durationSeconds != null) _durationLabel(call.durationSeconds!),
      if (call.agentName != null) 'by ${call.agentName}',
      call.recordingUrl == null ? 'No recording' : 'Recording available',
      _dateLabel(call.createdAt),
    ].where((value) => value.isNotEmpty).join(' · ');
    final transcript = call.transcript?.trim();
    final ticketLabel = [
      call.ticketNumber,
      call.ticketSubject,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.alternate)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(IconsaxPlusBroken.call, color: theme.secondaryText, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_humanize(call.direction)} call · ${_humanize(call.status)}',
                  style: theme.bodyMedium.override(
                    fontFamily: theme.bodyMediumFamily,
                    color: theme.primaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (number.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      number,
                      style: theme.bodySmall.override(
                        fontFamily: theme.bodySmallFamily,
                        color: theme.primaryText,
                        fontSize: 13,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    metadata,
                    style: theme.bodySmall.override(
                      fontFamily: theme.bodySmallFamily,
                      color: theme.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (ticketLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: InkWell(
                      onTap: call.ticketId == null
                          ? null
                          : () => context.push(
                              '/tickets/${Uri.encodeComponent(call.ticketId!)}'),
                      child: Text(
                        'Ticket: $ticketLabel',
                        style: theme.bodySmall.override(
                          fontFamily: theme.bodySmallFamily,
                          color: call.ticketId == null
                              ? theme.secondaryText
                              : theme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (transcript != null && transcript.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Transcript',
                    style: theme.bodySmall.override(
                      fontFamily: theme.bodySmallFamily,
                      color: theme.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SelectableText(
                    transcript,
                    style: theme.bodySmall.override(
                      fontFamily: theme.bodySmallFamily,
                      color: theme.primaryText,
                      fontSize: 13,
                      lineHeight: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (call.recordingUrl != null && call.recordingUrl!.trim().isNotEmpty)
            IconButton(
              tooltip: 'Play recording',
              onPressed: () => _openRecording(context),
              icon: Icon(IconsaxPlusBroken.play_circle,
                  color: theme.primary, size: 24),
            ),
        ],
      ),
    );
  }
}

class _DenseRow extends StatelessWidget {
  const _DenseRow({
    required this.theme,
    required this.title,
    required this.metadata,
    this.subtitle,
    this.trailing,
    this.trailingColor,
    this.icon,
    this.onTap,
  });
  final FlutterFlowTheme theme;
  final String title;
  final String? subtitle;
  final String metadata;
  final String? trailing;
  final Color? trailingColor;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.alternate))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, color: theme.secondaryText, size: 18),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium.override(
                            fontFamily: theme.bodyMediumFamily,
                            color: theme.primaryText,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodySmall.override(
                                fontFamily: theme.bodySmallFamily,
                                color: theme.primaryText,
                                fontSize: 13)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodySmall.override(
                              fontFamily: theme.bodySmallFamily,
                              color: theme.secondaryText,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Text(trailing!,
                      style: theme.bodySmall.override(
                          fontFamily: theme.bodySmallFamily,
                          color: trailingColor ?? theme.secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      );
}

class _MutedText extends StatelessWidget {
  const _MutedText({required this.theme, required this.text});
  final FlutterFlowTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(text,
            style: theme.bodySmall.override(
                fontFamily: theme.bodySmallFamily, color: theme.secondaryText)),
      );
}

String _humanize(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

Color _statusColor(String status, FlutterFlowTheme theme) =>
    switch (status.toLowerCase()) {
      'resolved' || 'closed' => theme.success,
      'in_progress' || 'pending' => theme.primary,
      'overdue' || 'escalated' => theme.error,
      _ => theme.primaryText,
    };

String _dateLabel(DateTime? date) {
  if (date == null) return 'Date unavailable';
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _durationLabel(int seconds) => '${seconds ~/ 60}m ${seconds % 60}s';

class _DetailSkeletonLine extends StatelessWidget {
  const _DetailSkeletonLine(
      {required this.theme,
      required this.width,
      this.height = 11,
      this.radius = 5});
  final FlutterFlowTheme theme;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => OmniSkeleton(
        width: width,
        height: height,
        borderRadius: BorderRadius.circular(radius),
        circle: radius >= width / 2 && radius >= height / 2,
        baseTint: theme.alternate,
      );
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton({required this.theme});
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _DetailSkeletonLine(theme: theme, width: 64, height: 64, radius: 32),
          const SizedBox(height: 12),
          _DetailSkeletonLine(theme: theme, width: 180, height: 22, radius: 6),
          const SizedBox(height: 8),
          _DetailSkeletonLine(theme: theme, width: 210, height: 14),
          const SizedBox(height: 24),
          for (var i = 0; i < 4; i++) ...[
            _DetailSkeletonLine(theme: theme, width: 240, height: 14),
            const SizedBox(height: 16),
          ],
        ]),
      );
}

class _InlineFailure extends StatelessWidget {
  const _InlineFailure(
      {required this.message, required this.onRetry, required this.theme});
  final String message;
  final VoidCallback onRetry;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Row(children: [
          Expanded(
              child: Text(message,
                  style: theme.bodySmall.override(
                      fontFamily: theme.bodySmallFamily, color: theme.error))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}
