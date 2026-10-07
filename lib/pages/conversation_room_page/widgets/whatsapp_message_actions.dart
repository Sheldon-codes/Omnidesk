import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'whatsapp_chat_style.dart';

class WhatsAppMessageAction {
  const WhatsAppMessageAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

class WhatsAppMessageSnapshot {
  const WhatsAppMessageSnapshot(this.image, this.rect, this.pixelRatio);
  final ui.Image image;
  final Rect rect; // global position of the message row
  final double pixelRatio;
}

/// Needs the message row wrapped as `RepaintBoundary(key: messageKey, ...)`.
/// In the room widget replace `KeyedSubtree(key: ...)` with
/// `RepaintBoundary(key: ...)` so the pressed bubble can be lifted exactly.
Future<WhatsAppMessageSnapshot?> captureWhatsAppMessage(
    BuildContext context, GlobalKey key) async {
  final ratio = MediaQuery.devicePixelRatioOf(context);
  for (var attempt = 0; attempt < 3; attempt++) {
    // Long-press callbacks can run while an implicit animation or the list's
    // scroll/layout pass has invalidated this boundary. Wait for a completed
    // frame before querying geometry or asking the engine to rasterize it.
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return null;

    final object = key.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary ||
        !object.attached ||
        !object.hasSize) {
      return null;
    }
    if (object.debugNeedsPaint) continue;

    final rect = object.localToGlobal(Offset.zero) & object.size;
    try {
      final image = await object.toImage(pixelRatio: ratio);
      return WhatsAppMessageSnapshot(image, rect, ratio);
    } on FlutterError {
      return null;
    } on AssertionError {
      // A render invalidation can race the async raster request. Retry only
      // after another frame; never let a transient capture failure escape the
      // long-press gesture callback as an unhandled exception.
    } on StateError {
      return null;
    }
  }
  return null;
}

/// Pass [reactions] only if the channel supports them (live WhatsApp in your
/// app currently doesn't), otherwise leave it empty and the bar is hidden.
Future<void> showWhatsAppMessageActions(
  BuildContext context, {
  required WhatsAppChatPalette palette,
  required WhatsAppMessageSnapshot snapshot,
  required bool outgoing,
  required List<WhatsAppMessageAction> actions,
  List<String> reactions = const [],
  ValueChanged<String>? onReact,
}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close message menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 170),
    transitionBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (dialogContext, _, __) => _Overlay(
      palette: palette,
      snapshot: snapshot,
      outgoing: outgoing,
      actions: actions,
      reactions: reactions,
      onReact: onReact,
    ),
  );
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.palette,
    required this.snapshot,
    required this.outgoing,
    required this.actions,
    required this.reactions,
    required this.onReact,
  });

  final WhatsAppChatPalette palette;
  final WhatsAppMessageSnapshot snapshot;
  final bool outgoing;
  final List<WhatsAppMessageAction> actions;
  final List<String> reactions;
  final ValueChanged<String>? onReact;

  static const _barHeight = 52.0;
  static const _rowHeight = 52.0;
  static const _gap = 8.0;
  static const _menuWidth = 250.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final rect = snapshot.rect;
    final hasBar = reactions.isNotEmpty;
    final menuHeight = actions.length * _rowHeight;
    final above = hasBar ? _barHeight + _gap : 0.0;

    var top = rect.top;
    final minTop = pad.top + 8 + above;
    final maxTop =
        size.height - pad.bottom - 8 - menuHeight - _gap - rect.height;
    if (top > maxTop) top = maxTop;
    if (top < minTop) top = minTop;

    final double? left = outgoing ? null : rect.left;
    final double? right = outgoing ? size.width - rect.right : null;
    final menuLeft = outgoing ? null : rect.left;
    final menuRight = outgoing ? size.width - rect.right : null;

    void close() => Navigator.of(context).pop();

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: close,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: ColoredBox(color: Colors.black.withValues(alpha: .45)),
              ),
            ),
          ),
          if (hasBar)
            Positioned(
              top: top - above,
              left: left,
              right: right,
              child: _ReactionBar(
                reactions: reactions,
                onTap: (emoji) {
                  close();
                  onReact?.call(emoji);
                },
              ),
            ),
          Positioned(
            top: top,
            left: snapshot.rect.left,
            width: rect.width,
            height: rect.height,
            child: IgnorePointer(
              child:
                  RawImage(image: snapshot.image, scale: snapshot.pixelRatio),
            ),
          ),
          Positioned(
            top: top + rect.height + _gap,
            left: menuLeft,
            right: menuRight,
            width: _menuWidth,
            child: _ActionMenu(
              actions: actions,
              onSelected: (action) {
                close();
                action.onTap();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({required this.reactions, required this.onTap});
  final List<String> reactions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Container(
        height: _Overlay._barHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xF2242625),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in reactions)
              Semantics(
                button: true,
                label: 'React with $emoji',
                child: InkResponse(
                  onTap: () => onTap(emoji),
                  radius: 24,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.actions, required this.onSelected});
  final List<WhatsAppMessageAction> actions;
  final ValueChanged<WhatsAppMessageAction> onSelected;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: const Color(0xE62C2C2C),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: .6, thickness: .6, color: Color(0x1FFFFFFF)),
                  InkWell(
                    onTap: () => onSelected(actions[i]),
                    child: SizedBox(
                      height: _Overlay._rowHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                actions[i].label,
                                style: TextStyle(
                                  color: actions[i].destructive
                                      ? const Color(0xFFF2707F)
                                      : Colors.white,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            Icon(
                              actions[i].icon,
                              size: 22,
                              color: actions[i].destructive
                                  ? const Color(0xFFF2707F)
                                  : Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
