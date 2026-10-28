import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'read_only_text.dart';
import 'review_markup.dart';

class ReviewContent extends StatefulWidget {
  const ReviewContent({
    super.key,
    required this.content,
    required this.byline,
    this.copyFallback = '',
    this.reduceMotion = false,
    this.onOpenLink,
  });
  final String content, byline, copyFallback;
  final bool reduceMotion;
  final Future<void> Function(Uri)? onOpenLink;

  @override
  State<ReviewContent> createState() => _ReviewContentState();
}

class _ReviewContentState extends State<ReviewContent>
    with AutomaticKeepAliveClientMixin {
  late ReviewDocument document;
  final recognizers = <Uri, TapGestureRecognizer>{};
  bool _expanded = false;
  static const _previewLines = 8;

  @override
  bool get wantKeepAlive => _expanded;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  void _parse() {
    for (final recognizer in recognizers.values) {
      recognizer.dispose();
    }
    recognizers.clear();
    document = ReviewDocument.parse(widget.content);
    for (final uri in document.links) {
      recognizers[uri] = TapGestureRecognizer()
        ..onTap = () => unawaited(_open(uri));
    }
  }

  @override
  void didUpdateWidget(ReviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _expanded = false;
      updateKeepAlive();
      _parse();
    }
  }

  @override
  void dispose() {
    for (final recognizer in recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _copy(
    String text,
    String notice, {
    BuildContext? feedbackContext,
  }) async {
    final target = feedbackContext ?? context;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (target.mounted) {
        showNovelFeedback(target, notice, haptic: HapticCue.success);
      }
    } catch (_) {
      if (target.mounted) {
        showNovelFeedback(target, '复制未完成，请重试', haptic: HapticCue.error);
      }
    }
  }

  Future<void> _open(Uri uri, {BuildContext? feedbackContext}) async {
    // Inline links and links in the extracted list share one feedback owner.
    final target = feedbackContext ?? context;
    AppHaptics.play(target, HapticCue.action);
    try {
      if (widget.onOpenLink != null) {
        await widget.onOpenLink!(uri);
        return;
      }
      // Prefer the associated app on mobile, then fall back to the browser.
      // Android uses ACTION_VIEW + REQUIRE_NON_BROWSER on API 30+.
      if ((defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android) &&
          await launchUrl(
            uri,
            mode: LaunchMode.externalNonBrowserApplication,
          )) {
        return;
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No link handler');
      }
    } catch (_) {
      if (target.mounted) {
        showNovelFeedback(target, '暂时无法打开，可在链接列表中复制', haptic: HapticCue.error);
      }
    }
  }

  Future<void> _links() => showJellySheet<void>(
    context: context,
    reduceMotion: widget.reduceMotion,
    heightFactor: .6,
    builder: (sheet) => ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      children: [
        ArchiveSection(
          title: '评论中的链接',
          code: '${document.links.length} / LINKS',
        ),
        const SizedBox(height: 16),
        for (final (index, uri) in document.links.indexed) ...[
          if (index > 0) const SizedBox(height: 16),
          ReadOnlyText(
            uri.toString(),
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GlassTextButton(
                key: ValueKey('review-open-link-$index'),
                haptic: null,
                compact: true,
                onPressed: () => _open(uri, feedbackContext: sheet),
                child: const AppText('打开链接'),
              ),
              const SizedBox(width: 12),
              GlassTextButton(
                key: ValueKey('review-copy-link-$index'),
                haptic: null,
                compact: true,
                onPressed: () =>
                    _copy(uri.toString(), '链接已复制', feedbackContext: sheet),
                child: const AppText('复制链接'),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    final body = TextSpan(
      style: DefaultTextStyle.of(
        context,
      ).style.merge(const TextStyle(fontSize: 14, height: 1.8)),
      children: [
        for (final part in document.parts)
          TextSpan(
            text: part.text,
            recognizer: recognizers[part.link],
            style: part.link == null
                ? null
                : TextStyle(
                    color: colors.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.primary.withValues(alpha: .5),
                  ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (document.text.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: body,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: _previewLines,
              )..layout(maxWidth: constraints.maxWidth);
              final hasMore = painter.didExceedMaxLines;
              painter.dispose();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSize(
                    duration:
                        widget.reduceMotion ||
                            MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : NovelMotion.enter,
                    reverseDuration:
                        widget.reduceMotion ||
                            MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : NovelMotion.exit,
                    alignment: Alignment.topLeft,
                    curve: NovelMotion.ease,
                    child: ReadOnlyText.rich(
                      body,
                      textKey: const ValueKey('review-prose'),
                      maxLines: _expanded ? null : _previewLines,
                      overflow: _expanded
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasMore) ...[
                    const SizedBox(height: 6),
                    JellyTapSurface(
                      key: const ValueKey('review-toggle-full-text'),
                      onTap: () {
                        setState(() => _expanded = !_expanded);
                        updateKeepAlive();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppText(
                              _expanded ? '收起' : '展开全文',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 7),
                            AnimatedRotation(
                              turns: _expanded ? .5 : 0,
                              duration:
                                  widget.reduceMotion ||
                                      MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : NovelMotion.enter,
                              curve: NovelMotion.ease,
                              child: const ArchiveIcon(
                                CupertinoIcons.chevron_down,
                                size: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: AppText(
                widget.byline,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            if (document.links.isNotEmpty)
              GlassIconButton(
                key: const ValueKey('review-extract-links'),
                icon: CupertinoIcons.link,
                label: '提取链接',
                onPressed: _links,
              ),
            GlassIconButton(
              key: const ValueKey('review-copy-text'),
              haptic: null,
              icon: CupertinoIcons.doc_on_doc,
              label: '复制评论',
              onPressed: () => _copy(
                document.text.isEmpty ? widget.copyFallback : document.text,
                '评论已复制',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
