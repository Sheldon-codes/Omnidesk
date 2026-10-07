import 'package:flutter/material.dart';

import 'whatsapp_chat_style.dart';

/// Round chevron at the bottom-right of the thread, shown once the user has
/// scrolled away from the latest message. [count] is the number of customer
/// messages that arrived while the user was scrolled up.
/// Place it as a direct child of the thread Stack.
class WhatsAppJumpToLatestButton extends StatelessWidget {
  const WhatsAppJumpToLatestButton({
    super.key,
    required this.visible,
    required this.count,
    required this.palette,
    required this.onTap,
  });

  final bool visible;
  final int count;
  final WhatsAppChatPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Positioned(
        right: 12,
        bottom: 10,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedScale(
            scale: visible ? 1 : .6,
            duration: const Duration(milliseconds: 160),
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Semantics(
                button: true,
                label: count > 0
                    ? 'Jump to latest, $count new messages'
                    : 'Jump to latest message',
                child: GestureDetector(
                  onTap: onTap,
                  child: SizedBox(
                    width: 48,
                    height: 56,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: palette.panelCircle,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 3,
                                  offset: Offset(0, 1)),
                            ],
                          ),
                          child: Icon(Icons.keyboard_arrow_down_rounded,
                              color: palette.text, size: 30),
                        ),
                        if (count > 0)
                          Positioned(
                            top: 0,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              height: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: palette.accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                count > 99 ? '99+' : '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
