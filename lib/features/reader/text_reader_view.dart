import 'dart:async';

import 'package:aloud_core/aloud_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../app/core_providers.dart';
import '../../core/highlight.dart';
import '../../core/prefs.dart';
import '../../core/ui/widgets.dart';
import 'reader_style.dart';
import 'reading_controller.dart';

/// Scrollable text of the open section with the spoken sentence highlighted.
///
/// * the list follows the narrator (unless the user scrolls away);
/// * the spoken sentence is highlighted, and — with the device voice — the
///   word being spoken inside it;
/// * double-tapping a sentence (or single-tapping, per setting) starts
///   reading from it.
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

  /// How long after a first tap the second one still counts.
  static const _doubleTapWindow = Duration(milliseconds: 400);

  /// Sentence marked by a first tap, waiting for the confirming second tap.
  int? _armed;
  Timer? _armTimer;

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  void _onSentenceTap(int sentence, TapToRead mode) {
    final ctrl = ref.read(readingProvider.notifier);
    switch (mode) {
      case TapToRead.off:
        return;
      case TapToRead.singleTap:
        unawaited(ctrl.seekToSentence(sentence, play: true));
      case TapToRead.doubleTap:
        if (_armed == sentence) {
          _disarm();
          unawaited(ctrl.seekToSentence(sentence, play: true));
          return;
        }
        _armTimer?.cancel();
        setState(() => _armed = sentence);
        _armTimer = Timer(_doubleTapWindow, _disarm);
        if (!Prefs.seenTapHint.read(ref.read(settingsProvider))) {
          context.snack('Double-tap a sentence to start reading from it.');
          unawaited(ref.setPref(Prefs.seenTapHint, true));
        }
    }
  }

  void _disarm() {
    _armTimer?.cancel();
    if (mounted && _armed != null) setState(() => _armed = null);
  }

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
    final highlight = HighlightMode.parse(ref.pref(Prefs.highlightMode));
    final wordStyle = WordStyle.parse(ref.pref(Prefs.wordStyle));
    final tapMode = TapToRead.parse(ref.pref(Prefs.tapToRead));

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
                _Paragraph paragraph(TextStyle textStyle, {bool quote = false, double top = 0, required double bottom}) =>
                    _Paragraph(
                      block: block,
                      sentences: index.inBlock(i).toList(),
                      active: activeBlock == i ? s.cursor : null,
                      armed: _armed,
                      style: textStyle,
                      style2: style,
                      quote: quote,
                      topPad: top,
                      bottomPad: bottom,
                      highlight: highlight,
                      wordStyle: wordStyle,
                      tapMode: tapMode,
                      onTap: (si) => _onSentenceTap(si, tapMode),
                    );

                switch (block.kind) {
                  case BlockKind.image:
                    return _ImageBlock(docId: doc.id, imageRef: block.imageRef!);
                  case BlockKind.sceneBreak:
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text('•   •   •', style: style.body.copyWith(color: style.palette.dim))),
                    );
                  case BlockKind.heading:
                    return paragraph(style.heading, top: 28, bottom: 10);
                  case BlockKind.paragraph || BlockKind.quote:
                    return paragraph(
                      block.context.italic ? style.body.copyWith(fontStyle: FontStyle.italic) : style.body,
                      quote: block.kind == BlockKind.quote,
                      bottom: style.body.fontSize! * 0.7,
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
    required this.armed,
    required this.style,
    required this.style2,
    required this.highlight,
    required this.wordStyle,
    required this.tapMode,
    required this.onTap,
    required this.topPad,
    required this.bottomPad,
    this.quote = false,
  });

  final ReaderBlock block;
  final List<SentenceRef> sentences;

  /// Flat index of the sentence being spoken, if it is in this paragraph.
  final int? active;

  /// Sentence marked by a first tap, if it is in this paragraph.
  final int? armed;
  final TextStyle style;
  final ReaderStyle style2;
  final HighlightMode highlight;
  final WordStyle wordStyle;
  final TapToRead tapMode;
  final bool quote;
  final double topPad;
  final double bottomPad;
  final void Function(int sentenceIndex) onTap;

  @override
  State<_Paragraph> createState() => _ParagraphState();
}

class _ParagraphState extends State<_Paragraph> {
  /// One recognizer per sentence, kept across rebuilds: the word highlight
  /// rebuilds this paragraph several times a second and recreating a
  /// recognizer mid-gesture would swallow the tap.
  final _recognizers = <int, TapGestureRecognizer>{};

  TapGestureRecognizer _recognizerFor(int sentence) => _recognizers.putIfAbsent(
        sentence,
        () => TapGestureRecognizer()..onTap = () => widget.onTap(sentence),
      );

  void _disposeRecognizers() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(_Paragraph old) {
    super.didUpdateWidget(old);
    if (!identical(old.block, widget.block)) _disposeRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only the paragraph being read listens for word changes.
    if (widget.active == null) return _paragraph(null);
    return Consumer(builder: (context, ref, _) => _paragraph(ref.watch(wordCursorProvider)));
  }

  /// Spans for one sentence: plain, marked as the current sentence, and — when
  /// the voice reports a word — with that word marked inside it.
  List<InlineSpan> _sentenceSpans(SentenceRef s, int? word) {
    final text = widget.block.text.substring(s.start, s.end);
    final palette = widget.style2.palette;
    final recognizer = widget.tapMode == TapToRead.off ? null : _recognizerFor(s.index);
    final isActive = widget.active == s.index;
    final isArmed = widget.armed == s.index;
    final hasWord = isActive && word != null;
    final sentenceMarked = isArmed || (isActive && widget.highlight.showsSentence(hasWord: hasWord));
    final sentenceStyle = sentenceMarked ? TextStyle(backgroundColor: palette.highlight) : null;

    final spans = hasWord && widget.highlight.showsWord(hasWord: true) ? WordTokenizer.spans(text) : const <WordSpan>[];
    if (word == null || word >= spans.length) {
      return [TextSpan(text: text, recognizer: recognizer, style: sentenceStyle)];
    }
    final w = spans[word];
    return [
      TextSpan(text: text.substring(0, w.start), recognizer: recognizer, style: sentenceStyle),
      TextSpan(text: text.substring(w.start, w.end), recognizer: recognizer, style: _wordStyle(context)),
      TextSpan(text: text.substring(w.end), recognizer: recognizer, style: sentenceStyle),
    ];
  }

  TextStyle _wordStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (widget.wordStyle) {
      WordStyle.soft => TextStyle(backgroundColor: scheme.primary.withValues(alpha: 0.35)),
      WordStyle.strong => TextStyle(backgroundColor: scheme.primary, color: scheme.onPrimary),
      WordStyle.underline => TextStyle(
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary,
          decorationThickness: 2.5,
          backgroundColor: widget.highlight.showsSentence(hasWord: true) ? widget.style2.palette.highlight : null,
        ),
    };
  }

  Widget _paragraph(int? word) {
    final text = widget.block.text;
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final s in widget.sentences) {
      if (s.start > pos) spans.add(TextSpan(text: text.substring(pos, s.start)));
      spans.addAll(_sentenceSpans(s, word));
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
