import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import '../../../flutter_flow/flutter_flow_theme.dart';
import '../conversation_room_page_model.dart';
import 'conversation_media_widgets.dart';

enum MessageGroupPosition { single, first, middle, last }

class ConversationMessageBubble extends StatefulWidget {
  const ConversationMessageBubble({
    super.key,
    required this.message,
    required this.quoted,
    required this.groupPosition,
    required this.customerInitial,
    required this.theme,
    required this.audioController,
    required this.canReply,
    required this.highlighted,
    required this.onReply,
    required this.onQuoteTap,
    required this.onLongPress,
    required this.onReaction,
    required this.onRetry,
    required this.onLocation,
    required this.onContact,
  });

  final ConversationMessage message;
  final ConversationMessage? quoted;
  final MessageGroupPosition groupPosition;
  final String customerInitial;
  final FlutterFlowTheme theme;
  final ConversationAudioController audioController;
  final bool canReply;
  final bool highlighted;
  final ValueChanged<ConversationMessage> onReply;
  final ValueChanged<String> onQuoteTap;
  final ValueChanged<ConversationMessage> onLongPress;
  final void Function(ConversationMessage message, String emoji) onReaction;
  final ValueChanged<ConversationMessage> onRetry;
  final ValueChanged<LocationMessageContent> onLocation;
  final ValueChanged<ContactMessageContent> onContact;

  @override
  State<ConversationMessageBubble> createState() =>
      _ConversationMessageBubbleState();
}

class _ConversationMessageBubbleState extends State<ConversationMessageBubble> {
  static const _threshold = 42.0;
  double _drag = 0;
  bool _thresholdFeedbackSent = false;

  bool get _agent => widget.message.sender == MessageSender.agent;

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.canReply) return;
    final preferredDelta = _agent ? -details.delta.dx : details.delta.dx;
    if (preferredDelta <= 0 && _drag <= 0) return;
    final next = (_drag + preferredDelta).clamp(0.0, 58.0);
    if (next >= _threshold && !_thresholdFeedbackSent) {
      _thresholdFeedbackSent = true;
      HapticFeedback.selectionClick();
    } else if (next < _threshold) {
      _thresholdFeedbackSent = false;
    }
    setState(() => _drag = next);
  }

  void _onDragEnd(DragEndDetails _) {
    if (_drag >= _threshold) widget.onReply(widget.message);
    setState(() {
      _drag = 0;
      _thresholdFeedbackSent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.content case final SystemMessageContent content) {
      return _SystemEvent(content: content, theme: widget.theme);
    }
    final bubble = _buildBubble(context);
    return Padding(
      padding: EdgeInsets.only(
        top: switch (widget.groupPosition) {
          MessageGroupPosition.single || MessageGroupPosition.first => 9,
          _ => 2,
        },
        bottom: widget.message.reactions.isEmpty ? 1 : 9,
      ),
      child: Stack(
        alignment: _agent ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          Positioned(
            left: _agent ? null : 10,
            right: _agent ? 10 : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: (_drag / _threshold).clamp(0, 1),
              child: Icon(Icons.reply_rounded,
                  size: 20, color: widget.theme.secondaryText),
            ),
          ),
          AnimatedContainer(
            duration:
                _drag == 0 ? const Duration(milliseconds: 170) : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_agent ? -_drag : _drag, 0, 0),
            decoration: widget.highlighted
                ? BoxDecoration(
                    color: widget.theme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(16),
                  )
                : null,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onHorizontalDragCancel: () =>
                  _onDragEnd(DragEndDetails(primaryVelocity: 0)),
              onLongPress: () => widget.onLongPress(widget.message),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(BuildContext context) {
    final color =
        _agent ? widget.theme.primary : widget.theme.primaryBackground;
    final textColor =
        _agent ? widget.theme.primaryBackground : widget.theme.primaryText;
    final showAvatar = !_agent &&
        (widget.groupPosition == MessageGroupPosition.single ||
            widget.groupPosition == MessageGroupPosition.last);
    return Row(
      mainAxisAlignment:
          _agent ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!_agent)
          SizedBox(
            width: 32,
            child: showAvatar
                ? CircleAvatar(
                    radius: 13,
                    backgroundColor: widget.theme.secondaryBackground,
                    child: Text(widget.customerInitial,
                        style: TextStyle(
                            color: widget.theme.primaryText, fontSize: 10)),
                  )
                : null,
          ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(MediaQuery.sizeOf(context).width * .78, 340),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: color,
                borderRadius: _bubbleRadius(_agent, widget.groupPosition),
                child: InkWell(
                  onTap: widget.message.delivery == MessageDelivery.failed
                      ? () => widget.onRetry(widget.message)
                      : null,
                  borderRadius: _bubbleRadius(_agent, widget.groupPosition),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 9, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.quoted case final quoted?)
                          _QuotedMessagePreview(
                            message: quoted,
                            textColor: textColor,
                            onTap: () => widget.onQuoteTap(quoted.id),
                          ),
                        _MessageContentRenderer(
                          message: widget.message,
                          textColor: textColor,
                          audioController: widget.audioController,
                          onLocation: widget.onLocation,
                          onContact: widget.onContact,
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: _MessageMetadata(
                            message: widget.message,
                            textColor: textColor,
                            readColor: _agent
                                ? widget.theme.secondary
                                : widget.theme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.message.reactions.isNotEmpty)
                Positioned(
                  right: _agent ? 8 : null,
                  left: _agent ? null : 8,
                  bottom: -15,
                  child: _ReactionSummary(
                    reactions: widget.message.reactions,
                    theme: widget.theme,
                    onTap: (emoji) => widget.onReaction(widget.message, emoji),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageContentRenderer extends StatelessWidget {
  const _MessageContentRenderer({
    required this.message,
    required this.textColor,
    required this.audioController,
    required this.onLocation,
    required this.onContact,
  });
  final ConversationMessage message;
  final Color textColor;
  final ConversationAudioController audioController;
  final ValueChanged<LocationMessageContent> onLocation;
  final ValueChanged<ContactMessageContent> onContact;

  @override
  Widget build(BuildContext context) => switch (message.content) {
        TextMessageContent(:final text) => Text(text,
            style: TextStyle(color: textColor, fontSize: 14, height: 1.35)),
        final ImageMessageContent content => ConversationImageMessage(
            content: content,
            textColor: textColor,
            onOpen: () => showConversationImageViewer(context, content)),
        final VideoMessageContent content => ConversationVideoMessage(
            content: content,
            textColor: textColor,
            onOpen: () => showConversationVideoViewer(context, content)),
        final AudioMessageContent content => ConversationAudioMessage(
            content: content,
            textColor: textColor,
            controller: audioController),
        final DocumentMessageContent content => ConversationDocumentMessage(
            content: content,
            textColor: textColor,
            onOpen: () => openBundledDocument(content)),
        final LocationMessageContent content => ConversationLocationMessage(
            content: content,
            textColor: textColor,
            onOpen: () => onLocation(content)),
        final ContactMessageContent content => ConversationContactMessage(
            content: content,
            textColor: textColor,
            onOpen: () => onContact(content)),
        UnsupportedMessageContent(:final description) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(IconsaxPlusBroken.info_circle,
                  color: textColor.withValues(alpha: .76), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(description,
                    style: TextStyle(
                        color: textColor.withValues(alpha: .84),
                        fontSize: 13,
                        height: 1.35)),
              ),
            ],
          ),
        SystemMessageContent() => const SizedBox.shrink(),
      };
}

class _QuotedMessagePreview extends StatelessWidget {
  const _QuotedMessagePreview({
    required this.message,
    required this.textColor,
    required this.onTap,
  });
  final ConversationMessage message;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Jump to quoted message',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.fromLTRB(8, 6, 7, 6),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(7),
              border: Border(
                left: BorderSide(
                    color: textColor.withValues(alpha: .65), width: 2),
              ),
            ),
            child: Row(
              children: [
                _QuoteTypeIcon(content: message.content, color: textColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.sender == MessageSender.agent
                            ? 'You'
                            : 'Customer',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        conversationMessagePreview(message.content),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: textColor.withValues(alpha: .77),
                            fontSize: 11,
                            height: 1.25),
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

class _QuoteTypeIcon extends StatelessWidget {
  const _QuoteTypeIcon({required this.content, required this.color});
  final ConversationMessageContent content;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final icon = switch (content) {
      ImageMessageContent() => Icons.image_outlined,
      VideoMessageContent() => Icons.play_circle_outline,
      AudioMessageContent() => Icons.mic_none_rounded,
      DocumentMessageContent() => Icons.insert_drive_file_outlined,
      LocationMessageContent() => Icons.location_on_outlined,
      ContactMessageContent() => Icons.person_outline,
      _ => null,
    };
    return icon == null
        ? const SizedBox.shrink()
        : Icon(icon, color: color.withValues(alpha: .7), size: 16);
  }
}

class _MessageMetadata extends StatelessWidget {
  const _MessageMetadata({
    required this.message,
    required this.textColor,
    required this.readColor,
  });
  final ConversationMessage message;
  final Color textColor;
  final Color readColor;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat('HH:mm').format(message.sentAt),
              style: TextStyle(
                  color: textColor.withValues(alpha: .66), fontSize: 9.5)),
          if (message.sender == MessageSender.agent) ...[
            const SizedBox(width: 3),
            _DeliveryIcon(
                delivery: message.delivery,
                color: textColor.withValues(alpha: .72),
                readColor: readColor),
          ],
        ],
      );
}

class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({
    required this.delivery,
    required this.color,
    required this.readColor,
  });
  final MessageDelivery delivery;
  final Color color;
  final Color readColor;

  @override
  Widget build(BuildContext context) => switch (delivery) {
        MessageDelivery.sending => SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.2, color: color)),
        MessageDelivery.sent =>
          Icon(Icons.check_rounded, size: 13, color: color),
        MessageDelivery.delivered =>
          Icon(Icons.done_all_rounded, size: 13, color: color),
        MessageDelivery.read =>
          Icon(Icons.done_all_rounded, size: 13, color: readColor),
        MessageDelivery.failed =>
          Icon(Icons.error_outline_rounded, size: 13, color: readColor),
        MessageDelivery.none => const SizedBox.shrink(),
      };
}

class _ReactionSummary extends StatelessWidget {
  const _ReactionSummary({
    required this.reactions,
    required this.theme,
    required this.onTap,
  });
  final List<MessageReaction> reactions;
  final FlutterFlowTheme theme;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          border: Border.all(color: theme.alternate),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final reaction in reactions)
              GestureDetector(
                onTap: () => onTap(reaction.emoji),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '${reaction.emoji}${reaction.count > 1 ? ' ${reaction.count}' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: reaction.reactedByAgent
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _SystemEvent extends StatelessWidget {
  const _SystemEvent({required this.content, required this.theme});
  final SystemMessageContent content;
  final FlutterFlowTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Row(
          children: [
            Expanded(child: Divider(color: theme.alternate)),
            const SizedBox(width: 10),
            if (content.emphasized) ...[
              Icon(IconsaxPlusBroken.ticket,
                  size: 13, color: theme.secondaryText),
              const SizedBox(width: 5),
            ],
            Flexible(
              flex: 3,
              child: Text(content.text,
                  textAlign: TextAlign.center,
                  style: theme.bodySmall.override(
                      fontFamily: theme.bodySmallFamily,
                      color: theme.secondaryText,
                      fontSize: 10.5,
                      fontWeight: content.emphasized
                          ? FontWeight.w600
                          : FontWeight.w400)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: theme.alternate)),
          ],
        ),
      );
}

BorderRadius _bubbleRadius(bool agent, MessageGroupPosition position) {
  const large = Radius.circular(15);
  const small = Radius.circular(4);
  return switch ((agent, position)) {
    (true, MessageGroupPosition.single) => const BorderRadius.only(
        topLeft: large, topRight: large, bottomLeft: large, bottomRight: small),
    (false, MessageGroupPosition.single) => const BorderRadius.only(
        topLeft: large, topRight: large, bottomLeft: small, bottomRight: large),
    (true, MessageGroupPosition.first) => const BorderRadius.only(
        topLeft: large, topRight: large, bottomLeft: large, bottomRight: small),
    (true, MessageGroupPosition.middle) => const BorderRadius.only(
        topLeft: large, topRight: small, bottomLeft: large, bottomRight: small),
    (true, MessageGroupPosition.last) => const BorderRadius.only(
        topLeft: large, topRight: small, bottomLeft: large, bottomRight: small),
    (false, MessageGroupPosition.first) => const BorderRadius.only(
        topLeft: large, topRight: large, bottomLeft: small, bottomRight: large),
    (false, MessageGroupPosition.middle) => const BorderRadius.only(
        topLeft: small, topRight: large, bottomLeft: small, bottomRight: large),
    (false, MessageGroupPosition.last) => const BorderRadius.only(
        topLeft: small, topRight: large, bottomLeft: small, bottomRight: large),
  };
}
