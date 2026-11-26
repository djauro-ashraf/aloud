import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/util/format.dart';
import '../../data/models/models.dart';
import '../listen/narrator.dart';
import '../reader/reading_controller.dart';

IconData kindIcon(DocKind k) => switch (k) {
      DocKind.text => Icons.article_outlined,
      DocKind.epub => Icons.menu_book_outlined,
      DocKind.pdf => Icons.picture_as_pdf_outlined,
      DocKind.web => Icons.language,
      DocKind.comic => Icons.auto_stories_outlined,
    };

/// Book cover, or a tinted placeholder with the kind's icon.
class DocCover extends ConsumerWidget {
  const DocCover(this.doc, {super.key, this.width = 48, this.height = 64});

  final Doc doc;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.10 + (doc.title.hashCode & 0x7) * 0.02),
          scheme.surfaceContainerHigh,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(kindIcon(doc.kind), color: scheme.onSurfaceVariant, size: width * 0.5),
    );
    if (!doc.hasCover) return placeholder;
    final file = ref.read(servicesProvider).paths.coverFile(doc.id);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        file,
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: (width * 3).round(),
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

String docSubtitle(Doc d) {
  final parts = <String>[d.kind.label];
  if (d.author != null && d.author!.isNotEmpty) parts.add(d.author!);
  if (d.kind == DocKind.comic) {
    parts.add('${d.pageCount} pages');
  } else if (d.completed) {
    parts.add('Finished');
  } else if (d.progress > 0) {
    parts.add('${ReadingProgress.percent(d.progress, started: true)}%');
  }
  if (d.openedAt != null) parts.add(Fmt.ago(DateTime.fromMillisecondsSinceEpoch(d.openedAt!)));
  return parts.join(' · ');
}

class DocTile extends ConsumerWidget {
  const DocTile({super.key, required this.doc, required this.onTap, required this.onMore});

  final Doc doc;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onMore,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            DocCover(doc),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    docSubtitle(doc),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (doc.progress > 0 && !doc.completed && doc.kind.isSpeakable) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: doc.progress, minHeight: 3),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.more_vert), onPressed: onMore, tooltip: 'More'),
          ],
        ),
      ),
    );
  }
}

class DocGridCard extends StatelessWidget {
  const DocGridCard({super.key, required this.doc, required this.onTap, required this.onMore});

  final Doc doc;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onMore,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (_, c) => DocCover(doc, width: c.maxWidth, height: c.maxHeight),
              ),
            ),
            const SizedBox(height: 6),
            Text(doc.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
            if (doc.progress > 0 && !doc.completed && doc.kind.isSpeakable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(value: doc.progress, minHeight: 3),
              ),
          ],
        ),
      ),
    );
  }
}

class ShelfTile extends StatelessWidget {
  const ShelfTile({super.key, required this.shelf, required this.itemCount, required this.onTap, required this.onMore});

  final Shelf shelf;
  final int itemCount;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.folder_outlined, color: scheme.onSecondaryContainer),
      ),
      title: Text(shelf.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(itemCount == 1 ? '1 item' : '$itemCount items'),
      trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: onMore, tooltip: 'More'),
      onTap: onTap,
      onLongPress: onMore,
    );
  }
}

/// Compact "now playing" bar shown above the content when something is open.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(readingProvider);
    final doc = s.doc;
    if (doc == null || !doc.kind.isSpeakable || s.status == NarratorStatus.idle && !s.loading) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final ctrl = ref.read(readingProvider.notifier);
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: () => context.push('/read/${doc.id}'),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
            child: Row(
              children: [
                DocCover(doc, width: 36, height: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        s.sectionTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(s.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36),
                  onPressed: ctrl.toggle,
                  tooltip: s.isPlaying ? 'Pause' : 'Play',
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: ctrl.close, tooltip: 'Close'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
