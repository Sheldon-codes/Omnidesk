import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../components/call_experience/call_session_controller.dart';
import '../../components/user_avatar/user_avatar.dart';
import '../../services/realtime/connection_monitor.dart';
import '../../services/realtime/realtime_event.dart';
import '../../services/realtime/realtime_service.dart';
import '../../services/realtime/typing_presence.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import 'conversation_room_page_model.dart';
import 'whatsapp_live_store.dart';
import 'widgets/conversation_composer.dart';
import 'widgets/conversation_media_widgets.dart';
import 'widgets/conversation_message_bubble.dart';

export 'conversation_room_page_model.dart';

class ConversationRoomPageWidget extends ConsumerStatefulWidget {
  const ConversationRoomPageWidget({super.key, required this.conversationId});

  static const routeName = 'ConversationRoomPage';
  static const routePath = '/chats/:conversationId';

  final String conversationId;

  @override
  ConsumerState<ConversationRoomPageWidget> createState() =>
      _ConversationRoomPageWidgetState();
}

class _ConversationRoomPageWidgetState
    extends ConsumerState<ConversationRoomPageWidget>
    with WidgetsBindingObserver {
  final _composerController = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _audioController = ConversationAudioController();
  final _messageKeys = <String, GlobalKey>{};
  WhatsAppThreadController? _liveStore;

  ConversationMessage? _replyingTo;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  Timer? _typingTimer;
  bool _initialJumpDone = false;
  String? _jumpForConversation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composerController.addListener(_scheduleTyping);
    if (_isLiveWhatsApp) {
      _liveStore = ref.read(whatsAppThreadsProvider.notifier);
    }
    if (_isLiveWhatsApp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _liveStore?.load(widget.conversationId);
        _liveStore?.startPolling(widget.conversationId);
      });
    }
  }

  void _scheduleTyping() {
    if (!_isLiveWhatsApp || _composerController.text.trim().isEmpty) return;
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      unawaited(ref
          .read(whatsAppThreadsProvider.notifier)
          .sendTyping(widget.conversationId));
    });
  }

  bool get _isLiveWhatsApp => int.tryParse(widget.conversationId) != null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isLiveWhatsApp) return;
    final store = _liveStore;
    if (store == null) return;
    if (state == AppLifecycleState.resumed) {
      store.startPolling(widget.conversationId);
    } else {
      store.stopPolling(widget.conversationId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isLiveWhatsApp) {
      _liveStore?.stopPolling(widget.conversationId);
    }
    _highlightTimer?.cancel();
    _typingTimer?.cancel();
    _composerController.removeListener(_scheduleTyping);
    _composerController.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    _audioController.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// Instant, non-animated jump used exactly once per conversation when the
  /// first messages render — the room opens already pinned to the latest
  /// message with no visible glide.
  void _jumpToLatest() {
    if (!mounted || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    _scrollController.jumpTo(max);
  }

  Future<void> _send(ConversationThread thread) async {
    final value = _composerController.text.trim();
    if (value.isEmpty) {
      _showSnack('Enter a message');
      return;
    }
    final online = ref.read(connectionMonitorProvider);
    try {
      if (_isLiveWhatsApp) {
        await ref.read(whatsAppThreadsProvider.notifier).send(
              thread.conversation.id,
              value,
              replyToId: _replyingTo?.id,
            );
        if (!online && mounted) {
          _showSnack('Offline — message queued, will send on reconnect');
        }
      } else {
        ref.read(conversationStoreProvider.notifier).sendText(
              thread.conversation.id,
              value,
              replyToId: _replyingTo?.id,
            );
      }
    } catch (_) {
      if (mounted) _showSnack('Message could not be sent. Try again.');
      return;
    }
    _composerController.clear();
    _composerFocusNode.unfocus();
    setState(() => _replyingTo = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
  }

  void _sendContent(
    ConversationThread thread,
    ConversationMessageContent content,
  ) {
    ref.read(conversationStoreProvider.notifier).sendContent(
          thread.conversation.id,
          content,
          replyToId: _replyingTo?.id,
        );
    setState(() => _replyingTo = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
  }

  void _startReply(ConversationMessage message) {
    setState(() => _replyingTo = message);
    _composerFocusNode.requestFocus();
  }

  Future<void> _jumpToMessage(
    ConversationThread thread,
    String messageId,
  ) async {
    final existingContext = _messageKeys[messageId]?.currentContext;
    if (existingContext != null) {
      await Scrollable.ensureVisible(
        existingContext,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: .32,
      );
    } else if (_scrollController.hasClients) {
      final index = thread.messages.indexWhere((item) => item.id == messageId);
      if (index < 0) return;
      final extent = _scrollController.position.maxScrollExtent;
      final fraction = thread.messages.length <= 1
          ? 0.0
          : index / (thread.messages.length - 1);
      await _scrollController.animateTo(
        extent * fraction,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
    if (!mounted) return;
    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final localThread =
        ref.watch(conversationThreadProvider(widget.conversationId));
    final liveState = _isLiveWhatsApp
        ? ref.watch(whatsAppThreadsProvider)[widget.conversationId]
        : null;
    final inboxThread = _isLiveWhatsApp
        ? ref
            .watch(whatsAppInboxProvider)
            .threads
            .where((item) => item.conversation.id == widget.conversationId)
            .firstOrNull
        : null;
    final thread = _isLiveWhatsApp ? liveState?.thread : localThread;
    final theme = FlutterFlowTheme.of(context);
    if (_isLiveWhatsApp && liveState?.error != null && thread == null) {
      return _LiveRoomError(
          theme: theme,
          onRetry: () => ref
              .read(whatsAppThreadsProvider.notifier)
              .load(widget.conversationId));
    }
    // Any live room without content yet shows the shimmer — first open,
    // reload, blank-but-loading timeline, or a stale entry left behind by
    // a previous visit (e.g. popped mid-load). Never _NotFound here.
    final showSkeleton = _isLiveWhatsApp &&
        (thread == null ||
            (thread.messages.isEmpty &&
                (liveState == null || liveState.loading)));
    if (showSkeleton) {
      return _ConversationRoomSkeleton(theme: theme, knownThread: inboxThread);
    }
    if (thread == null) return _NotFound(theme: theme);

    final conversation = thread.conversation;
    final resolved = conversation.status == ChatConversationStatus.resolved;
    final typing = _isLiveWhatsApp
        ? ref
            .watch(typingPresenceProvider(conversation.id))
            .values
            .where((t) => t.isTyping)
            .firstOrNull
        : null;
    final online = ref.watch(connectionMonitorProvider);
    final connState =
        _isLiveWhatsApp ? ref.watch(realtimeConnectionProvider).value : null;
    final degraded = _isLiveWhatsApp &&
        (!online ||
            liveState?.degraded == true ||
            connState == RealtimeConnectionState.degraded);
    // Auto-scroll when live messages land while the user is near the bottom.
    ref.listen(
        whatsAppThreadsProvider.select(
            (m) => m[widget.conversationId]?.thread?.messages.length ?? 0),
        (prev, next) {
      if (!mounted || next <= (prev ?? 0)) return;
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.extentAfter < 320) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
      }
    });
    // Pin to the latest message the moment the first batch renders.
    // jumpTo (not animateTo) so the open feels instant — no visible scroll.
    if (_jumpForConversation != widget.conversationId) {
      _jumpForConversation = widget.conversationId;
      _initialJumpDone = false;
    }
    if (!_initialJumpDone && thread.messages.isNotEmpty) {
      _initialJumpDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToLatest();
        // Second frame catches late layout growth (remote images sizing).
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
      });
    }
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _RoomHeader(
              thread: thread,
              theme: theme,
              onBack: () => context.pop(),
              onOpenCustomer: conversation.customerId == null
                  ? null
                  : () => context.push('/customers/${conversation.customerId}'),
              onActions: () => _openActions(thread),
            ),
            if (degraded)
              Container(
                width: double.infinity,
                color: theme.secondaryBackground,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(
                  'Reconnecting — new messages may be delayed',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.secondaryText, fontSize: 11),
                ),
              ),
            if (typing != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 14,
                      child: _TypingDots(color: theme.primary),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        typing.who == 'customer'
                            ? '${typing.displayName ?? conversation.name} is typing…'
                            : '${typing.displayName ?? 'Another agent'} is typing…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: theme.secondaryText, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ColoredBox(
                color: theme.secondaryBackground,
                child: _MessageTimeline(
                  thread: thread,
                  controller: _scrollController,
                  theme: theme,
                  audioController: _audioController,
                  messageKeys: _messageKeys,
                  highlightedMessageId: _highlightedMessageId,
                  onLoadOlder: () => ref
                      .read(conversationStoreProvider.notifier)
                      .loadOlderMessages(conversation.id),
                  onReply: _startReply,
                  onQuoteTap: (messageId) => _jumpToMessage(thread, messageId),
                  onLongPress: (message) =>
                      _openMessageActions(thread, message),
                  onReaction: (message, emoji) {
                    if (_isLiveWhatsApp) {
                      _showSnack(
                          'Reactions are not available for this channel');
                      return;
                    }
                    ref
                        .read(conversationStoreProvider.notifier)
                        .addReaction(conversation.id, message.id, emoji);
                  },
                  onRetry: (message) {
                    if (_isLiveWhatsApp) {
                      unawaited(ref
                          .read(whatsAppThreadsProvider.notifier)
                          .retry(conversation.id, message.id));
                      _showSnack('Retrying queued message');
                      return;
                    }
                    ref
                        .read(conversationStoreProvider.notifier)
                        .retryMessage(conversation.id, message.id);
                    _showSnack('Message queued to retry');
                  },
                  onLocation: (_) => _showSnack('Map integration coming later'),
                  onContact: (content) {
                    if (content.customerId case final customerId?) {
                      context.push('/customers/$customerId');
                    } else {
                      _showSnack('Add contact coming soon');
                    }
                  },
                ),
              ),
            ),
            if (resolved)
              ResolvedConversationComposer(
                theme: theme,
                onReopen: () => _reopen(thread),
              )
            else
              ConversationComposer(
                controller: _composerController,
                focusNode: _composerFocusNode,
                theme: theme,
                replyingTo: _replyingTo,
                onCancelReply: () => setState(() => _replyingTo = null),
                onAttach: () => _openAttachments(thread),
                onSend: () => _send(thread),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openActions(ConversationThread thread) async {
    final conversation = thread.conversation;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (conversation.customerId != null)
                ListTile(
                  leading: const Icon(IconsaxPlusBroken.user),
                  title: const Text('View customer'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('/customers/${conversation.customerId}');
                  },
                ),
              ListTile(
                leading: const Icon(IconsaxPlusBroken.call),
                title: const Text('Call customer'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final started = ref
                      .read(callSessionControllerProvider.notifier)
                      .startOutgoing(CallParty(
                        customerId: conversation.customerId,
                        displayName: conversation.name,
                        phoneNumber:
                            conversation.contactIdentifier ?? 'Unknown',
                        avatar: conversation.avatar,
                      ));
                  if (!started) {
                    _showSnack(
                      ref.read(callSessionControllerProvider).failureMessage ??
                          'Call already in progress',
                    );
                  }
                },
              ),
              if (_isLiveWhatsApp)
                ListTile(
                  leading: const Icon(IconsaxPlusBroken.document_text),
                  title: const Text('Saved replies'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _insertTemplate();
                  },
                ),
              if (!_isLiveWhatsApp)
                ListTile(
                  leading: const Icon(IconsaxPlusBroken.message_minus),
                  title: const Text('Mark unread'),
                  onTap: () {
                    ref
                        .read(conversationStoreProvider.notifier)
                        .markUnread(conversation.id);
                    Navigator.pop(sheetContext);
                  },
                ),
              ListTile(
                leading: Icon(
                  conversation.status == ChatConversationStatus.resolved
                      ? IconsaxPlusBroken.refresh
                      : IconsaxPlusBroken.tick_circle,
                ),
                title: Text(
                  conversation.status == ChatConversationStatus.resolved
                      ? 'Reopen conversation'
                      : 'Resolve conversation',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (conversation.status == ChatConversationStatus.resolved) {
                    _reopen(thread);
                  } else {
                    _confirmResolve(thread);
                  }
                },
              ),
              ListTile(
                leading: const Icon(IconsaxPlusBroken.info_circle),
                title: const Text('Conversation information'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openInfo(thread);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmResolve(ConversationThread thread) async {
    final shouldResolve = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Resolve conversation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('The conversation will become read-only.'),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Resolve'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (shouldResolve != true || !mounted) return;
    try {
      if (_isLiveWhatsApp) {
        await ref
            .read(whatsAppThreadsProvider.notifier)
            .status(thread.conversation.id, 'resolved');
      } else {
        ref
            .read(conversationStoreProvider.notifier)
            .resolve(thread.conversation.id);
      }
    } catch (_) {
      if (mounted) _showSnack('Unable to resolve the conversation. Try again.');
    }
  }

  Future<void> _reopen(ConversationThread thread) async {
    try {
      if (_isLiveWhatsApp) {
        await ref
            .read(whatsAppThreadsProvider.notifier)
            .status(thread.conversation.id, 'in_progress');
      } else {
        ref
            .read(conversationStoreProvider.notifier)
            .reopen(thread.conversation.id);
      }
    } catch (_) {
      if (mounted) _showSnack('Unable to reopen the conversation. Try again.');
    }
  }

  Future<void> _openInfo(ConversationThread thread) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Conversation information',
                    style: TextStyle(
                        color: FlutterFlowTheme.of(context).primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 18),
                _InfoRow('Customer', thread.conversation.name),
                _InfoRow('Channel', thread.conversation.channel.label),
                if (thread.conversation.ticketId case final ticket?)
                  _InfoRow('Ticket', ticket),
                _InfoRow(
                    'Status',
                    thread.conversation.status ==
                            ChatConversationStatus.resolved
                        ? 'Resolved'
                        : 'Open'),
                _InfoRow('Summary', thread.summary),
              ],
            ),
          ),
        ),
      );

  Future<void> _insertTemplate() async {
    try {
      final templates =
          await ref.read(whatsAppThreadsProvider.notifier).templates();
      if (!mounted) return;
      if (templates.isEmpty) {
        _showSnack('No saved replies are available');
        return;
      }
      final selected = await showModalBottomSheet<WhatsAppTemplate>(
        context: context,
        showDragHandle: true,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            children: [
              for (final template in templates)
                ListTile(
                  title: Text(template.title),
                  subtitle: Text(
                    template.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(context, template),
                ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      _composerController
        ..text = selected.body
        ..selection = TextSelection.collapsed(offset: selected.body.length);
      _composerFocusNode.requestFocus();
    } catch (_) {
      if (mounted) _showSnack('Saved replies could not be loaded. Try again.');
    }
  }

  Future<void> _openMessageActions(
    ConversationThread thread,
    ConversationMessage message,
  ) async {
    final theme = FlutterFlowTheme.of(context);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .34),
      builder: (dialogContext) => Dialog(
        backgroundColor: theme.primaryBackground,
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                conversationMessagePreview(message.content),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: theme.primaryText, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 13),
              if (!_isLiveWhatsApp)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    for (final emoji in const [
                      '👍',
                      '❤️',
                      '😂',
                      '😮',
                      '😢',
                      '🙏'
                    ])
                      Semantics(
                        button: true,
                        label: 'React with $emoji',
                        child: InkWell(
                          onTap: () {
                            ref
                                .read(conversationStoreProvider.notifier)
                                .addReaction(
                                    thread.conversation.id, message.id, emoji);
                            Navigator.pop(dialogContext);
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 21)),
                          ),
                        ),
                      ),
                    Semantics(
                      button: true,
                      label: 'More reactions',
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _showSnack('More reactions coming soon');
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: const Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(Icons.add_rounded, size: 21),
                        ),
                      ),
                    ),
                  ],
                ),
              if (!_isLiveWhatsApp) const Divider(height: 20),
              if (thread.capabilities.canReply)
                _MessageAction(
                  icon: Icons.reply_rounded,
                  label: 'Reply',
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _startReply(message);
                  },
                ),
              if (message.content case final TextMessageContent content)
                _MessageAction(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: content.text));
                    Navigator.pop(dialogContext);
                    _showSnack('Message copied');
                  },
                ),
              _MessageAction(
                icon: Icons.forward_rounded,
                label: 'Forward',
                onTap: () {
                  Navigator.pop(dialogContext);
                  _showSnack('Forwarding coming soon');
                },
              ),
              _MessageAction(
                icon: Icons.info_outline_rounded,
                label: 'Info',
                onTap: () {
                  Navigator.pop(dialogContext);
                  _showSnack('Message information coming soon');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAttachments(ConversationThread thread) async {
    if (_isLiveWhatsApp) {
      await _pickLiveAttachment(thread);
      return;
    }
    final capabilities = thread.capabilities;
    final choice = await showModalBottomSheet<_AttachmentChoice>(
      context: context,
      showDragHandle: true,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                enabled: false,
                leading: Icon(IconsaxPlusBroken.camera),
                title: Text('Camera'),
                subtitle: Text('Unavailable in the demo'),
              ),
              if (capabilities.canSendImages || capabilities.canSendVideo)
                ListTile(
                  leading: const Icon(IconsaxPlusBroken.gallery),
                  title: const Text('Photo or video'),
                  onTap: () => Navigator.pop(context, _AttachmentChoice.media),
                ),
              if (capabilities.canSendDocuments)
                ListTile(
                  leading: const Icon(IconsaxPlusBroken.document),
                  title: const Text('Document'),
                  onTap: () =>
                      Navigator.pop(context, _AttachmentChoice.document),
                ),
              if (capabilities.canSendLocations)
                ListTile(
                  leading: const Icon(IconsaxPlusBroken.location),
                  title: const Text('Location'),
                  onTap: () =>
                      Navigator.pop(context, _AttachmentChoice.location),
                ),
              if (capabilities.canSendContacts)
                ListTile(
                  leading: const Icon(IconsaxPlusBroken.user),
                  title: const Text('Contact'),
                  onTap: () =>
                      Navigator.pop(context, _AttachmentChoice.contact),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _AttachmentChoice.media:
        await _openDemoMediaPicker(thread);
      case _AttachmentChoice.document:
        _sendContent(
          thread,
          const DocumentMessageContent(
            assetPath: 'assets/demo/chat/fees_schedule.pdf',
            fileName: 'Fees_Schedule.pdf',
            mimeType: 'PDF',
            sizeLabel: '4 KB',
          ),
        );
      case _AttachmentChoice.location:
        _sendContent(
          thread,
          const LocationMessageContent(
            title: 'Kaizen School',
            subtitle: 'Nairobi',
            previewAssetPath: 'assets/demo/chat/map_preview.png',
            latitude: -1.286389,
            longitude: 36.817223,
          ),
        );
      case _AttachmentChoice.contact:
        _sendContent(
          thread,
          const ContactMessageContent(
            name: 'John Kamau',
            phone: '+254 720 000 000',
            avatar: 'J',
          ),
        );
    }
  }

  Future<void> _pickLiveAttachment(ConversationThread thread) async {
    try {
      final picked = await FilePicker.pickFile();
      final path = picked?.path;
      if (path == null || path.isEmpty) return;
      await ref.read(whatsAppThreadsProvider.notifier).send(
            thread.conversation.id,
            _composerController.text.trim(),
            replyToId: _replyingTo?.id,
            attachment: File(path),
          );
      _composerController.clear();
      _composerFocusNode.unfocus();
      if (mounted) setState(() => _replyingTo = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
    } catch (_) {
      if (mounted) _showSnack('Attachment could not be sent. Try again.');
    }
  }

  Future<void> _openDemoMediaPicker(ConversationThread thread) async {
    final selected = await showModalBottomSheet<_DemoMedia>(
      context: context,
      showDragHandle: true,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Demo media',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MediaPickerTile(
                      label: 'Error screenshot',
                      assetPath: 'assets/demo/chat/error_screenshot.png',
                      onTap: () => Navigator.pop(
                        context,
                        const _DemoMedia.image(
                            'assets/demo/chat/error_screenshot.png'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MediaPickerTile(
                      label: 'School photo',
                      assetPath: 'assets/demo/chat/school_photo.png',
                      onTap: () => Navigator.pop(
                        context,
                        const _DemoMedia.image(
                            'assets/demo/chat/school_photo.png'),
                      ),
                    ),
                  ),
                  if (thread.capabilities.canSendVideo) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MediaPickerTile(
                        label: 'Walkthrough',
                        assetPath: 'assets/demo/chat/school_photo.png',
                        video: true,
                        onTap: () => Navigator.pop(
                          context,
                          const _DemoMedia.video(
                            'assets/demo/chat/walkthrough.mp4',
                            'assets/demo/chat/school_photo.png',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final caption = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MediaComposerPage(media: selected),
      ),
    );
    if (!mounted || caption == null) return;
    if (selected.isVideo) {
      _sendContent(
        thread,
        VideoMessageContent(
          assetPath: selected.assetPath,
          thumbnailAssetPath: selected.thumbnailAssetPath!,
          duration: const Duration(seconds: 8),
          caption: caption.trim().isEmpty ? null : caption.trim(),
        ),
      );
    } else {
      _sendContent(
        thread,
        ImageMessageContent(
          assetPath: selected.assetPath,
          caption: caption.trim().isEmpty ? null : caption.trim(),
          width: 960,
          height: selected.assetPath.contains('error') ? 1280 : 720,
        ),
      );
    }
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.thread,
    required this.theme,
    required this.onBack,
    required this.onOpenCustomer,
    required this.onActions,
  });
  final ConversationThread thread;
  final FlutterFlowTheme theme;
  final VoidCallback onBack;
  final VoidCallback? onOpenCustomer;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final item = thread.conversation;
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        border: Border(bottom: BorderSide(color: theme.alternate)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back to chats',
            child: IconButton(
              onPressed: onBack,
              icon: Icon(IconsaxPlusBroken.arrow_left_2,
                  color: theme.primaryText),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onOpenCustomer,
              child: Row(
                children: [
                  UserAvatar(
                    imageUrl: item.avatarUrl,
                    initials: item.avatar ?? item.initials,
                    radius: 18,
                    backgroundColor: theme.secondaryBackground,
                    foregroundColor: theme.primaryText,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodyMedium.override(
                                fontFamily: theme.bodyMediumFamily,
                                color: theme.primaryText,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        Text(
                          '${item.channel.label}${item.ticketId == null ? '' : ' · ${item.ticketId}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodySmall.override(
                              fontFamily: theme.bodySmallFamily,
                              color: theme.secondaryText,
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Conversation actions',
            child: IconButton(
              onPressed: onActions,
              icon: Icon(IconsaxPlusBroken.more,
                  color: theme.primaryText, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTimeline extends StatelessWidget {
  const _MessageTimeline({
    required this.thread,
    required this.controller,
    required this.theme,
    required this.audioController,
    required this.messageKeys,
    required this.highlightedMessageId,
    required this.onLoadOlder,
    required this.onReply,
    required this.onQuoteTap,
    required this.onLongPress,
    required this.onReaction,
    required this.onRetry,
    required this.onLocation,
    required this.onContact,
  });

  final ConversationThread thread;
  final ScrollController controller;
  final FlutterFlowTheme theme;
  final ConversationAudioController audioController;
  final Map<String, GlobalKey> messageKeys;
  final String? highlightedMessageId;
  final VoidCallback onLoadOlder;
  final ValueChanged<ConversationMessage> onReply;
  final ValueChanged<String> onQuoteTap;
  final ValueChanged<ConversationMessage> onLongPress;
  final void Function(ConversationMessage, String) onReaction;
  final ValueChanged<ConversationMessage> onRetry;
  final ValueChanged<LocationMessageContent> onLocation;
  final ValueChanged<ContactMessageContent> onContact;

  @override
  Widget build(BuildContext context) {
    final items = _timelineItems(thread.messages);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels <= 0 && thread.hasOlderMessages) {
          onLoadOlder();
        }
        return false;
      },
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        itemCount: items.length + (thread.isLoadingOlderMessages ? 1 : 0),
        itemBuilder: (context, index) {
          if (thread.isLoadingOlderMessages && index == 0) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final item = items[index - (thread.isLoadingOlderMessages ? 1 : 0)];
          if (item case _DateItem(:final date)) {
            return _TimelineDate(date: date, theme: theme);
          }
          final messageItem = item as _MessageItem;
          final message = messageItem.message;
          final quoted = message.replyToId == null
              ? null
              : thread.messages
                  .where((item) => item.id == message.replyToId)
                  .firstOrNull;
          return KeyedSubtree(
            key: messageKeys.putIfAbsent(message.id, GlobalKey.new),
            child: ConversationMessageBubble(
              message: message,
              quoted: quoted,
              groupPosition: messageItem.groupPosition,
              customerInitial: thread.conversation.initials,
              customerAvatarUrl: thread.conversation.avatarUrl,
              theme: theme,
              audioController: audioController,
              canReply: thread.capabilities.canReply,
              highlighted: highlightedMessageId == message.id,
              onReply: onReply,
              onQuoteTap: onQuoteTap,
              onLongPress: onLongPress,
              onReaction: onReaction,
              onRetry: onRetry,
              onLocation: onLocation,
              onContact: onContact,
            ),
          );
        },
      ),
    );
  }

  List<Object> _timelineItems(List<ConversationMessage> messages) {
    final items = <Object>[];
    DateTime? activeDate;
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final date = DateUtils.dateOnly(message.sentAt);
      if (activeDate == null || date != activeDate) {
        items.add(_DateItem(date));
        activeDate = date;
      }
      if (message.content is SystemMessageContent) {
        items.add(_MessageItem(message, MessageGroupPosition.single));
        continue;
      }
      final joinsPrevious =
          index > 0 && _canGroup(messages[index - 1], message);
      final joinsNext = index < messages.length - 1 &&
          _canGroup(message, messages[index + 1]);
      final position = switch ((joinsPrevious, joinsNext)) {
        (false, false) => MessageGroupPosition.single,
        (false, true) => MessageGroupPosition.first,
        (true, true) => MessageGroupPosition.middle,
        (true, false) => MessageGroupPosition.last,
      };
      items.add(_MessageItem(message, position));
    }
    return items;
  }

  bool _canGroup(ConversationMessage first, ConversationMessage second) {
    if (first.sender != second.sender ||
        first.sender == MessageSender.system ||
        first.content is SystemMessageContent ||
        second.content is SystemMessageContent ||
        !DateUtils.isSameDay(first.sentAt, second.sentAt)) {
      return false;
    }
    return second.sentAt.difference(first.sentAt).inMinutes.abs() <= 5;
  }
}

class _DateItem {
  const _DateItem(this.date);
  final DateTime date;
}

class _MessageItem {
  const _MessageItem(this.message, this.groupPosition);
  final ConversationMessage message;
  final MessageGroupPosition groupPosition;
}

class _TimelineDate extends StatelessWidget {
  const _TimelineDate({required this.date, required this.theme});
  final DateTime date;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            DateUtils.isSameDay(date, DateTime(2026, 8, 29))
                ? 'Today'
                : DateFormat('MMM d').format(date),
            style: theme.bodySmall.override(
                fontFamily: theme.bodySmallFamily,
                color: theme.secondaryText,
                fontSize: 10.5),
          ),
        ),
      );
}

enum _AttachmentChoice { media, document, location, contact }

class _DemoMedia {
  const _DemoMedia.image(this.assetPath)
      : thumbnailAssetPath = null,
        isVideo = false;
  const _DemoMedia.video(this.assetPath, this.thumbnailAssetPath)
      : isVideo = true;
  final String assetPath;
  final String? thumbnailAssetPath;
  final bool isVideo;
}

class _MediaPickerTile extends StatelessWidget {
  const _MediaPickerTile({
    required this.label,
    required this.assetPath,
    required this.onTap,
    this.video = false,
  });
  final String label;
  final String assetPath;
  final VoidCallback onTap;
  final bool video;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(assetPath,
                          fit: BoxFit.cover, cacheWidth: 400),
                      if (video)
                        const Center(
                          child: Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white, size: 36),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
}

class _MediaComposerPage extends StatefulWidget {
  const _MediaComposerPage({required this.media});
  final _DemoMedia media;

  @override
  State<_MediaComposerPage> createState() => _MediaComposerPageState();
}

class _MediaComposerPageState extends State<_MediaComposerPage> {
  final _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.media.isVideo ? 'Video preview' : 'Photo preview',
            style: const TextStyle(fontSize: 16)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(widget.media.thumbnailAssetPath ??
                        widget.media.assetPath),
                    if (widget.media.isVideo)
                      const Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white, size: 56),
                  ],
                ),
              ),
            ),
            Container(
              color: theme.primaryBackground,
              padding: const EdgeInsets.fromLTRB(14, 9, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'Add a caption…',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Send media',
                    onPressed: () =>
                        Navigator.pop(context, _captionController.text),
                    style: IconButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: theme.primaryBackground),
                    icon: const Icon(IconsaxPlusBroken.send_1, size: 19),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(label),
        onTap: onTap,
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(label,
                  style: TextStyle(
                      color: FlutterFlowTheme.of(context).secondaryText,
                      fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.theme});
  final FlutterFlowTheme theme;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: theme.primaryBackground,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Conversation not found',
                    style: TextStyle(color: theme.primaryText, fontSize: 16)),
                const SizedBox(height: 12),
                TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Back to chats')),
              ],
            ),
          ),
        ),
      );
}

class _ConversationRoomSkeleton extends StatelessWidget {
  const _ConversationRoomSkeleton({required this.theme, this.knownThread});

  final FlutterFlowTheme theme;
  final ConversationThread? knownThread;

  @override
  Widget build(BuildContext context) {
    final base = theme.alternate.withValues(alpha: .56);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      body: SafeArea(
        child: ExcludeSemantics(
          child: Column(
            children: [
              if (knownThread case final thread?)
                _RoomHeader(
                  thread: thread,
                  theme: theme,
                  onBack: () => context.pop(),
                  onOpenCustomer: thread.conversation.customerId == null
                      ? null
                      : () => context.push(
                            '/customers/${thread.conversation.customerId}',
                          ),
                  onActions: () {},
                )
              else
                Container(
                  height: 68,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: theme.primaryBackground,
                    border: Border(bottom: BorderSide(color: theme.alternate)),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 48),
                    _RoomSkeletonShape(
                        color: base, width: 36, height: 36, round: true),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _RoomSkeletonShape(
                              color: base, width: 126, height: 13),
                          const SizedBox(height: 7),
                          _RoomSkeletonShape(
                              color: base, width: 90, height: 10),
                        ])),
                    const SizedBox(width: 48),
                  ]),
                ),
              Expanded(
                child: ColoredBox(
                  color: theme.secondaryBackground,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                    children: [
                      Center(
                        child: _RoomSkeletonShape(
                          color: base,
                          width: 44,
                          height: 10,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _TimelineSkeletonBubble(
                        color: base,
                        alignment: Alignment.centerLeft,
                        width: 154,
                        height: 48,
                        withAvatar: true,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(15),
                          topRight: Radius.circular(15),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(15),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _TimelineSkeletonBubble(
                        color: base,
                        alignment: Alignment.centerLeft,
                        width: 202,
                        height: 64,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(15),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(15),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _TimelineSkeletonBubble(
                        color: base,
                        alignment: Alignment.centerRight,
                        width: 178,
                        height: 55,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(15),
                          topRight: Radius.circular(15),
                          bottomLeft: Radius.circular(15),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _TimelineSkeletonBubble(
                        color: base,
                        alignment: Alignment.centerRight,
                        width: 112,
                        height: 46,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(15),
                          topRight: Radius.circular(4),
                          bottomLeft: Radius.circular(15),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: theme.primaryBackground,
                  border: Border(top: BorderSide(color: theme.alternate)),
                ),
                padding: const EdgeInsets.fromLTRB(8, 7, 10, 9),
                child: Row(children: [
                  _RoomSkeletonShape(
                      color: base, width: 44, height: 44, round: true),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _RoomSkeletonShape(
                      color: base,
                      width: double.infinity,
                      height: 44,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(width: 7),
                  _RoomSkeletonShape(
                      color: theme.primary.withValues(alpha: .5),
                      width: 44,
                      height: 44,
                      round: true),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomSkeletonShape extends StatelessWidget {
  const _RoomSkeletonShape({
    required this.color,
    required this.width,
    required this.height,
    this.round = false,
    this.borderRadius,
  });

  final Color color;
  final double width;
  final double height;
  final bool round;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => _RoomShimmer(
        color: color,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius:
                borderRadius ?? BorderRadius.circular(round ? width : 12),
          ),
        ),
      );
}

class _TimelineSkeletonBubble extends StatelessWidget {
  const _TimelineSkeletonBubble({
    required this.color,
    required this.alignment,
    required this.width,
    required this.height,
    required this.borderRadius,
    this.withAvatar = false,
  });

  final Color color;
  final Alignment alignment;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final bool withAvatar;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (withAvatar) ...[
              _RoomSkeletonShape(
                  color: color, width: 26, height: 26, round: true),
              const SizedBox(width: 6),
            ],
            _RoomSkeletonShape(
              color: color,
              width: width,
              height: height,
              borderRadius: borderRadius,
            ),
          ],
        ),
      );
}

class _RoomShimmer extends StatefulWidget {
  const _RoomShimmer({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  State<_RoomShimmer> createState() => _RoomShimmerState();
}

class _RoomShimmerState extends State<_RoomShimmer>
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
    if (MediaQuery.disableAnimationsOf(context)) {
      return ColoredBox(color: widget.color, child: widget.child);
    }
    // Bright highlight band sweeping across the shape — a real shine sweep
    // rather than a subtle pulse. The band is lerped toward white so it
    // reads on both light and dark themes.
    final shine = Color.lerp(widget.color, Colors.white, .72) ?? Colors.white;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [widget.color, shine, widget.color],
          stops: const [.32, .5, .68],
          begin: Alignment(-1.9 + _controller.value * 3.8, -.25),
          end: Alignment(-.9 + _controller.value * 3.8, .25),
        ).createShader(bounds),
        child: ColoredBox(color: widget.color, child: child),
      ),
    );
  }
}

class _LiveRoomError extends StatelessWidget {
  const _LiveRoomError({required this.theme, required this.onRetry});
  final FlutterFlowTheme theme;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: theme.primaryBackground,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_off_outlined, color: theme.secondaryText),
                const SizedBox(height: 12),
                Text('Unable to load this conversation',
                    style: TextStyle(
                        color: theme.primaryText, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('Check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.secondaryText, fontSize: 13)),
                const SizedBox(height: 14),
                OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
                TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Back to chats')),
              ]),
            ),
          ),
        ),
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
        ],
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < 3; i++)
            Opacity(
              opacity: _dotOpacity(_controller.value, i),
              child: Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }

  /// Triangle wave in [0.35, 1.0] — staggered per dot. Plain arithmetic with
  /// no `%`/`*` precedence traps and no path outside [0, 1].
  double _dotOpacity(double t, int index) {
    final phase = (t * 1.2 - index * 0.25) % 1.0;
    final triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return (0.35 + 0.65 * triangle).clamp(0.0, 1.0);
  }
}
