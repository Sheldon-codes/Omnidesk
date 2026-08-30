import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../flutter_flow/flutter_flow_theme.dart';
import '../conversation_room_page_model.dart';

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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FlutterFlowTheme theme;
  final ConversationMessage? replyingTo;
  final VoidCallback onCancelReply;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
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
}

class ResolvedConversationComposer extends StatelessWidget {
  const ResolvedConversationComposer({
    super.key,
    required this.theme,
    required this.onReopen,
  });
  final FlutterFlowTheme theme;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 11, 12, 12),
          decoration: BoxDecoration(
            color: theme.primaryBackground,
            border: Border(top: BorderSide(color: theme.alternate)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Conversation resolved',
                        style: TextStyle(
                            color: theme.primaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Reopen to continue replying',
                        style: TextStyle(
                            color: theme.secondaryText, fontSize: 11)),
                  ],
                ),
              ),
              TextButton(onPressed: onReopen, child: const Text('Reopen')),
            ],
          ),
        ),
      );
}

class _ReplyComposerPreview extends StatelessWidget {
  const _ReplyComposerPreview({
    required this.message,
    required this.theme,
    required this.onClose,
  });
  final ConversationMessage message;
  final FlutterFlowTheme theme;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          border: Border(
            left: BorderSide(color: theme.primary, width: 2),
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
                        color: theme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversationMessagePreview(message.content),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.secondaryText, fontSize: 11),
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
                    size: 18, color: theme.secondaryText),
              ),
            ),
          ],
        ),
      );
}
