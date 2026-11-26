import 'package:aloud_core/aloud_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import '../../core/ui/widgets.dart';
import '../../data/import/import_exception.dart';
import '../../data/models/models.dart';
import 'import_flow.dart';
import 'library_actions.dart';
import 'library_widgets.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(docsProvider);
    final shelvesAsync = ref.watch(shelvesProvider);
    final shelfId = ref.watch(currentShelfProvider);
    final grid = ref.pref(Prefs.libraryGrid);
    final sortName = ref.pref(Prefs.librarySort);
    final sort = LibrarySort.values.asNameMap()[sortName] ?? LibrarySort.recent;
    final query = _search.text.trim().toLowerCase();

    final docs = docsAsync.value ?? const <Doc>[];
    final shelves = shelvesAsync.value ?? const <Shelf>[];
    final tree = ShelfTree([for (final s in shelves) s.node]);

    final visibleDocs = [
      for (final d in docs)
        if (query.isNotEmpty
            ? (d.title.toLowerCase().contains(query) || (d.author?.toLowerCase().contains(query) ?? false))
            : d.shelfId == shelfId)
          d,
    ]..sort((a, b) => LibrarySorter.compare(sort, a.sortKey, b.sortKey));

    final visibleShelves = query.isNotEmpty
        ? [for (final s in shelves) if (s.name.toLowerCase().contains(query)) s]
        : [for (final n in tree.childrenOf(shelfId)) shelves.firstWhere((s) => s.id == n.id)];

    final path = shelfId == null ? const <ShelfNode>[] : tree.pathTo(shelfId);
    final loading = docsAsync.isLoading && docs.isEmpty;
    final continueDoc = (shelfId == null && query.isEmpty) ? _continueCandidate(docs) : null;

    return PopScope(
      canPop: shelfId == null && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_searching) {
          setState(() {
            _searching = false;
            _search.clear();
          });
        } else {
          ref.read(currentShelfProvider.notifier).open(tree.node(shelfId!)?.parentId);
        }
      },
      child: Scaffold(
        appBar: _appBar(context, path, sort, grid),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : (docs.isEmpty && shelves.isEmpty)
                ? _emptyLibrary(context)
                : CustomScrollView(
                    slivers: [
                      if (continueDoc != null) SliverToBoxAdapter(child: _ContinueCard(doc: continueDoc)),
                      if (path.isNotEmpty) SliverToBoxAdapter(child: _Breadcrumb(path: path)),
                      SliverList.builder(
                        itemCount: visibleShelves.length,
                        itemBuilder: (_, i) {
                          final s = visibleShelves[i];
                          final count = docs.where((d) => d.shelfId == s.id).length + tree.childrenOf(s.id).length;
                          return ShelfTile(
                            shelf: s,
                            itemCount: count,
                            onTap: () {
                              setState(() {
                                _searching = false;
                                _search.clear();
                              });
                              ref.read(currentShelfProvider.notifier).open(s.id);
                            },
                            onMore: () => showShelfActions(context, ref, s),
                          );
                        },
                      ),
                      if (visibleDocs.isEmpty && visibleShelves.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(icon: Icons.search_off, title: 'Nothing here yet'),
                        )
                      else if (grid)
                        SliverPadding(
                          padding: const EdgeInsets.all(10),
                          sliver: SliverGrid.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 170,
                              childAspectRatio: 0.6,
                            ),
                            itemCount: visibleDocs.length,
                            itemBuilder: (_, i) => DocGridCard(
                              doc: visibleDocs[i],
                              onTap: () => openDoc(context, ref, visibleDocs[i]),
                              onMore: () => showDocActions(context, ref, visibleDocs[i]),
                            ),
                          ),
                        )
                      else
                        SliverList.builder(
                          itemCount: visibleDocs.length,
                          itemBuilder: (_, i) => DocTile(
                            doc: visibleDocs[i],
                            onTap: () => openDoc(context, ref, visibleDocs[i]),
                            onMore: () => showDocActions(context, ref, visibleDocs[i]),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 96)),
                    ],
                  ),
        bottomNavigationBar: const MiniPlayer(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddSheet(context, shelfId),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
      ),
    );
  }

  /// The unfinished item opened most recently.
  Doc? _continueCandidate(List<Doc> docs) {
    final started = [
      for (final d in docs)
        if (d.kind.isSpeakable && d.openedAt != null && !d.completed && d.progress > 0) d,
    ]..sort((a, b) => b.openedAt!.compareTo(a.openedAt!));
    return started.firstOrNull;
  }

  PreferredSizeWidget _appBar(BuildContext context, List<ShelfNode> path, LibrarySort sort, bool grid) {
    if (_searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            _searching = false;
            _search.clear();
          }),
        ),
        title: TextField(
          controller: _search,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search library', border: InputBorder.none),
          onChanged: (_) => setState(() {}),
        ),
      );
    }
    return AppBar(
      title: Text(path.isEmpty ? 'Aloud' : path.last.name),
      actions: [
        IconButton(icon: const Icon(Icons.search), tooltip: 'Search', onPressed: () => setState(() => _searching = true)),
        PopupMenuButton<LibrarySort>(
          icon: const Icon(Icons.sort),
          tooltip: 'Sort',
          initialValue: sort,
          onSelected: (s) => ref.read(settingsProvider.notifier).set(Prefs.librarySort, s.name),
          itemBuilder: (_) => [for (final s in LibrarySort.values) PopupMenuItem(value: s, child: Text(s.label))],
        ),
        IconButton(
          icon: Icon(grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
          tooltip: grid ? 'List view' : 'Grid view',
          onPressed: () => ref.read(settingsProvider.notifier).set(Prefs.libraryGrid, !grid),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'rules':
                context.push('/rules');
              case 'voices':
                context.push('/voices');
              case 'settings':
                context.push('/settings');
              case 'lock':
                ref.read(lockCallbackProvider)();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'voices', child: Text('Voices')),
            PopupMenuItem(value: 'rules', child: Text('Listening rules')),
            PopupMenuItem(value: 'settings', child: Text('Settings')),
            PopupMenuItem(value: 'lock', child: Text('Lock now')),
          ],
        ),
      ],
    );
  }

  Widget _emptyLibrary(BuildContext context) => EmptyState(
        icon: Icons.headphones_outlined,
        title: 'Your library is empty',
        message: 'Add a book, PDF, article or comic — or paste a link — and listen to it anywhere.',
        action: FilledButton.icon(
          onPressed: () => _showAddSheet(context, ref.read(currentShelfProvider)),
          icon: const Icon(Icons.add),
          label: const Text('Add something'),
        ),
      );

  // ── Add sheet ──────────────────────────────────────────────────────────

  void _showAddSheet(BuildContext context, String? shelfId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Import files'),
              subtitle: const Text('EPUB, PDF, TXT, CBZ, HTML'),
              onTap: () {
                Navigator.pop(ctx);
                pickAndImport(context, ref, shelfId: shelfId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Web page or novel'),
              subtitle: const Text('Paste a link; add chapters in one go'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/web${shelfId == null ? '' : '?shelf=$shelfId'}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Paste text'),
              onTap: () {
                Navigator.pop(ctx);
                _pasteText(context, shelfId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New shelf'),
              onTap: () {
                Navigator.pop(ctx);
                createShelf(context, ref, parentId: shelfId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pasteText(BuildContext context, String? shelfId) async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!context.mounted) return;
    final title = TextEditingController(text: clip.trim().isEmpty ? '' : _guessTitle(clip));
    final body = TextEditingController(text: clip);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste text'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Text', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final t = title.text;
    final b = body.text;
    title.dispose();
    body.dispose();
    if (ok != true || !context.mounted) return;
    try {
      final doc = await ref.read(servicesProvider).importer.importText(t.isEmpty ? 'Pasted text' : t, b, shelfId: shelfId);
      if (context.mounted) openDoc(context, ref, doc, listen: false);
    } on ImportException catch (e) {
      if (context.mounted) context.snack(e.message);
    }
  }

  String _guessTitle(String text) {
    final first = text.trim().split('\n').first.trim();
    return first.length > 60 ? '${first.substring(0, 60)}…' : first;
  }
}

class _Breadcrumb extends ConsumerWidget {
  const _Breadcrumb({required this.path});

  final List<ShelfNode> path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          TextButton(onPressed: () => ref.read(currentShelfProvider.notifier).open(null), child: const Text('Library')),
          for (final n in path) ...[
            const Icon(Icons.chevron_right, size: 18),
            TextButton(onPressed: () => ref.read(currentShelfProvider.notifier).open(n.id), child: Text(n.name)),
          ],
        ],
      ),
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.doc});

  final Doc doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        color: scheme.primaryContainer,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openDoc(context, ref, doc, listen: true),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                DocCover(doc, width: 52, height: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Continue listening', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
                      const SizedBox(height: 4),
                      Text(doc.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: doc.progress, minHeight: 4),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.play_circle_fill, size: 44, color: scheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
