import 'package:flutter/material.dart';

import 'whatsapp_chat_style.dart';

class WhatsAppAttachmentItem {
  const WhatsAppAttachmentItem({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
}

/// Grid that takes the keyboard's place under the composer (not a modal sheet).
/// Give it the last known keyboard height so the layout doesn't jump when
/// switching between the keyboard and this panel.
///
/// Only pass items the channel can actually send. A CRM sending through the
/// WhatsApp API usually can't offer Poll / Event / AI images.
class WhatsAppAttachmentPanel extends StatelessWidget {
  const WhatsAppAttachmentPanel({
    super.key,
    required this.palette,
    required this.items,
    this.height = 292,
  });

  final WhatsAppChatPalette palette;
  final List<WhatsAppAttachmentItem> items;
  final double height;

  Color get _background => palette.panel;
  Color get _circle => palette.panelCircle;

  @override
  Widget build(BuildContext context) => Container(
        height: height + MediaQuery.paddingOf(context).bottom,
        width: double.infinity,
        color: _background,
        padding: EdgeInsets.fromLTRB(
            14, 22, 14, MediaQuery.paddingOf(context).bottom),
        child: GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 14,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: .86,
          children: [
            for (final item in items)
              Semantics(
                button: true,
                label: item.label,
                child: InkResponse(
                  onTap: item.onTap,
                  radius: 44,
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration:
                            BoxDecoration(color: _circle, shape: BoxShape.circle),
                        child: Icon(item.icon, color: item.iconColor, size: 28),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.text, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}
