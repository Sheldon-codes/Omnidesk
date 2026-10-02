import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../components/omni_skeleton.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../components/call_experience/call_session_controller.dart';
import 'email_page_model.dart';
import 'widgets/email_body_renderer.dart';

class EmailThreadPageWidget extends ConsumerStatefulWidget {
  const EmailThreadPageWidget(
      {super.key, required this.threadId, this.initialTimelineId});
  static const routeName = 'EmailThreadPage';
  static const routePath = '/email/:threadId';
  final String threadId;
  final String? initialTimelineId;

  @override
  ConsumerState<EmailThreadPageWidget> createState() =>
      _EmailThreadPageWidgetState();
}

class _EmailThreadPageWidgetState extends ConsumerState<EmailThreadPageWidget> {
  final _expandedMessageIds = <String>{};
  final _remoteImages = <String>{};
  final _messageKeys = <String, GlobalKey>{};
  final _scrollController = ScrollController();
  var _loadCompleted = false;
  var _deepLinkHandled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = ref.read(emailStoreProvider.notifier);
      store.openThread(widget.threadId);
      store.loadThread(widget.threadId).then((_) {
        if (mounted) setState(() => _loadCompleted = true);
      }, onError: (_) {
        if (mounted) setState(() => _loadCompleted = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(emailThreadProvider(widget.threadId));
    final theme = FlutterFlowTheme.of(context);
    if (thread == null) {
      return _loadCompleted
          ? _NotFound(theme: theme)
          : _EmailThreadSkeleton(theme: theme);
    }
    final latest = thread.latestMessage;
    _expandedMessageIds.add(latest.id);
    final targetId = widget.initialTimelineId?.trim();
    if (!_deepLinkHandled && _loadCompleted && targetId?.isNotEmpty == true) {
      _deepLinkHandled = true;
      final target = thread.messages.where((message) => message.id == targetId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (target.isEmpty) {
          _snack('Message was archived or could not be highlighted.');
          return;
        }
        _expandedMessageIds.add(targetId!);
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final index =
              thread.messages.indexWhere((message) => message.id == targetId);
          if (index >= 0 && _scrollController.hasClients) {
            final extent = _scrollController.position.maxScrollExtent;
            final fraction = thread.messages.length <= 1
                ? 0.0
                : index / (thread.messages.length - 1);
            await _scrollController.animateTo(
              extent * fraction,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
            );
          }
          if (!mounted) return;
          final targetContext = _messageKeys[targetId]?.currentContext;
          if (targetContext?.mounted == true) {
            await Scrollable.ensureVisible(
              targetContext!,
              duration: const Duration(milliseconds: 260),
              alignment: .15,
              curve: Curves.easeOut,
            );
          }
        });
      });
    }
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              thread: thread,
              theme: theme,
              onBack: context.pop,
              onActions: () => _openActions(thread),
            ),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                    sliver: SliverList.list(
                      children: [
                        Text(thread.subject,
                            style: theme.titleLarge.override(
                              fontFamily: theme.titleLargeFamily,
                              color: theme.primaryText,
                              fontWeight: FontWeight.w600,
                            )),
                        const SizedBox(height: 4),
                        Text(
                          [
                            'Email',
                            if (thread.ticketId != null) thread.ticketId!
                          ].join(' · '),
                          style: theme.bodySmall.override(
                            fontFamily: theme.bodySmallFamily,
                            color: theme.secondaryText,
                          ),
                        ),
                        if (thread.pendingContext != null) ...[
                          const SizedBox(height: 6),
                          Text(thread.pendingContext!,
                              style: theme.bodySmall.override(
                                fontFamily: theme.bodySmallFamily,
                                color: theme.secondaryText,
                              )),
                        ],
                        const SizedBox(height: 22),
                        for (final message in thread.messages)
                          _ThreadMessageSection(
                            key: _messageKeys.putIfAbsent(
                                message.id, GlobalKey.new),
                            message: message,
                            highlighted:
                                message.id == targetId && _deepLinkHandled,
                            isLatest: message.id == latest.id,
                            expanded: _expandedMessageIds.contains(message.id),
                            showRemoteImages:
                                _remoteImages.contains(message.id),
                            theme: theme,
                            customerName: thread.customerId == null
                                ? null
                                : thread.sender,
                            onToggle: () => setState(() {
                              _expandedMessageIds.contains(message.id)
                                  ? _expandedMessageIds.remove(message.id)
                                  : _expandedMessageIds.add(message.id);
                            }),
                            onLoadImages: () =>
                                setState(() => _remoteImages.add(message.id)),
                            onLinkTap: _handleLink,
                            onOpenAttachment: _openAttachment,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _ReplyActions(
              theme: theme,
              onReply: () => _openComposer(EmailComposerMode.reply),
              onReplyAll: () => _openComposer(EmailComposerMode.replyAll),
              onForward: () => _openComposer(EmailComposerMode.forward),
            ),
          ],
        ),
      ),
    );
  }

  void _openComposer(EmailComposerMode mode) => context.push(
        '/email/${widget.threadId}/compose/${mode.name}',
      );

  Future<void> _handleLink(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    if (uri.scheme == 'mailto') {
      context.push('/email/compose?to=${Uri.encodeComponent(uri.path)}');
      return;
    }
    if (uri.scheme == 'tel') {
      ref.read(callSessionControllerProvider.notifier).startOutgoing(
            CallParty(displayName: uri.path, phoneNumber: uri.path),
          );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Open external link?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(raw, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                Navigator.pop(sheetContext);
                _snack(
                    'External browser opening is not enabled in UI-only mode');
              },
              child: const Text('Open link'),
            ),
          ]),
        ),
      ),
    );
  }

  void _openAttachment(EmailAttachment attachment) {
    _snack(attachment.localPath == null
        ? 'This fixture has no local file to open'
        : 'Attachment preview coming soon');
  }

  Future<void> _openActions(EmailThread thread) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (thread.customerId != null)
                ListTile(
                  leading: const Icon(IconsaxPlusBroken.user),
                  title: const Text('View customer'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('/customers/${thread.customerId}');
                  },
                )
              else
                ListTile(
                  leading: const Icon(IconsaxPlusBroken.user_add),
                  title: const Text('Add customer'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push(
                      '/customers/new?email=${Uri.encodeComponent(thread.latestMessage.from.address)}&name=${Uri.encodeComponent(thread.latestMessage.from.name ?? '')}',
                    );
                  },
                ),
              ListTile(
                leading: Icon(
                    thread.starred ? Icons.star_outline : Icons.star_border),
                title: Text(thread.starred ? 'Unstar' : 'Star'),
                onTap: () {
                  ref.read(emailStoreProvider.notifier).toggleStar(thread.id);
                  Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.mark_email_unread_outlined),
                title: const Text('Mark unread'),
                onTap: () {
                  ref.read(emailStoreProvider.notifier).markUnread(thread.id);
                  Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Archive'),
                onTap: () {
                  ref.read(emailStoreProvider.notifier).archive(thread.id);
                  Navigator.pop(sheetContext);
                  context.pop();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: FlutterFlowTheme.of(context).error),
                title: Text('Delete',
                    style:
                        TextStyle(color: FlutterFlowTheme.of(context).error)),
                onTap: () {
                  ref.read(emailStoreProvider.notifier).delete(thread.id);
                  Navigator.pop(sheetContext);
                  context.pop();
                },
              ),
            ]),
          ),
        ),
      );

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.thread,
      required this.theme,
      required this.onBack,
      required this.onActions});
  final EmailThread thread;
  final FlutterFlowTheme theme;
  final VoidCallback onBack;
  final VoidCallback onActions;
  @override
  Widget build(BuildContext context) => Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.alternate))),
        child: Row(children: [
          IconButton(
            tooltip: 'Back to email',
            onPressed: onBack,
            icon:
                Icon(IconsaxPlusBroken.arrow_left_2, color: theme.primaryText),
          ),
          Expanded(
              child: Text(thread.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyMedium.override(
                      fontFamily: theme.bodyMediumFamily,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryText))),
          IconButton(
            tooltip: 'Email actions',
            onPressed: onActions,
            icon: Icon(Icons.more_horiz, color: theme.primaryText),
          ),
        ]),
      );
}

class _ThreadMessageSection extends StatefulWidget {
  const _ThreadMessageSection({
    super.key,
    required this.message,
    required this.highlighted,
    required this.isLatest,
    required this.expanded,
    required this.showRemoteImages,
    required this.theme,
    required this.customerName,
    required this.onToggle,
    required this.onLoadImages,
    required this.onLinkTap,
    required this.onOpenAttachment,
  });
  final EmailThreadMessage message;
  final bool highlighted;
  final bool isLatest;
  final bool expanded;
  final bool showRemoteImages;
  final FlutterFlowTheme theme;
  final String? customerName;
  final VoidCallback onToggle;
  final VoidCallback onLoadImages;
  final ValueChanged<String> onLinkTap;
  final ValueChanged<EmailAttachment> onOpenAttachment;
  @override
  State<_ThreadMessageSection> createState() => _ThreadMessageSectionState();
}

class _ThreadMessageSectionState extends State<_ThreadMessageSection> {
  var _detailsVisible = false;
  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final avatar = message.from.label.isEmpty
        ? '?'
        : message.from.label.characters.first.toUpperCase();
    final attachments = message.attachments
        .where(
          (item) => item.disposition == EmailAttachmentDisposition.attachment,
        )
        .toList(growable: false);
    return Container(
      decoration: widget.highlighted
          ? BoxDecoration(
              color: widget.theme.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: widget.theme.primary.withValues(alpha: .3)),
            )
          : null,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.isLatest ? 0 : 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                    radius: 17,
                    backgroundColor: widget.theme.secondaryBackground,
                    child: Text(avatar,
                        style: TextStyle(color: widget.theme.primaryText))),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(message.from.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: widget.theme.bodyMedium.override(
                              fontFamily: widget.theme.bodyMediumFamily,
                              fontWeight: FontWeight.w600,
                              color: widget.theme.primaryText)),
                      Text(
                          message.direction == EmailDirection.outbound
                              ? 'to ${message.to.map((item) => item.label).join(', ')}'
                              : 'to me',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: widget.theme.bodySmall.override(
                              fontFamily: widget.theme.bodySmallFamily,
                              color: widget.theme.secondaryText)),
                      Text(_dateLabel(message.sentAt),
                          style: widget.theme.bodySmall.override(
                              fontFamily: widget.theme.bodySmallFamily,
                              color: widget.theme.secondaryText)),
                    ])),
                Icon(
                    widget.expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: widget.theme.secondaryText),
              ]),
            ),
          ),
          if (widget.expanded) ...[
            Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () =>
                        setState(() => _detailsVisible = !_detailsVisible),
                    child: Text(
                        _detailsVisible ? 'Hide details' : 'Show details'))),
            if (_detailsVisible)
              _Metadata(message: message, theme: widget.theme),
            const SizedBox(height: 4),
            SanitizedEmailBodyRenderer(
                body: message.body,
                theme: widget.theme,
                showRemoteImages: widget.showRemoteImages,
                onLoadRemoteImages: widget.onLoadImages,
                onLinkTap: widget.onLinkTap),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Attachments · ${attachments.length}',
                  style: widget.theme.bodyMedium.override(
                      fontFamily: widget.theme.bodyMediumFamily,
                      fontWeight: FontWeight.w600,
                      color: widget.theme.primaryText)),
              const SizedBox(height: 4),
              for (final attachment in attachments)
                _AttachmentRow(
                    attachment: attachment,
                    theme: widget.theme,
                    onTap: () => widget.onOpenAttachment(attachment)),
            ],
          ],
          if (!widget.isLatest)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Divider(color: widget.theme.alternate)),
        ]),
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.message, required this.theme});
  final EmailThreadMessage message;
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _line('From', message.from.address),
          _line('To', message.to.map((item) => item.address).join(', ')),
          if (message.replyTo != null)
            _line('Reply-To', message.replyTo!.address),
          if (message.cc.isNotEmpty)
            _line('Cc', message.cc.map((item) => item.address).join(', ')),
          _line('Date', _dateLabel(message.sentAt)),
          if (message.messageId != null)
            _line('Message-ID', message.messageId!),
        ]),
      );
  Widget _line(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
          text: TextSpan(
              style: theme.bodySmall.override(
                  fontFamily: theme.bodySmallFamily,
                  color: theme.secondaryText),
              children: [
            TextSpan(
                text: '$label  ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value)
          ])));
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow(
      {required this.attachment, required this.theme, required this.onTap});
  final EmailAttachment attachment;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(children: [
              Icon(
                  attachment.isImage
                      ? Icons.image_outlined
                      : Icons.insert_drive_file_outlined,
                  color: theme.secondaryText),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(attachment.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium.override(
                            fontFamily: theme.bodyMediumFamily,
                            color: theme.primaryText)),
                    Text(_bytes(attachment.byteCount),
                        style: theme.bodySmall.override(
                            fontFamily: theme.bodySmallFamily,
                            color: theme.secondaryText))
                  ])),
              Icon(
                  attachment.isBlocked
                      ? Icons.warning_amber_outlined
                      : Icons.open_in_new,
                  size: 18,
                  color:
                      attachment.isBlocked ? theme.error : theme.secondaryText),
            ])),
      );
}

class _ReplyActions extends StatelessWidget {
  const _ReplyActions(
      {required this.theme,
      required this.onReply,
      required this.onReplyAll,
      required this.onForward});
  final FlutterFlowTheme theme;
  final VoidCallback onReply;
  final VoidCallback onReplyAll;
  final VoidCallback onForward;
  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
            color: theme.primaryBackground,
            border: Border(top: BorderSide(color: theme.alternate))),
        child: Row(children: [
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: onReply,
                  icon: const Icon(Icons.reply_outlined),
                  label: const Text('Reply'))),
          const SizedBox(width: 8),
          IconButton(
              tooltip: 'Reply all',
              onPressed: onReplyAll,
              icon: const Icon(Icons.reply_all_outlined)),
          IconButton(
              tooltip: 'Forward',
              onPressed: onForward,
              icon: const Icon(Icons.forward_outlined))
        ]),
      ));
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.theme});
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child:
              Center(child: Text('Email not found', style: theme.bodyMedium))));
}

class _EmailThreadSkeleton extends StatelessWidget {
  const _EmailThreadSkeleton({required this.theme});
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: theme.primaryBackground,
        body: SafeArea(
          child: ExcludeSemantics(
            child: Column(children: [
              SizedBox(
                height: 56,
                child: Row(children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: context.pop,
                    icon: Icon(Icons.arrow_back, color: theme.primaryText),
                  ),
                  const SizedBox(width: 8),
                  OmniSkeleton(
                      width: 150, height: 14, baseTint: theme.alternate),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  OmniSkeleton(
                      width: 220, height: 22, baseTint: theme.alternate),
                  const SizedBox(height: 10),
                  OmniSkeleton(
                      width: 120, height: 11, baseTint: theme.alternate),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.secondaryBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.alternate),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OmniSkeleton(
                              width: 142,
                              height: 13,
                              baseTint: theme.alternate),
                          const SizedBox(height: 10),
                          OmniSkeleton(
                              width: 186,
                              height: 11,
                              baseTint: theme.alternate),
                          const SizedBox(height: 20),
                          for (var index = 0; index < 5; index++) ...[
                            OmniSkeleton(
                              width: index == 4 ? 154 : double.infinity,
                              height: 12,
                              baseTint: theme.alternate,
                            ),
                            if (index < 4) const SizedBox(height: 9),
                          ],
                        ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Row(children: [
                  Expanded(
                    child: OmniSkeleton(
                      width: double.infinity,
                      height: 44,
                      borderRadius: BorderRadius.circular(12),
                      baseTint: theme.alternate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OmniSkeleton(
                      width: double.infinity,
                      height: 44,
                      borderRadius: BorderRadius.circular(12),
                      baseTint: theme.alternate,
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
}

String _dateLabel(DateTime value) =>
    '${value.day}/${value.month}/${value.year} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _bytes(int count) => count >= 1000000
    ? '${(count / 1000000).toStringAsFixed(1)} MB'
    : '${(count / 1024).round()} KB';
