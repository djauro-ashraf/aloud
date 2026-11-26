import 'dart:async';
import 'dart:io';

import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/core_providers.dart';
import '../../core/ui/widgets.dart';
import '../../core/util/ids.dart';
import '../../data/import/comic_importer.dart';
import '../../data/models/models.dart';

/// Full-screen page viewer for CBZ comics: swipe or tap edges to turn pages,
/// pinch to zoom, optional right-to-left (manga) direction.
class ComicReaderView extends ConsumerStatefulWidget {
  const ComicReaderView({super.key, required this.doc});

  final Doc doc;

  @override
  ConsumerState<ComicReaderView> createState() => _ComicReaderViewState();
}

class _ComicReaderViewState extends ConsumerState<ComicReaderView> {
  late final List<File> _pages;
  late final PageController _controller;
  late int _page;
  bool _rtl = false;
  bool _chrome = true;
  final _saver = Debouncer(const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    final paths = ref.read(servicesProvider).paths;
    _pages = ComicImporter.pages(paths.pagesDir(widget.doc.id));
    _page = _pages.isEmpty ? 0 : widget.doc.position.sentence.clamp(0, _pages.length - 1);
    _controller = PageController(initialPage: _page);
    unawaited(WakelockPlus.enable());
    unawaited(ref.read(servicesProvider).library.touch(widget.doc.id));
  }

  @override
  void dispose() {
    _saver.flush(_save);
    _saver.dispose();
    _controller.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  void _save() {
    final total = _pages.length;
    unawaited(ref.read(servicesProvider).library.savePosition(
          widget.doc.id,
          position: ReadingPosition(section: 0, sentence: _page),
          progress: total == 0 ? 0 : (_page + 1) / total,
          completed: total > 0 && _page >= total - 1,
        ));
  }

  void _go(int delta) {
    final target = (_page + delta).clamp(0, _pages.length - 1);
    if (target != _page) {
      unawaited(_controller.animateToPage(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut));
    }
  }

  void _onTap(TapUpDetails d, double width) {
    final x = d.localPosition.dx / width;
    if (x < 0.28) {
      _go(_rtl ? 1 : -1);
    } else if (x > 0.72) {
      _go(_rtl ? -1 : 1);
    } else {
      setState(() => _chrome = !_chrome);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.broken_image_outlined, title: 'No pages found'),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _onTap(d, c.maxWidth),
              child: PageView.builder(
                controller: _controller,
                reverse: _rtl,
                itemCount: _pages.length,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  _saver.run(_save);
                  for (final n in [i + 1, i - 1]) {
                    if (n >= 0 && n < _pages.length) unawaited(precacheImage(FileImage(_pages[n]), context));
                  }
                },
                itemBuilder: (_, i) => _ComicPage(file: _pages[i]),
              ),
            ),
          ),
          if (_chrome) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.black.withValues(alpha: 0.65),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      const BackButton(color: Colors.white),
                      Expanded(
                        child: Text(widget.doc.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                      IconButton(
                        tooltip: _rtl ? 'Right-to-left (manga)' : 'Left-to-right',
                        icon: Icon(_rtl ? Icons.format_textdirection_r_to_l : Icons.format_textdirection_l_to_r, color: Colors.white),
                        onPressed: () => setState(() => _rtl = !_rtl),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.black.withValues(alpha: 0.65),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Text('${_page + 1}', style: const TextStyle(color: Colors.white)),
                      Expanded(
                        child: Directionality(
                          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                          child: Slider(
                            value: _page.toDouble(),
                            min: 0,
                            max: (_pages.length - 1).clamp(1, 1 << 30).toDouble(),
                            onChanged: _pages.length <= 1 ? null : (v) => _controller.jumpToPage(v.round()),
                          ),
                        ),
                      ),
                      Text('${_pages.length}', style: const TextStyle(color: Colors.white)),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComicPage extends StatefulWidget {
  const _ComicPage({required this.file});

  final File file;

  @override
  State<_ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends State<_ComicPage> {
  final _tc = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(() {
      final z = _tc.value.getMaxScaleOnAxis() > 1.02;
      if (z != _zoomed) setState(() => _zoomed = z);
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _tc,
      minScale: 1,
      maxScale: 5,
      // Let the PageView receive horizontal drags until the page is zoomed.
      panEnabled: _zoomed,
      child: Center(
        child: Image.file(
          widget.file,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
        ),
      ),
    );
  }
}
