import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../flutter_flow/flutter_flow_theme.dart';
import '../customer_editor_page/customer_editor_page_model.dart';
import '../tickets_page/tickets_page_model.dart';
import 'customer_details_page_model.dart';

export 'customer_details_page_model.dart';

class CustomerDetailsPageWidget extends ConsumerWidget {
  const CustomerDetailsPageWidget({super.key, required this.customerId});

  final String customerId;
  static const routeName = 'CustomerDetailsPage';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FlutterFlowTheme.of(context);
    final state =
        ref.watch(customerDetailNotifierProvider(customerId: customerId));
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

    final customer = state.customer!;
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
                onEdit: () => context.push('/customers/$customerId/edit'),
                onDownload: () => _showComingSoon(context),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: _QuickActions(theme: theme),
              ),
            ),
            SliverToBoxAdapter(
                child: _Section(
                    theme: theme,
                    title: 'Details',
                    child: _DetailsSection(customer: customer, theme: theme))),
            SliverToBoxAdapter(
                child: _Section(
                    theme: theme,
                    title: 'Tickets',
                    child:
                        _TicketsSection(tickets: state.tickets, theme: theme))),
            SliverToBoxAdapter(
                child: _Section(
                    theme: theme,
                    title: 'Recent activity',
                    child: _ActivitySection(
                        activities: state.activities, theme: theme))),
            const SliverToBoxAdapter(child: SizedBox(height: 36)),
          ],
        ),
      ),
    );
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
  final VoidCallback onEdit;
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
  const _QuickActions({required this.theme});
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _QuickAction(
              label: 'Call',
              icon: IconsaxPlusBroken.call,
              theme: theme,
              onTap: () => _showComingSoon(context)),
          _QuickAction(
              label: 'Message',
              icon: IconsaxPlusBroken.messages,
              theme: theme,
              onTap: () => _showComingSoon(context)),
          _QuickAction(
              label: 'Email',
              icon: IconsaxPlusBroken.sms,
              theme: theme,
              onTap: () => _showComingSoon(context)),
        ],
      );
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
  const _DetailsSection({required this.customer, required this.theme});
  final CustomerRecord customer;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (customer.company.trim().isNotEmpty) {
      rows.add(
          _InfoRow(label: 'Company', value: customer.company, theme: theme));
    }
    if (customer.notes.trim().isNotEmpty) {
      rows.add(_InfoRow(label: 'Notes', value: customer.notes, theme: theme));
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
  const _TicketsSection({required this.tickets, required this.theme});
  final List<CustomerDetailTicket> tickets;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return _MutedText(theme: theme, text: 'No tickets yet');
    }
    return Column(
      children: [
        for (final ticket in tickets)
          _DenseRow(
            theme: theme,
            title: ticket.id,
            subtitle: ticket.subject,
            metadata:
                '${_statusLabel(ticket.status)} · ${_priorityLabel(ticket.priority)} · ${ticket.department}',
            trailing: _statusLabel(ticket.status),
            trailingColor: _statusColor(ticket.status, theme),
            onTap: () => _showComingSoon(context),
          ),
      ],
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.activities, required this.theme});
  final List<CustomerActivity> activities;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return _MutedText(theme: theme, text: 'No recent activity');
    }
    return Column(
      children: [
        for (final activity in activities)
          _DenseRow(
            theme: theme,
            icon: _activityIcon(activity.channel),
            title: activity.title,
            subtitle: activity.preview,
            metadata: [activity.timestamp, activity.duration, activity.ticketId]
                .whereType<String>()
                .join(' · '),
          ),
      ],
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

IconData _activityIcon(CustomerActivityChannel channel) => switch (channel) {
      CustomerActivityChannel.call => IconsaxPlusBroken.call,
      CustomerActivityChannel.chat => IconsaxPlusBroken.messages,
      CustomerActivityChannel.email => IconsaxPlusBroken.sms,
      CustomerActivityChannel.ticket => IconsaxPlusBroken.ticket,
    };

String _statusLabel(TicketStatus status) => switch (status) {
      TicketStatus.open => 'Open',
      TicketStatus.inProgress => 'In progress',
      TicketStatus.overdue => 'Overdue',
      TicketStatus.escalated => 'Escalated',
      TicketStatus.resolved => 'Resolved',
    };

String _priorityLabel(TicketPriority priority) => switch (priority) {
      TicketPriority.low => 'Low',
      TicketPriority.medium => 'Medium',
      TicketPriority.high => 'High',
    };

Color _statusColor(TicketStatus status, FlutterFlowTheme theme) =>
    switch (status) {
      TicketStatus.overdue || TicketStatus.escalated => theme.error,
      TicketStatus.inProgress => theme.primary,
      TicketStatus.resolved => theme.success,
      TicketStatus.open => theme.primaryText,
    };
