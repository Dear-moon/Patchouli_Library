import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../app_interactions.dart';
import '../app_language.dart';

/// Release text shares typography and parsing across prompts, About and pages.
/// It stays inside the caller's scroll view; links require an explicit tap.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes(
    this.text, {
    super.key,
    this.style,
    this.baseUri,
    this.onOpenLink,
  });

  final String text;
  final TextStyle? style;
  final Uri? baseUri;
  final Future<void> Function(Uri)? onOpenLink;

  Future<void> _open(BuildContext context, String? href) async {
    final uri = releaseLinkUri(href, baseUri: baseUri);
    if (uri == null) {
      showNovelFeedback(context, '此链接无法打开');
      return;
    }
    try {
      if (onOpenLink != null) {
        await onOpenLink!(uri);
      } else if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Browser unavailable');
      }
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '暂时无法打开，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final body = theme.textTheme.bodyMedium!
        .copyWith(fontSize: 14, height: 1.7, color: colors.onSurface)
        .merge(style);
    TextStyle heading(double size) => body.copyWith(
      fontSize: size,
      height: 1.45,
      fontWeight: FontWeight.w600,
    );
    final localizer = _ReleaseTextLocalizer(context);
    return MarkdownBody(
      key: ValueKey(Localizations.maybeLocaleOf(context)),
      data: text.trim(),
      fitContent: false,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      // Convert prose on parsed nodes, never URLs, Markdown syntax or code.
      // Padding hooks leave the package's text/link/table builders intact.
      paddingBuilders: {
        for (final tag in [
          'p',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'ul',
          'ol',
          'li',
          'blockquote',
          'table',
        ])
          tag: localizer,
      },
      styleSheet: MarkdownStyleSheet(
        p: body,
        h1: heading(body.fontSize! + 6),
        h2: heading(body.fontSize! + 4),
        h3: heading(body.fontSize! + 2),
        h4: heading(body.fontSize!),
        h5: heading(body.fontSize!),
        h6: heading(body.fontSize!),
        strong: const TextStyle(fontWeight: FontWeight.w700),
        a: TextStyle(
          color: colors.primary,
          decoration: TextDecoration.underline,
          decorationColor: colors.primary.withValues(alpha: .45),
        ),
        blockSpacing: 12,
        listIndent: 20,
        listBullet: body,
        listBulletPadding: const EdgeInsets.only(right: 6),
        blockquote: body,
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        blockquoteDecoration: BoxDecoration(
          color: colors.onSurface.withValues(alpha: .035),
          border: Border(
            left: BorderSide(
              color: colors.primary.withValues(alpha: .45),
              width: 2,
            ),
          ),
        ),
        code: body.copyWith(
          fontFamily: 'monospace',
          fontSize: body.fontSize! - 1,
          backgroundColor: colors.onSurface.withValues(alpha: .05),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: colors.onSurface.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(10),
        ),
        tableHead: body.copyWith(fontWeight: FontWeight.w600),
        tableBody: body,
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        tableBorder: TableBorder.all(
          color: colors.onSurface.withValues(alpha: .12),
          width: .5,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.onSurface.withValues(alpha: .12)),
          ),
        ),
        textScaler: MediaQuery.textScalerOf(context),
      ),
      onTapLink: (_, href, _) => unawaited(_open(context, href)),
      // Keep update checks lightweight: remote artwork opens only on request.
      imageBuilder: (uri, title, alt) => TextButton.icon(
        onPressed: releaseLinkUri(uri.toString(), baseUri: baseUri) == null
            ? null
            : () => unawaited(_open(context, uri.toString())),
        icon: const Icon(Icons.image_outlined, size: 18),
        label: Text(
          appText(context, '查看图片${alt?.isNotEmpty == true ? '：$alt' : ''}'),
        ),
      ),
    );
  }
}

/// Release content may be remote. Never dispatch local files or app intents.
Uri? releaseLinkUri(String? href, {Uri? baseUri}) {
  if (href == null || href.trim().isEmpty) return null;
  final parsed = Uri.tryParse(href.trim());
  if (parsed == null) return null;
  final uri = parsed.hasScheme ? parsed : baseUri?.resolveUri(parsed);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

class _ReleaseTextLocalizer extends MarkdownPaddingBuilder {
  _ReleaseTextLocalizer(this.context);
  final BuildContext context;
  final _visited = Set<md.Element>.identity();
  static const _alerts = {
    '[!NOTE]': '说明',
    '[!TIP]': '提示',
    '[!IMPORTANT]': '重要说明',
    '[!WARNING]': '警告',
    '[!CAUTION]': '注意',
  };

  @override
  void visitElementBefore(md.Element element) => _convert(element);

  void _convert(md.Element element) {
    if (!_visited.add(element) ||
        element.tag == 'code' ||
        element.tag == 'pre') {
      return;
    }
    final children = element.children;
    if (children == null) return;
    if (element.tag == 'blockquote' && children.isNotEmpty) {
      final first = children.first;
      if (first is md.Element && first.tag == 'p') {
        final nodes = first.children;
        if (nodes != null && nodes.isNotEmpty && nodes.first is md.Text) {
          final content = (nodes.first as md.Text).text;
          for (final alert in _alerts.entries) {
            if (content == alert.key || content.startsWith('${alert.key}\n')) {
              nodes.removeAt(0);
              nodes.insertAll(0, [
                md.Element('strong', [md.Text(alert.value)]),
                md.Text(content.substring(alert.key.length)),
              ]);
              break;
            }
          }
        }
      }
    }
    final rawLink =
        element.tag == 'a' && element.textContent == element.attributes['href'];
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child is md.Text && !rawLink) {
        children[i] = md.Text(appText(context, child.text));
      } else if (child is md.Element) {
        _convert(child);
      }
    }
  }
}
