import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'whatsapp_chat_style.dart';

/// "Today", "Yesterday", weekday for the last week, then a full date.
/// Use this for BOTH the inline day chips and the pinned pill so they match.
String whatsAppDayLabel(DateTime date, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(date);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat('EEEE').format(day);
  return DateFormat('d MMMM y').format(day);
}

/// Day pill pinned to the top of the thread. It shows the day of the message
/// at the top of the viewport and swaps (slide + fade) when the day changes.
/// Place it as a direct child of the Stack that holds the message list.
///
/// [topVisibleDate] must return the sentAt of the first message whose bottom
/// edge is below the top of the list viewport, or null.
class WhatsAppDayPill extends StatefulWidget {
  const WhatsAppDayPill({
    super.key,
    required this.controller,
    required this.palette,
    required this.topVisibleDate,
    this.alwaysVisible = false,
    this.idleHideDelay = const Duration(milliseconds: 1500),
  });

  final ScrollController controller;
  final WhatsAppChatPalette palette;
  final DateTime? Function() topVisibleDate;

  /// false: pill fades out shortly after scrolling stops.
  /// true: pill stays pinned whenever the list is scrolled away from the start.
  final bool alwaysVisible;
  final Duration idleHideDelay;

  @override
  State<WhatsAppDayPill> createState() => _WhatsAppDayPillState();
}

class _WhatsAppDayPillState extends State<WhatsAppDayPill> {
  Timer? _hideTimer;
  DateTime? _day;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant WhatsAppDayPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final top = widget.topVisibleDate();
    final day = top == null ? null : DateUtils.dateOnly(top);
    if (day != _day || !_visible) {
      setState(() {
        _day = day;
        _visible = day != null;
      });
    }
    _hideTimer?.cancel();
    if (!widget.alwaysVisible) {
      _hideTimer = Timer(widget.idleHideDelay, () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _visible ? 1 : 0,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 170),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, -.45), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: day == null
                  ? const SizedBox.shrink(key: ValueKey('no-day'))
                  : WhatsAppDayChip(
                      key: ValueKey(day),
                      label: whatsAppDayLabel(day),
                      palette: widget.palette,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chip itself. Use it for the inline day separators too.
class WhatsAppDayChip extends StatelessWidget {
  const WhatsAppDayChip({super.key, required this.label, required this.palette});
  final String label;
  final WhatsAppChatPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: palette.dayChip,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: palette.isDark ? Colors.white : const Color(0xFF54656F),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
