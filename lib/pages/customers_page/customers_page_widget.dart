import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/call_experience/call_session_controller.dart';
import '../../components/omni_skeleton.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../conversation_room_page/whatsapp_compose_sheet.dart';
import '../conversation_room_page/whatsapp_live_store.dart';
import '../customer_editor_page/customer_editor_page_model.dart';
import 'customers_page_model.dart';

export 'customers_page_model.dart';

class CustomersPageWidget extends ConsumerStatefulWidget {
  const CustomersPageWidget({super.key});

  static const routeName = 'CustomersPage';
  static const routePath = '/customers';

  @override
  ConsumerState<CustomersPageWidget> createState() =>
      _CustomersPageWidgetState();
}

class _CustomersPageWidgetState extends ConsumerState<CustomersPageWidget> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(customersPageProvider.notifier).load());
    });
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 420) {
      unawaited(ref.read(customersPageProvider.notifier).loadMore());
    }
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        unawaited(ref.read(customersPageProvider.notifier).search(value));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final state = ref.watch(customersPageProvider);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Column(
          children: [
            _Header(theme: theme, onBack: context.pop),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: TextField(
                controller: _search,
                onChanged: _searchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search customers',
                  hintStyle: TextStyle(color: theme.secondaryText),
                  prefixIcon: Icon(IconsaxPlusBroken.search_normal,
                      color: theme.secondaryText, size: 19),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            _searchChanged('');
                            setState(() {});
                          },
                          icon: Icon(IconsaxPlusBroken.close_circle,
                              color: theme.secondaryText, size: 18),
                        ),
                  filled: true,
                  fillColor: theme.secondaryBackground,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.alternate),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.alternate),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: theme.primary, width: 1.3),
                  ),
                ),
              ),
            ),
            if (state.refreshing)
              LinearProgressIndicator(
                minHeight: 2,
                color: theme.primary,
                backgroundColor: theme.alternate.withValues(alpha: .35),
              ),
            Expanded(child: _content(state, theme)),
          ],
        ),
      ),
    );
  }

  Widget _content(CustomersPageState state, FlutterFlowTheme theme) {
    if ((!state.hasLoaded || state.loading) && state.customers.isEmpty) {
      return const _CustomerListSkeleton();
    }
    if (state.error != null && state.customers.isEmpty) {
      return _MessageState(
        icon: IconsaxPlusBroken.wifi_square,
        title: 'Could not load customers',
        message: state.error!,
        action: 'Retry',
        onAction: () =>
            unawaited(ref.read(customersPageProvider.notifier).retry()),
        theme: theme,
      );
    }
    if (state.isEmpty) {
      return _MessageState(
        icon: IconsaxPlusBroken.people,
        title: state.search.isEmpty ? 'No customers yet' : 'No matches found',
        message: state.search.isEmpty
            ? 'Customers in this workspace will appear here.'
            : 'Try another name, email, or phone number.',
        theme: theme,
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: () => ref.read(customersPageProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 100),
        itemCount: state.customers.length +
            (state.loadingMore ? 3 : 0) +
            (state.error != null ? 1 : 0),
        separatorBuilder: (_, __) => Divider(height: 1, color: theme.alternate),
        itemBuilder: (context, index) {
          if (state.error != null && index == state.customers.length) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Could not refresh customer results',
                  style: TextStyle(color: theme.error)),
              trailing: TextButton(
                onPressed: () => unawaited(
                    ref.read(customersPageProvider.notifier).refresh()),
                child: const Text('Retry'),
              ),
            );
          }
          if (index >= state.customers.length) {
            return const _CustomerSkeletonRow();
          }
          final customer = state.customers[index];
          return _CustomerRow(
            customer: customer,
            theme: theme,
            onTap: () {
              ref.read(customersStoreProvider.notifier).upsert(customer);
              context.push('/customers/${Uri.encodeComponent(customer.id)}',
                  extra: customer);
            },
            onCall: () {
              final started = ref
                  .read(callSessionControllerProvider.notifier)
                  .startOutgoing(CallParty(
                    customerId: customer.id,
                    displayName: customer.name,
                    phoneNumber: customer.phone,
                  ));
              if (!started && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      ref.read(callSessionControllerProvider).failureMessage ??
                          'Call already in progress'),
                ));
              }
            },
            onMessage: () => _composeWhatsApp(customer),
            onEmail: () => launchUrl(
              Uri(scheme: 'mailto', path: customer.email.trim()),
              mode: LaunchMode.externalApplication,
            ),
          );
        },
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
}

class _Header extends StatelessWidget {
  const _Header({required this.theme, required this.onBack});
  final FlutterFlowTheme theme;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: kToolbarHeight,
        child: Row(children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon:
                Icon(IconsaxPlusBroken.arrow_left_2, color: theme.primaryText),
          ),
          Expanded(
            child: Text('Customers',
                style: theme.titleLarge.override(
                    fontFamily: theme.titleLargeFamily,
                    color: theme.primaryText,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 16),
        ]),
      );
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.theme,
    required this.onTap,
    required this.onCall,
    required this.onMessage,
    required this.onEmail,
  });
  final CustomerRecord customer;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  _InitialAvatar(name: customer.name, theme: theme),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              customer.name.isEmpty
                                  ? 'Unnamed customer'
                                  : customer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyMedium.override(
                                  fontFamily: theme.bodyMediumFamily,
                                  color: theme.primaryText,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(
                              customer.email.isNotEmpty
                                  ? customer.email
                                  : customer.phone,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodySmall.override(
                                  fontFamily: theme.bodySmallFamily,
                                  color: theme.secondaryText)),
                        ]),
                  ),
                  if (customer.ticketsCount != null) ...[
                    const SizedBox(width: 8),
                    Text('${customer.ticketsCount} tickets',
                        style: theme.bodySmall.override(
                            fontFamily: theme.bodySmallFamily,
                            color: theme.secondaryText,
                            fontSize: 11)),
                  ],
                  const SizedBox(width: 5),
                  Icon(IconsaxPlusBroken.arrow_right_3,
                      size: 17, color: theme.secondaryText),
                ]),
              ),
            ),
          ),
          if (customer.phone.trim().isNotEmpty)
            _RowAction(
                label: 'Call ${customer.name}',
                icon: IconsaxPlusBroken.call,
                theme: theme,
                onTap: onCall),
          if (customer.phone.trim().isNotEmpty)
            _RowAction(
                label: 'WhatsApp ${customer.name}',
                icon: IconsaxPlusBroken.messages,
                theme: theme,
                onTap: onMessage),
          if (customer.email.trim().isNotEmpty)
            _RowAction(
                label: 'Email ${customer.name}',
                icon: IconsaxPlusBroken.sms,
                theme: theme,
                onTap: onEmail),
        ]),
      );
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.icon,
    required this.theme,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 40),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: theme.secondaryText),
      );
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name, required this.theme});
  final String name;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.alternate.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(initial,
          style: theme.titleMedium.override(
              fontFamily: theme.titleMediumFamily,
              color: theme.primaryText,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _CustomerListSkeleton extends StatelessWidget {
  const _CustomerListSkeleton();

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
        itemCount: 8,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: FlutterFlowTheme.of(context).alternate,
        ),
        itemBuilder: (_, __) => const _CustomerSkeletonRow(),
      );
}

class _CustomerSkeletonRow extends StatelessWidget {
  const _CustomerSkeletonRow();

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(children: [
          _SkeletonBlock(width: 46, height: 46, radius: 14),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _SkeletonBlock(width: 154, height: 14, radius: 5),
                const SizedBox(height: 8),
                _SkeletonBlock(width: 140, height: 11, radius: 5),
              ])),
          _SkeletonBlock(width: 45, height: 10, radius: 5),
          const SizedBox(width: 14),
          Icon(IconsaxPlusBroken.arrow_right_3,
              size: 17, color: theme.alternate),
        ]),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock(
      {required this.width, required this.height, required this.radius});
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return OmniSkeleton(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(radius),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState(
      {required this.icon,
      required this.title,
      required this.message,
      required this.theme,
      this.action,
      this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 36, color: theme.secondaryText),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.titleMedium.override(
                    fontFamily: theme.titleMediumFamily,
                    color: theme.primaryText,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.bodySmall.override(
                    fontFamily: theme.bodySmallFamily,
                    color: theme.secondaryText)),
            if (action != null) ...[
              const SizedBox(height: 14),
              TextButton(onPressed: onAction, child: Text(action!)),
            ],
          ]),
        ),
      );
}
