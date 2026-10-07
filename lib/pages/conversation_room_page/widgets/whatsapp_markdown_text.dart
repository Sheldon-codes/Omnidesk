import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Compact, theme-aware Markdown for WhatsApp message and system-event text.
/// Plain messages stay on the cheaper Text path; Markdown is parsed only when
/// common formatting syntax is present.
class WhatsAppMarkdownText extends StatelessWidget {
  const WhatsAppMarkdownText({
    super.key,
    required this.data,
    required this.style,
    this.linkColor,
  });

  final String data;
  final TextStyle style;
  final Color? linkColor;

  static final _markdownSyntax = RegExp(
    r'(^\s{0,3}(#{1,6}\s|[-*+]\s|\d+\.\s|>\s|```)|'
    r'\*\*[^*\n]+\*\*|__[^_\n]+__|~~[^~\n]+~~|'
    r'`[^`\n]+`|\*[^*\n]+\*|_[^_\n]+_|'
    r'\[[^\]]+\]\([^)]+\))',
    multiLine: true,
  );

  @override
  Widget build(BuildContext context) {
    if (!_markdownSyntax.hasMatch(data)) {
      return Text(data, style: style);
    }

    final base = style;
    final bodyStyle = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      h1: _headingStyle(base, 1.3),
      h2: _headingStyle(base, 1.2),
      h3: _headingStyle(base, 1.1),
      h4: _headingStyle(base, 1.05),
      h5: base.copyWith(fontWeight: FontWeight.w600),
      h6: base.copyWith(fontWeight: FontWeight.w600),
      a: base.copyWith(
        color: linkColor ?? base.color,
        decoration: TextDecoration.underline,
      ),
      code: base.copyWith(
        fontFamily: 'monospace',
        backgroundColor: base.color?.withValues(alpha: .10),
      ),
      blockquote: base.copyWith(color: base.color?.withValues(alpha: .88)),
      listBullet: base,
      blockSpacing: 5,
      listIndent: 20,
      codeblockPadding: const EdgeInsets.all(8),
      codeblockDecoration: BoxDecoration(
        color: base.color?.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
      blockquotePadding: const EdgeInsets.only(left: 9),
      blockquoteDecoration: BoxDecoration(
        border: Border(
            left: BorderSide(
                color: linkColor ?? base.color ?? Colors.grey, width: 2)),
      ),
    );

    return MarkdownBody(
      data: data,
      styleSheet: bodyStyle,
      softLineBreak: true,
      shrinkWrap: true,
      fitContent: true,
      // Do not fetch arbitrary remote images embedded in an agent/customer
      // message. Rich media must use the app's explicit attachment model.
      builders: {'img': _SuppressMarkdownImages()},
      onTapLink: (text, href, title) => unawaited(_openLink(href)),
    );
  }

  TextStyle _headingStyle(TextStyle base, double scale) => base.copyWith(
        fontSize: (base.fontSize ?? 14) * scale,
        fontWeight: FontWeight.w700,
      );

  Future<void> _openLink(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href.trim());
    if (uri == null ||
        !const {'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase())) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Link launch failure should not break the conversation renderer.
    }
  }
}

class _SuppressMarkdownImages extends MarkdownElementBuilder {
  _SuppressMarkdownImages();

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) =>
      const SizedBox.shrink();
}
