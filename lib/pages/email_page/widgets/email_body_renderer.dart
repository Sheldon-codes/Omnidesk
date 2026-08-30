import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../../flutter_flow/flutter_flow_theme.dart';
import '../email_page_model.dart';

class SanitizedEmailBodyRenderer extends StatelessWidget {
  const SanitizedEmailBodyRenderer({
    super.key,
    required this.body,
    required this.theme,
    required this.showRemoteImages,
    required this.onLoadRemoteImages,
    required this.onLinkTap,
  });

  final EmailBody body;
  final FlutterFlowTheme theme;
  final bool showRemoteImages;
  final VoidCallback onLoadRemoteImages;
  final ValueChanged<String> onLinkTap;

  @override
  Widget build(BuildContext context) {
    if (body.html == null || body.html!.trim().isEmpty) {
      return SelectableText(
        body.plainText,
        textDirection: body.direction,
        style: theme.bodyMedium.override(
          fontFamily: theme.bodyMediumFamily,
          color: theme.primaryText,
          lineHeight: 1.55,
        ),
      );
    }
    try {
      final sanitized = sanitizeEmailHtml(
        body.html!,
        allowRemoteImages: showRemoteImages,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sanitized.hasBlockedRemoteImages && !showRemoteImages)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton.icon(
                onPressed: onLoadRemoteImages,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Load images'),
              ),
            ),
          Html.fromDom(
            document: sanitized.document,
            extensions: const [TableHtmlExtension()],
            style: {
              'body': Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                color: theme.primaryText,
                fontSize: FontSize(15),
                lineHeight: const LineHeight(1.55),
              ),
              'p': Style(margin: Margins.only(bottom: 12)),
              'blockquote': Style(
                margin: Margins.only(left: 0, bottom: 12),
                padding: HtmlPaddings.only(left: 10),
                border:
                    Border(left: BorderSide(color: theme.alternate, width: 2)),
                color: theme.secondaryText,
              ),
              'table': Style(margin: Margins.only(bottom: 12)),
              'th': Style(
                padding: HtmlPaddings.all(6),
                fontWeight: FontWeight.w600,
              ),
              'td': Style(padding: HtmlPaddings.all(6)),
              'pre': Style(
                padding: HtmlPaddings.all(10),
                backgroundColor: theme.secondaryBackground,
              ),
            },
            onLinkTap: (url, _, __) {
              if (url != null) onLinkTap(url);
            },
          ),
        ],
      );
    } catch (_) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unable to render this email correctly.',
            style: theme.bodyMedium.override(
              fontFamily: theme.bodyMediumFamily,
              color: theme.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(body.plainText),
        ],
      );
    }
  }
}

class SanitizedEmailHtml {
  const SanitizedEmailHtml(this.document, this.hasBlockedRemoteImages);
  final dom.Document document;
  final bool hasBlockedRemoteImages;
}

SanitizedEmailHtml sanitizeEmailHtml(
  String source, {
  required bool allowRemoteImages,
}) {
  final document = html_parser.parse(source);
  var blockedRemoteImages = false;
  const bannedTags = {
    'script',
    'style',
    'iframe',
    'frame',
    'frameset',
    'object',
    'embed',
    'form',
    'input',
    'button',
    'textarea',
    'select',
    'base',
    'meta',
    'link',
  };
  for (final element in document.querySelectorAll('*').toList()) {
    if (bannedTags.contains(element.localName)) {
      element.remove();
      continue;
    }
    final attributes = Map<String, String>.from(element.attributes);
    for (final entry in attributes.entries) {
      final name = entry.key.toLowerCase();
      final value = entry.value.trim();
      final dangerousUrl = switch (name) {
        'href' => !_isSafeLink(value),
        'src' => !_isSafeResource(
            value,
            allowRemoteImages: allowRemoteImages,
          ),
        _ => false,
      };
      if (name.startsWith('on') || name == 'style' || dangerousUrl) {
        if (name == 'src' &&
            value.startsWith(RegExp(r'https?://', caseSensitive: false))) {
          blockedRemoteImages = true;
        }
        element.attributes.remove(entry.key);
      }
    }
    if (element.localName == 'img' && !element.attributes.containsKey('src')) {
      element.remove();
    }
  }
  return SanitizedEmailHtml(document, blockedRemoteImages);
}

bool _isSafeLink(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  if (uri.scheme == 'mailto' || uri.scheme == 'tel') return true;
  return uri.scheme == 'https' || uri.scheme == 'http';
}

bool _isSafeResource(String value, {required bool allowRemoteImages}) {
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  if (value.startsWith('cid:') || value.startsWith('data:image/')) return true;
  if (uri.scheme == 'https' || uri.scheme == 'http') return allowRemoteImages;
  return false;
}
