import 'dart:async';

import 'package:aloud_core/aloud_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/core_providers.dart';
import '../../core/highlight.dart';
import '../../core/prefs.dart';
import '../../core/ui/widgets.dart';
import '../../data/models/models.dart';
import 'pdf_geometry.dart';
import 'reading_controller.dart';

/// The PDF as it was printed, with the spoken sentence (and, with the device
/// voice, the spoken word) marked on the page.
///
/// * the highlight is drawn over the page from the PDF's own text positions;
/// * double-tapping text starts reading from that sentence, in any chapter;
/// * the view follows the narrator unless the reader is scrolling;
/// * a page-number handle on the right scrolls long documents quickly.
class PdfReaderView extends ConsumerStatefulWidget {
  const PdfReaderView({super.key, required this.doc, required this.controller});

  final Doc doc;
  final PdfViewerController controller;

  @override
  ConsumerState<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends ConsumerState<PdfReaderView> {
  /// After the reader touches the page, the view leaves it alone this long.
  static const _followPause = Duration(seconds: 4);

  /// How far from a fingertip's centre a word may be and still count as tapped.
  static const _fingertipDp = 40.0;

  late final String _path;
  late final PdfGeometry _geometry;
  late final PdfViewerParams _params;
  final _highlight = ValueNotifier<PdfHighlight>(PdfHighlight.none);
  late final ValueNotifier<PdfHighlightStyle> _style;

  PdfSectionMap? _sectionMap;
  SentenceGeometry? _sentence;
  int? _unlocatedPage;
  int _request = 0;
  DateTime _lastTouch = DateTime.fromMillisecondsSinceEpoch(0);
  bool _viewerReady = false;
  bool _restoredPosition = false;

  @override
  void initState() {
    super.initState();
    _path = ref.read(servicesProvider).paths.sourceFile(widget.doc.id, 'source.pdf').path;
    _geometry = PdfGeometry(_path);
    _style = ValueNotifier(PdfHighlightStyle.from(ref.read(settingsProvider)));
    _params = PdfViewerParams(
      onGeneralTap: _onGeneralTap,
      pageOverlaysBuilder: _pageOverlays,
      viewerOverlayBuilder: _viewerOverlays,
      onInteractionStart: (_) => _touched(),
      onInteractionEnd: (_) => _touched(),
      onViewerReady: (_, _) {
        _viewerReady = true;
        _restorePosition();
      },
    );

    ref
      ..listenManual(readingProvider.select((s) => (s.content, s.cursor)), (_, _) => unawaited(_locate()),
          fireImmediately: true)
      ..listenManual(wordCursorProvider, (_, _) => _publish())
      ..listenManual(settingsProvider.select((m) => Prefs.highlightMode.read(m)), (_, _) => _publish())
      ..listenManual(settingsProvider.select(PdfHighlightStyle.from), (_, style) => _style.value = style);
  }

  @override
  void dispose() {
    _highlight.dispose();
    _style.dispose();
    unawaited(_geometry.dispose());
    super.dispose();
  }

  void _touched() => _lastTouch = DateTime.now();

  // ── Locating and painting the highlight ────────────────────────────────

  /// Finds the current sentence on the pages. Each call supersedes the last,
  /// so a fast-moving narrator never paints a stale sentence.
  Future<void> _locate() async {
    final request = ++_request;
    final s = ref.read(readingProvider);
    final content = s.content;
    final index = s.index;
    // Translated text no longer matches the PDF's own text.
    if (content == null || index == null || index.isEmpty || s.translated) {
      _sentence = null;
      _unlocatedPage = null;
      _publish();
      return;
    }
    final sentence = index.sentences[s.cursor.clamp(0, index.length - 1)];
    final page = content.blocks[sentence.block].page;
    final geometry = await _geometry.sentence(content, sentence);
    if (!mounted || request != _request) return;

    _sentence = geometry;
    _unlocatedPage = geometry == null ? page : null;
    _publish();
    _restorePosition();
    _follow(geometry, page);
  }

  /// Sends what to paint to the page overlays.
  void _publish() {
    final mode = HighlightMode.parse(Prefs.highlightMode.read(ref.read(settingsProvider)));
    if (mode == HighlightMode.off) {
      _highlight.value = PdfHighlight.none;
      return;
    }
    final geometry = _sentence;
    if (geometry == null) {
      _highlight.value = PdfHighlight(markedPage: _unlocatedPage);
      return;
    }
    final word = ref.read(wordCursorProvider);
    final wordBoxes = word == null ? const <int, List<PageBox>>{} : geometry.wordBoxes(word);
    final hasWord = wordBoxes.isNotEmpty;
    _highlight.value = PdfHighlight(
      lines: mode.showsSentence(hasWord: hasWord) ? geometry.lines : const {},
      words: mode.showsWord(hasWord: hasWord) ? wordBoxes : const {},
    );
  }

  // ── Following the narrator ─────────────────────────────────────────────

  /// Brings the first line of the sentence into view while listening, unless
  /// the reader has just scrolled themselves.
  void _follow(SentenceGeometry? geometry, int? page) {
    final c = widget.controller;
    if (!c.isReady || !ref.read(readingProvider).isPlaying) return;
    if (!Prefs.autoScroll.read(ref.read(settingsProvider))) return;
    if (DateTime.now().difference(_lastTouch) < _followPause) return;

    final first = geometry?.firstLine;
    if (first != null) {
      final (pageIndex, box) = first;
      final target = c.calcRectForRectInsidePage(
        pageNumber: pageIndex + 1,
        rect: PdfRect(box.left, box.top, box.right, box.bottom),
      );
      unawaited(c.ensureVisible(target, margin: 96));
    } else if (page != null && c.pageNumber != page + 1) {
      unawaited(c.goToPage(pageNumber: page + 1));
    }
  }

  /// Opens on the page the reader left off at, once both the viewer and the
  /// chapter are ready.
  void _restorePosition() {
    if (_restoredPosition || !_viewerReady) return;
    final s = ref.read(readingProvider);
    final content = s.content;
    final index = s.index;
    if (content == null || index == null || index.isEmpty) return;
    _restoredPosition = true;
    final page = content.blocks[index.sentences[s.cursor.clamp(0, index.length - 1)].block].page;
    if (page != null && page > 0) unawaited(widget.controller.goToPage(pageNumber: page + 1, duration: Duration.zero));
  }

  // ── Reading from a tap ─────────────────────────────────────────────────

  bool _onGeneralTap(BuildContext context, PdfViewerController controller, PdfViewerGeneralTapHandlerDetails details) {
    final mode = TapToRead.parse(Prefs.tapToRead.read(ref.read(settingsProvider)));
    final wanted = switch (mode) {
      TapToRead.doubleTap => PdfViewerGeneralTapType.doubleTap,
      TapToRead.singleTap => PdfViewerGeneralTapType.tap,
      TapToRead.off => null,
    };
    if (wanted == null || details.type != wanted) return false;
    final hit = controller.getPdfPageHitTestResult(details.documentPosition, useDocumentLayoutCoordinates: true);
    if (hit == null) return false;
    _touched();
    unawaited(_readFromTap(hit));
    // A single tap is also used for links and the like; only a double tap is ours alone.
    return mode == TapToRead.doubleTap;
  }

  Future<void> _readFromTap(PdfPageHitTestResult hit) async {
    final found = await _sentenceAt(hit.page.pageNumber - 1, hit.offset.x, hit.offset.y, _reachInPoints(hit.page));
    if (!mounted) return;
    if (found == null) {
      context.snack('No readable text there — double-tap on the text itself.');
      return;
    }
    await ref.read(readingProvider.notifier).readFrom(found.section, found.sentence);
  }

  /// A fingertip's reach, in PDF points at the current zoom.
  double _reachInPoints(PdfPage page) {
    final c = widget.controller;
    final onScreen = c.layout.pageLayouts[page.pageNumber - 1].width * c.currentZoom;
    return _fingertipDp * page.width / onScreen;
  }

  /// The chapter and sentence nearest a point on [page]. The page may belong
  /// to a chapter other than the one loaded.
  Future<({int section, int sentence})?> _sentenceAt(int page, double x, double y, double reach) async {
    final s = ref.read(readingProvider);
    final content = s.content;
    final index = s.index;
    if (content != null && index != null) {
      final here = await _geometry.sentenceAt(content, index, page, x, y, maxDistance: reach);
      if (here != null) return (section: s.section, sentence: here);
    }
    final section = await _sections().sectionOfPage(page);
    if (section == null || section == s.section) return null;
    final other = await _readSection(section);
    final sentence = await _geometry.sentenceAt(other, SectionIndex.build(other), page, x, y, maxDistance: reach);
    return sentence == null ? null : (section: section, sentence: sentence);
  }

  /// Starts reading at the first sentence on the page in view.
  Future<void> _readFromCurrentPage() async {
    final page = (widget.controller.pageNumber ?? 1) - 1;
    final s = ref.read(readingProvider);
    var section = s.section;
    var content = s.content;
    var index = s.index;
    if (content == null || index == null || index.firstSentenceOnPage(content, page) == null) {
      final found = await _sections().sectionOfPage(page);
      if (found == null) {
        if (mounted) context.snack('No readable text on this page.');
        return;
      }
      section = found;
      content = await _readSection(found);
      index = SectionIndex.build(content);
    }
    final sentence = index.firstSentenceOnPage(content, page);
    if (sentence == null) {
      if (mounted) context.snack('No readable text on this page.');
      return;
    }
    await ref.read(readingProvider.notifier).readFrom(section, sentence);
  }

  PdfSectionMap _sections() {
    final count = ref.read(readingProvider).sectionCount;
    final existing = _sectionMap;
    if (existing != null && existing.count == count) return existing;
    return _sectionMap = PdfSectionMap(count: count, read: _readSection);
  }

  Future<ReaderSection> _readSection(int section) => ref.read(servicesProvider).content.readSection(widget.doc.id, section);

  // ── Viewer hooks ───────────────────────────────────────────────────────

  List<Widget> _pageOverlays(BuildContext context, Rect pageRect, PdfPage page) => [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _HighlightPainter(page: page, highlight: _highlight, style: _style)),
          ),
        ),
      ];

  List<Widget> _viewerOverlays(BuildContext context, Size size, PdfViewerHandleLinkTap handleLinkTap) => [
        PdfViewerScrollThumb(
          controller: widget.controller,
          orientation: ScrollbarOrientation.right,
          thumbSize: const Size(48, 30),
          thumbBuilder: (context, thumbSize, pageNumber, controller) => _PageHandle(page: pageNumber),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: PdfViewer.file(_path, controller: widget.controller, initialPageNumber: 1, params: _params),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: Center(
            child: FloatingActionButton.extended(
              onPressed: () => unawaited(_readFromCurrentPage()),
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Read from this page'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints the sentence and word marks over one page.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({required this.page, required this.highlight, required this.style})
      : super(repaint: Listenable.merge([highlight, style]));

  final PdfPage page;
  final ValueListenable<PdfHighlight> highlight;
  final ValueListenable<PdfHighlightStyle> style;

  @override
  void paint(Canvas canvas, Size size) {
    final h = highlight.value;
    final st = style.value;
    final index = page.pageNumber - 1;
    final color = Color(st.color);

    if (h.markedPage == index) {
      final frame = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)).deflate(st.thickness / 2);
      canvas.drawRRect(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = st.thickness
          ..color = color.withValues(alpha: 0.7),
      );
    }

    final lines = h.lines[index];
    if (lines != null) {
      final fill = Paint()..color = color.withValues(alpha: 0.22);
      for (final box in lines) {
        canvas.drawRRect(_rounded(box, size, st), fill);
      }
    }

    final words = h.words[index];
    if (words != null) {
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = st.thickness
        ..color = color;
      for (final box in words) {
        canvas.drawRRect(_rounded(box, size, st), outline);
      }
    }
  }

  RRect _rounded(PageBox box, Size size, PdfHighlightStyle st) {
    final r = PdfRect(box.left, box.top, box.right, box.bottom).toRect(page: page, scaledPageSize: size);
    return RRect.fromRectAndRadius(
      Rect.fromLTRB(r.left - st.padH, r.top - st.padV + st.offsetY, r.right + st.padH, r.bottom + st.padV + st.offsetY),
      const Radius.circular(3),
    );
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.page != page || old.highlight != highlight || old.style != style;
}

/// The draggable handle that shows the page being scrolled to.
class _PageHandle extends StatelessWidget {
  const _PageHandle({required this.page});

  final int? page;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Center(
        child: Text(
          page == null ? '' : '$page',
          style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }
}
