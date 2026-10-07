import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WhatsApp conversation colors are scoped to the WhatsApp channel. Other
/// OmniDesk conversation types continue to use the product theme.
@immutable
class WhatsAppChatPalette {
  const WhatsAppChatPalette._({
    required this.isDark,
    required this.chrome,
    required this.wallpaper,
    required this.incomingBubble,
    required this.outgoingBubble,
    required this.incomingAttachment,
    required this.outgoingAttachment,
    required this.field,
    required this.text,
    required this.muted,
    required this.accent,
    required this.readReceipt,
    required this.note,
    required this.noteText,
    required this.divider,
    required this.dayChip,
    required this.link,
    required this.panel,
    required this.panelCircle,
  });

  factory WhatsAppChatPalette.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const WhatsAppChatPalette._(
            isDark: true,
            chrome: Color(0xFF121212),
            wallpaper: Color(0xFF0A0A0A),
            incomingBubble: Color(0xFF242626),
            outgoingBubble: Color(0xFF1A4635),
            incomingAttachment: Color(0xFF1D1F1F),
            outgoingAttachment: Color(0xFF15382A),
            field: Color(0xFF2C2C2C),
            text: Color(0xFFFFFFFF),
            muted: Color(0xFF9AA5A0),
            accent: Color(0xFF00A884),
            readReceipt: Color(0xFF53BDEB),
            note: Color(0xFF3A3217),
            noteText: Color(0xFFF3E3A1),
            divider: Color(0xFF1F1F1F),
            dayChip: Color(0xFF161616),
            link: Color(0xFF20C062),
            panel: Color(0xFF0A0A0A),
            panelCircle: Color(0xFF222222),
          )
        : const WhatsAppChatPalette._(
            isDark: false,
            chrome: Color(0xFFF7F7F7),
            wallpaper: Color(0xFFEFEAE2),
            incomingBubble: Color(0xFFFFFFFF),
            outgoingBubble: Color(0xFFD9FDD3),
            incomingAttachment: Color(0xFFF1F3F4),
            outgoingAttachment: Color(0xFFC8EFC3),
            field: Color(0xFFFFFFFF),
            text: Color(0xFF111B21),
            muted: Color(0xFF667781),
            accent: Color(0xFF00A884),
            readReceipt: Color(0xFF53BDEB),
            note: Color(0xFFFFF4C2),
            noteText: Color(0xFF54410A),
            divider: Color(0xFFE5E5E5),
            dayChip: Color(0xFFFFFFFF),
            link: Color(0xFF027EB5),
            panel: Color(0xFFF7F7F7),
            panelCircle: Color(0xFFFFFFFF),
          );
  }

  final bool isDark;
  final Color chrome;
  final Color wallpaper;
  final Color incomingBubble;
  final Color outgoingBubble;
  final Color incomingAttachment;
  final Color outgoingAttachment;
  final Color field;
  final Color text;
  final Color muted;
  final Color accent;
  final Color readReceipt;
  final Color note;
  final Color noteText;
  final Color divider;
  final Color dayChip;
  final Color link;
  final Color panel;
  final Color panelCircle;
}

/// Renders the supplied transparent WhatsApp line-art over the channel's
/// theme-aware base color. SVG color is tinted at paint time, so the source
/// asset remains shared by light and dark modes.
class WhatsAppWallpaper extends StatelessWidget {
  const WhatsAppWallpaper({super.key, required this.palette});

  final WhatsAppChatPalette palette;

  @override
  Widget build(BuildContext context) {
    final patternColor = palette.isDark
        ? Colors.white.withValues(alpha: .10)
        : const Color(0xFF665C4F).withValues(alpha: .09);

    return ColoredBox(
      color: palette.wallpaper,
      child: Image.asset(
        'assets/images/whatsapp_wallpaper.png',
        fit: BoxFit.cover,
        color: patternColor,
        colorBlendMode: BlendMode.srcIn,
        errorBuilder: (context, error, stackTrace) => CustomPaint(
          painter: WhatsAppWallpaperPainter(palette),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Low-contrast repeating line art keeps the thread recognizable without
/// adding a large wallpaper image to the app bundle.
class WhatsAppWallpaperPainter extends CustomPainter {
  const WhatsAppWallpaperPainter(this.palette);

  final WhatsAppChatPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(palette.wallpaper, BlendMode.srcOver);
    final paint = Paint()
      ..color = palette.isDark
          ? Colors.white.withValues(alpha: .10)
          : const Color(0xFF665C4F).withValues(alpha: .09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const stepX = 46.0;
    const stepY = 48.0;
    for (var row = -1; row * stepY < size.height + stepY; row++) {
      for (var column = -1; column * stepX < size.width + stepX; column++) {
        final x = column * stepX + (row.isOdd ? stepX / 2 : 0);
        final y = row * stepY;
        final motif = (column * 7 + row * 11).abs() % 12;
        switch (motif) {
          case 0:
            _drawChat(canvas, paint, Offset(x + 2, y + 5));
          case 1:
            _drawSpark(canvas, paint, Offset(x + 34, y + 35));
          case 2:
            _drawSmiley(canvas, paint, Offset(x + 22, y + 22));
          case 3:
            _drawPhone(canvas, paint, Offset(x + 17, y + 1));
          case 4:
            _drawHeart(canvas, paint, Offset(x + 1, y + 29));
          case 5:
            _drawCamera(canvas, paint, Offset(x + 11, y + 28));
          case 6:
            _drawStar(canvas, paint, Offset(x + 23, y + 23), 10);
          case 7:
            _drawGift(canvas, paint, Offset(x + 4, y + 5));
          case 8:
            _drawMusicNote(canvas, paint, Offset(x + 31, y + 18));
          case 9:
            _drawFlower(canvas, paint, Offset(x + 22, y + 26));
          case 10:
            _drawDocument(canvas, paint, Offset(x + 7, y + 3));
          case 11:
            _drawHeadphones(canvas, paint, Offset(x + 9, y + 12));
        }
        // Small secondary marks break up the grid and make the wallpaper feel
        // hand-arranged without introducing a runtime image asset.
        if ((column + row).abs() % 3 == 0) {
          _drawSpark(canvas, paint, Offset(x + 39, y + 8));
        }
      }
    }
  }

  void _drawChat(Canvas canvas, Paint paint, Offset origin) {
    final rect = Rect.fromLTWH(origin.dx, origin.dy, 27, 19);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)), paint);
    final tail = Path()
      ..moveTo(origin.dx + 7, origin.dy + 19)
      ..lineTo(origin.dx + 5, origin.dy + 24)
      ..lineTo(origin.dx + 13, origin.dy + 19);
    canvas.drawPath(tail, paint);
    canvas.drawLine(Offset(origin.dx + 6, origin.dy + 7),
        Offset(origin.dx + 21, origin.dy + 7), paint);
    canvas.drawLine(Offset(origin.dx + 6, origin.dy + 12),
        Offset(origin.dx + 17, origin.dy + 12), paint);
  }

  void _drawSpark(Canvas canvas, Paint paint, Offset center) {
    canvas.drawLine(Offset(center.dx - 9, center.dy),
        Offset(center.dx + 9, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - 9),
        Offset(center.dx, center.dy + 9), paint);
    canvas.drawLine(Offset(center.dx - 6, center.dy - 6),
        Offset(center.dx + 6, center.dy + 6), paint);
    canvas.drawLine(Offset(center.dx + 6, center.dy - 6),
        Offset(center.dx - 6, center.dy + 6), paint);
  }

  void _drawPhone(Canvas canvas, Paint paint, Offset origin) {
    final path = Path()
      ..moveTo(origin.dx + 5, origin.dy + 3)
      ..quadraticBezierTo(
          origin.dx + 1, origin.dy + 5, origin.dx + 5, origin.dy + 13)
      ..quadraticBezierTo(
          origin.dx + 10, origin.dy + 21, origin.dx + 18, origin.dy + 23)
      ..quadraticBezierTo(
          origin.dx + 23, origin.dy + 24, origin.dx + 24, origin.dy + 19)
      ..lineTo(origin.dx + 18, origin.dy + 15)
      ..lineTo(origin.dx + 14, origin.dy + 18)
      ..quadraticBezierTo(
          origin.dx + 9, origin.dy + 15, origin.dx + 7, origin.dy + 10)
      ..lineTo(origin.dx + 10, origin.dy + 7)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, Paint paint, Offset origin) {
    final path = Path()
      ..moveTo(origin.dx + 11, origin.dy + 21)
      ..cubicTo(origin.dx - 8, origin.dy + 10, origin.dx + 3, origin.dy - 1,
          origin.dx + 11, origin.dy + 6)
      ..cubicTo(origin.dx + 20, origin.dy - 1, origin.dx + 30, origin.dy + 10,
          origin.dx + 11, origin.dy + 21);
    canvas.drawPath(path, paint);
  }

  void _drawCamera(Canvas canvas, Paint paint, Offset origin) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(origin.dx, origin.dy + 4, 29, 19),
          const Radius.circular(5)),
      paint,
    );
    canvas.drawCircle(Offset(origin.dx + 14, origin.dy + 13), 5, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(origin.dx + 6, origin.dy, 10, 5),
          const Radius.circular(2)),
      paint,
    );
  }

  void _drawSmiley(Canvas canvas, Paint paint, Offset center) {
    canvas.drawCircle(center, 9, paint);
    canvas.drawCircle(Offset(center.dx - 3, center.dy - 2), 0.9, paint);
    canvas.drawCircle(Offset(center.dx + 3, center.dy - 2), 0.9, paint);
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(center.dx, center.dy + 1), width: 9, height: 7),
      .15,
      2.8,
      false,
      paint,
    );
  }

  void _drawStar(Canvas canvas, Paint paint, Offset center, double radius) {
    final path = Path();
    for (var point = 0; point < 10; point++) {
      final angle = -math.pi / 2 + point * math.pi / 5;
      final pointRadius = point.isEven ? radius : radius * .43;
      final offset = Offset(center.dx + math.cos(angle) * pointRadius,
          center.dy + math.sin(angle) * pointRadius);
      if (point == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawGift(Canvas canvas, Paint paint, Offset origin) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(origin.dx + 3, origin.dy + 9, 22, 18),
          const Radius.circular(3)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(origin.dx + 1, origin.dy + 5, 26, 6),
          const Radius.circular(2)),
      paint,
    );
    canvas.drawLine(Offset(origin.dx + 14, origin.dy + 6),
        Offset(origin.dx + 14, origin.dy + 27), paint);
    canvas.drawOval(Rect.fromLTWH(origin.dx + 7, origin.dy, 7, 6), paint);
    canvas.drawOval(Rect.fromLTWH(origin.dx + 14, origin.dy, 7, 6), paint);
  }

  void _drawMusicNote(Canvas canvas, Paint paint, Offset origin) {
    canvas.drawLine(Offset(origin.dx + 13, origin.dy + 2),
        Offset(origin.dx + 13, origin.dy + 20), paint);
    canvas.drawLine(Offset(origin.dx + 13, origin.dy + 2),
        Offset(origin.dx + 23, origin.dy), paint);
    canvas.drawLine(Offset(origin.dx + 23, origin.dy),
        Offset(origin.dx + 23, origin.dy + 15), paint);
    canvas.drawOval(Rect.fromLTWH(origin.dx + 7, origin.dy + 16, 7, 5), paint);
    canvas.drawOval(Rect.fromLTWH(origin.dx + 17, origin.dy + 12, 7, 5), paint);
  }

  void _drawFlower(Canvas canvas, Paint paint, Offset center) {
    for (var petal = 0; petal < 6; petal++) {
      final angle = petal * math.pi / 3;
      canvas.drawCircle(
        Offset(
            center.dx + math.cos(angle) * 6, center.dy + math.sin(angle) * 6),
        3.5,
        paint,
      );
    }
    canvas.drawCircle(center, 2.5, paint);
  }

  void _drawDocument(Canvas canvas, Paint paint, Offset origin) {
    final rect = Rect.fromLTWH(origin.dx + 4, origin.dy + 2, 20, 27);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)), paint);
    canvas.drawLine(Offset(origin.dx + 8, origin.dy + 12),
        Offset(origin.dx + 20, origin.dy + 12), paint);
    canvas.drawLine(Offset(origin.dx + 8, origin.dy + 17),
        Offset(origin.dx + 20, origin.dy + 17), paint);
    canvas.drawLine(Offset(origin.dx + 8, origin.dy + 22),
        Offset(origin.dx + 17, origin.dy + 22), paint);
  }

  void _drawHeadphones(Canvas canvas, Paint paint, Offset origin) {
    canvas.drawArc(
      Rect.fromLTWH(origin.dx + 2, origin.dy, 26, 26),
      math.pi,
      math.pi,
      false,
      paint,
    );
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(origin.dx + 1, origin.dy + 13, 6, 11),
            const Radius.circular(3)),
        paint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(origin.dx + 23, origin.dy + 13, 6, 11),
            const Radius.circular(3)),
        paint);
  }

  @override
  bool shouldRepaint(covariant WhatsAppWallpaperPainter oldDelegate) =>
      oldDelegate.palette.isDark != palette.isDark;
}
