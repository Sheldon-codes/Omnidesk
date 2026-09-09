import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Customer/agent avatar that renders the profile photo when available and
/// falls back to initials otherwise (including while loading or on error).
///
/// Backend supplies `avatar_url` (WhatsApp profile photo) on ticket customers
/// and timeline rows; it is often null (see logs: only some customers have
/// one), so every call site must handle the fallback — this widget owns that.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.initials,
    this.radius = 18,
    this.backgroundColor,
    this.foregroundColor,
    this.fontSize,
  });

  final String? imageUrl;
  final String initials;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? fontSize;

  bool get _hasUrl => imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg =
        backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final fg = foregroundColor ?? theme.colorScheme.onSurfaceVariant;
    final label = initials.trim().isEmpty ? '?' : initials.trim();
    if (!_hasUrl) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(label,
            style: TextStyle(
                color: fg,
                fontSize: fontSize ?? radius * 0.72,
                fontWeight: FontWeight.w600)),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl!.trim(),
      imageBuilder: (_, provider) =>
          CircleAvatar(radius: radius, backgroundImage: provider),
      placeholder: (_, __) => CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(label,
            style: TextStyle(
                color: fg,
                fontSize: fontSize ?? radius * 0.72,
                fontWeight: FontWeight.w600)),
      ),
      errorWidget: (_, __, ___) => CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(label,
            style: TextStyle(
                color: fg,
                fontSize: fontSize ?? radius * 0.72,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}
