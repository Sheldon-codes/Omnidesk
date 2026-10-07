import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../flutter_flow/flutter_flow_theme.dart';
import '../conversation_room_page_model.dart';
import 'whatsapp_chat_style.dart';

class ConversationComposer extends StatelessWidget {
  const ConversationComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.theme,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onAttach,
    required this.onSend,
    this.whatsAppPalette,
    this.onSavedReplies,
    this.attachPanelOpen = false,
    this.bottomSafeArea = true,
    this.canAttach = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FlutterFlowTheme theme;
  final ConversationMessage? replyingTo;
  final VoidCallback onCancelReply;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final bool canAttach;
  final WhatsAppChatPalette? whatsAppPalette;
  final VoidCallback? onSavedReplies;

  /// true while the attachment grid is open: the + becomes a keyboard icon.
  final bool attachPanelOpen;

  /// Set false while the attachment panel is shown under the composer so the
  /// home-indicator padding isn't applied twice.
  final bool bottomSafeArea;

  @override
  Widget build(BuildContext context) => whatsAppPalette == null
      ? _buildDefault(context)
      : _buildWhatsApp(context, whatsAppPalette!);

  Widget _buildDefault(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: theme.primaryBackground,
            border: Border(top: BorderSide(color: theme.alternate)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyingTo case final message?)
                _ReplyComposerPreview(
                  message: message,
                  theme: theme,
                  onClose: onCancelReply,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 10, 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (canAttach)
                      Semantics(
                        button: true,
                        label: 'Add attachment',
                        child: IconButton(
                          onPressed: onAttach,
                          tooltip: 'Attach',
                          icon: Icon(Icons.add_rounded,
                              color: theme.secondaryText, size: 25),
                        ),
                      ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onTapOutside: (_) => focusNode.unfocus(),
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: 'Type a message…',
                            hintStyle: TextStyle(
                                color: theme.secondaryText, fontSize: 14),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 11),
                            filled: true,
                            fillColor: theme.secondaryBackground,
                            border: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Semantics(
                      button: true,
                      label: 'Send message',
                      child: IconButton.filled(
                        onPressed: onSend,
                        tooltip: 'Send message',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          backgroundColor: theme.primary,
                          foregroundColor: theme.primaryBackground,
                        ),
                        icon: const Icon(IconsaxPlusBroken.send_1, size: 19),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildWhatsApp(BuildContext context, WhatsAppChatPalette palette) =>
      Container(
        color: palette.chrome,
        child: SafeArea(
          top: false,
          bottom: bottomSafeArea,
          child: Container(
            decoration: BoxDecoration(
              color: palette.chrome,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyingTo case final message?)
                  _ReplyComposerPreview(
                    message: message,
                    theme: theme,
                    onClose: onCancelReply,
                    whatsAppPalette: palette,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 5, 7, 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (canAttach)
                        Semantics(
                          button: true,
                          label: attachPanelOpen
                              ? 'Show keyboard'
                              : 'Add attachment',
                          child: IconButton(
                            onPressed: onAttach,
                            tooltip: attachPanelOpen ? 'Keyboard' : 'Attach',
                            constraints: const BoxConstraints.tightFor(
                                width: 44, height: 44),
                            icon: Icon(
                                attachPanelOpen
                                    ? Icons.keyboard_alt_outlined
                                    : Icons.add_rounded,
                                color: palette.text,
                                size: attachPanelOpen ? 26 : 28),
                          ),
                        ),
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          decoration: BoxDecoration(
                            color: palette.field,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.only(left: 14, right: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  onTapOutside: (_) => focusNode.unfocus(),
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  minLines: 1,
                                  maxLines: 5,
                                  style: TextStyle(
                                      color: palette.text, fontSize: 16),
                                  decoration: InputDecoration(
                                    hintText: 'Message',
                                    hintStyle: TextStyle(
                                        color: palette.muted, fontSize: 16),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              if (onSavedReplies != null)
                                Semantics(
                                  button: true,
                                  label: 'Insert saved reply',
                                  child: IconButton(
                                    onPressed: onSavedReplies,
                                    tooltip: 'Saved replies',
                                    constraints: const BoxConstraints.tightFor(
                                        width: 40, height: 44),
                                    icon: Icon(IconsaxPlusBroken.document_text,
                                        color: palette.muted, size: 22),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) {
                          final canSend = value.text.trim().isNotEmpty;
                          // Like WhatsApp: no send button until there is text.
                          return AnimatedSize(
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOut,
                            alignment: Alignment.centerRight,
                            child: canSend
                                ? Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Semantics(
                                      button: true,
                                      label: 'Send message',
                                      child: IconButton.filled(
                                        onPressed: onSend,
                                        tooltip: 'Send message',
                                        constraints:
                                            const BoxConstraints.tightFor(
                                                width: 44, height: 44),
                                        style: IconButton.styleFrom(
                                          backgroundColor: palette.accent,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.send_rounded,
                                            size: 19),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class ResolvedConversationComposer extends StatelessWidget {
  const ResolvedConversationComposer({
    super.key,
    required this.theme,
    required this.onReopen,
    this.whatsAppPalette,
  });
  final FlutterFlowTheme theme;
  final VoidCallback onReopen;
  final WhatsAppChatPalette? whatsAppPalette;

  @override
  Widget build(BuildContext context) => Container(
        color: whatsAppPalette?.chrome ?? theme.primaryBackground,
        child: SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 11, 12, 12),
            decoration: BoxDecoration(
              color: whatsAppPalette?.chrome ?? theme.primaryBackground,
              border: Border(
                  top: BorderSide(
                      color: whatsAppPalette?.divider ?? theme.alternate)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Conversation resolved',
                          style: TextStyle(
                              color: whatsAppPalette?.text ?? theme.primaryText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Reopen to continue replying',
                          style: TextStyle(
                              color:
                                  whatsAppPalette?.muted ?? theme.secondaryText,
                              fontSize: 11)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onReopen,
                  style: whatsAppPalette == null
                      ? null
                      : TextButton.styleFrom(
                          foregroundColor: whatsAppPalette!.accent),
                  child: const Text('Reopen'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ReplyComposerPreview extends StatelessWidget {
  const _ReplyComposerPreview({
    required this.message,
    required this.theme,
    required this.onClose,
    this.whatsAppPalette,
  });
  final ConversationMessage message;
  final FlutterFlowTheme theme;
  final VoidCallback onClose;
  final WhatsAppChatPalette? whatsAppPalette;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
        decoration: BoxDecoration(
          color: whatsAppPalette?.field ?? theme.secondaryBackground,
          border: Border(
            left: BorderSide(
                color: whatsAppPalette?.accent ?? theme.primary, width: 2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.sender == MessageSender.agent
                        ? 'Replying to yourself'
                        : 'Replying to customer',
                    style: TextStyle(
                        color: whatsAppPalette?.accent ?? theme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversationMessagePreview(message.content),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: whatsAppPalette?.muted ?? theme.secondaryText,
                        fontSize: 11),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Cancel reply',
              child: IconButton(
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded,
                    size: 18,
                    color: whatsAppPalette?.muted ?? theme.secondaryText),
              ),
            ),
          ],
        ),
      );
}
