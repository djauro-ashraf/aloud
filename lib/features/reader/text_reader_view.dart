import 'package:aloud_core/aloud_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import 'reader_style.dart';
import 'reading_controller.dart';

/// Scrollable text of the open section with the spoken sentence highlighted.
///
/// * the list follows the narrator (unless the user scrolls away);
/// * tapping any sentence starts reading from it.
class TextReaderView extends ConsumerStatefulWidget {
  const TextReaderView({super.key, this.bottomPadding = 160});

  /// Space left under the last block so it can scroll above the player bar.
  final double bottomPadding;

  @override
  ConsumerState<TextReaderView> createState() => _TextReaderViewState();
}

class _TextReaderViewState extends ConsumerState<TextReaderView> {
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  bool _following = true;

  bool _isVisible(int block) => _positions.itemPositions.value
      .any((p) => p.index == block && p.itemLeadingEdge >= 0 && p.itemTrailingEdge <= 1);

  void _follow(int block) {
    if (!_following || !_scroll.isAttached || _isVisible(block)) return;
    _scroll.scrollTo(
      index: block,
      alignment: 0.12,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(readingProvider);
    final content = s.content;
    final index = s.index;
    final doc = s.doc;
    final style = ReaderStyle.of(ref, context);
    final autoScroll = ref.pref(Prefs.autoScroll);
    final ctrl = ref.read(readingProvider.notifier);

    ref.listen<int?>(readingProvider.select((x) => x.cursorBlock), (prev, next) {
      if (next != null && autoScroll) _follow(next);
    });
    ref.listen<bool>(readingProvider.select((x) => x.isPlaying), (prev, playing) {
      if (playing && prev != true) setState(() => _following = true);
    });

    if (content == null || index == null || doc == null) {
      return ColoredBox(color: style.palette.background, child: const Center(child: CircularProgressIndicator()));
    }
    if (content.blocks.isEmpty) {
      return ColoredBox(
        color: style.palette.background,
        child: Center(child: Text('This section is empty.', style: style.body)),
      );
    }

    final activeBlock = s.cursorBlock;
    return ColoredBox(
      color: style.palette.background,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is UserScrollNotification && n.direction != ScrollDirection.idle && _following) {
                setState(() => _following = false);
              }
              return false;
            },
            child: ScrollablePositionedList.builder(
              key: ValueKey('${doc.id}:${s.section}:${s.translated}'),
              itemScrollController: _scroll,
              itemPositionsListener: _positions,
              initialScrollIndex: (activeBlock ?? 0).clamp(0, content.blocks.length - 1),
              initialAlignment: 0.08,
              padding: EdgeInsets.symmetric(horizontal: style.margin),
              itemCount: content.blocks.length + 1,
              itemBuilder: (context, i) {
                if (i == content.blocks.length) return SizedBox(height: widget.bottomPadding);
                final block = content.blocks[i];
                switch (block.kind) {
                  case BlockKind.image:
                    return _ImageBlock(docId: doc.id, imageRef: block.imageRef!);
                  case BlockKind.sceneBreak:
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text('•   •   •', style: style.body.copyWith(color: style.palette.dim))),
                    );
                  case BlockKind.heading:
                    return _Paragraph(
                      block: block,
                      sentences: index.inBlock(i).toList(),
                      active: activeBlock == i ? s.cursor : null,
                      style: style.heading,
                      style2: style,
                      topPad: 28,
                      bottomPad: 10,
                      onTap: (si) => ctrl.seekToSentence(si, play: true),
                    );
                  case BlockKind.paragraph || BlockKind.quote:
                    return _Paragraph(
                      block: block,
                      sentences: index.inBlock(i).toList(),
                      active: activeBlock == i ? s.cursor : null,
                      style: block.context.italic ? style.body.copyWith(fontStyle: FontStyle.italic) : style.body,
                      style2: style,
                      quote: block.kind == BlockKind.quote,
                      topPad: 0,
                      bottomPad: style.body.fontSize! * 0.7,
                      onTap: (si) => ctrl.seekToSentence(si, play: true),
                    );
                }
              },
            ),
          ),
          if (!_following && s.isPlaying)
            Positioned(
              right: 16,
              bottom: widget.bottomPadding - 40,
              child: FloatingActionButton.small(
                tooltip: 'Back to the spoken sentence',
                onPressed: () {
                  setState(() => _following = true);
                  if (activeBlock != null) {
                    _scroll.scrollTo(index: activeBlock, alignment: 0.12, duration: const Duration(milliseconds: 300));
                  }
                },
                child: const Icon(Icons.my_location),
              ),
            ),
        ],
      ),
    );
  }
}

/// One paragraph with per-sentence tap targets and the active highlight.
class _Paragraph extends StatefulWidget {
  const _Paragraph({
    required this.block,
    required this.sentences,
    required this.active,
    required this.style,
    required this.style2,
    required this.onTap,
    required this.topPad,
    required this.bottomPad,
    this.quote = false,
  });

  final ReaderBlock block;
  final List<SentenceRef> sentences;

  /// Flat index of the sentence being spoken, if it is in this paragraph.
  final int? active;
  final TextStyle style;
  final ReaderStyle style2;
  final bool quote;
  final double topPad;
  final double bottomPad;
  final void Function(int sentenceIndex) onTap;

  @override
  State<_Paragraph> createState() => _ParagraphState();
}

class _ParagraphState extends State<_Paragraph> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final text = widget.block.text;
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final s in widget.sentences) {
      if (s.start > pos) spans.add(TextSpan(text: text.substring(pos, s.start)));
      final rec = TapGestureRecognizer()..onTap = () => widget.onTap(s.index);
      _recognizers.add(rec);
      spans.add(TextSpan(
        text: text.substring(s.start, s.end),
        recognizer: rec,
        style: widget.active == s.index ? TextStyle(backgroundColor: widget.style2.palette.highlight) : null,
      ));
      pos = s.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    if (spans.isEmpty) spans.add(TextSpan(text: text));

    Widget child = Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.style2.justify && !widget.quote ? TextAlign.justify : TextAlign.start,
    );
    if (widget.quote) {
      child = Container(
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: widget.style2.palette.dim, width: 3))),
        child: child,
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: widget.topPad, bottom: widget.bottomPad),
      child: child,
    );
  }
}

class _ImageBlock extends ConsumerWidget {
  const _ImageBlock({required this.docId, required this.imageRef});

  final String docId;
  final String imageRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.read(servicesProvider).content.image(docId, imageRef);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          child: Image.file(file, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ),
      ),
    );
  }
}
