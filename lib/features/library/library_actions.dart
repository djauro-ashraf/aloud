import 'dart:async';

import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/ui/widgets.dart';
import '../../core/util/format.dart';
import '../../core/util/ids.dart';
import '../../data/models/models.dart';
import '../reader/reading_controller.dart';

/// The shelf currently shown in the library (null = top level).
final currentShelfProvider = NotifierProvider<CurrentShelf, String?>(CurrentShelf.new);

class CurrentShelf extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String? id) => state = id;
}

/// Opens a document in the reader, optionally starting playback.
void openDoc(BuildContext context, WidgetRef ref, Doc doc, {bool listen = false}) {
  if (doc.kind.isSpeakable) {
    unawaited(ref.read(readingProvider.notifier).open(doc.id, autoplay: listen));
  }
  context.push('/read/${doc.id}');
}

// ── Document actions ──────────────────────────────────────────────────────

Future<void> showDocActions(BuildContext context, WidgetRef ref, Doc doc) {
  final repo = ref.read(servicesProvider).library;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(doc.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([doc.kind.label, if (doc.author != null) doc.author!, Fmt.bytes(doc.sizeBytes)].join(' · ')),
          ),
          const Divider(height: 1),
          if (doc.kind.isSpeakable)
            ListTile(
              leading: const Icon(Icons.headphones_outlined),
              title: const Text('Listen'),
              onTap: () {
                Navigator.pop(ctx);
                openDoc(context, ref, doc, listen: true);
              },
            ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('Move to shelf'),
            onTap: () async {
              Navigator.pop(ctx);
              final pick = await pickShelf(context, ref, title: 'Move “${doc.title}” to…');
              if (pick != null) await repo.moveDoc(doc.id, pick.id);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(ctx);
              final name = await promptText(context, title: 'Rename', initial: doc.title);
              if (name != null) await repo.updateDoc(doc.id, (d) => d.copyWith(title: Names.title(name)));
            },
          ),
          if (doc.progress > 0 || doc.completed)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset progress'),
              onTap: () async {
                Navigator.pop(ctx);
                await repo.resetProgress(doc.id);
              },
            ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            title: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await confirm(
                context,
                title: 'Delete “${doc.title}”?',
                message: 'The book and its reading progress will be removed from this device.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (!ok) return;
              if (ref.read(readingProvider).doc?.id == doc.id) await ref.read(readingProvider.notifier).close();
              await repo.deleteDoc(doc.id);
            },
          ),
        ],
      ),
    ),
  );
}

// ── Shelf actions ─────────────────────────────────────────────────────────

Future<void> createShelf(BuildContext context, WidgetRef ref, {String? parentId}) async {
  final name = await promptText(context, title: 'New shelf', hint: 'e.g. Fantasy', confirmLabel: 'Create');
  if (name == null) return;
  await ref.read(servicesProvider).library.createShelf(name, parentId: parentId, id: newId());
}

Future<void> showShelfActions(BuildContext context, WidgetRef ref, Shelf shelf) {
  final repo = ref.read(servicesProvider).library;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.folder_outlined), title: Text(shelf.name)),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(ctx);
              final name = await promptText(context, title: 'Rename shelf', initial: shelf.name);
              if (name != null) await repo.renameShelf(shelf.id, name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('Move'),
            onTap: () async {
              Navigator.pop(ctx);
              final pick = await pickShelf(context, ref, title: 'Move “${shelf.name}” to…', exclude: shelf.id);
              if (pick == null) return;
              final ok = await repo.moveShelf(shelf.id, pick.id);
              if (!ok && context.mounted) context.snack('A shelf can’t be moved into itself.');
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            title: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            onTap: () async {
              Navigator.pop(ctx);
              await _deleteShelf(context, ref, shelf);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _deleteShelf(BuildContext context, WidgetRef ref, Shelf shelf) async {
  final repo = ref.read(servicesProvider).library;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete “${shelf.name}”?'),
      content: const Text('Choose what happens to the books and shelves inside it.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: const Text('Keep contents')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, 'all'),
          child: const Text('Delete all'),
        ),
      ],
    ),
  );
  if (choice == null) return;
  if (ref.read(currentShelfProvider) == shelf.id) ref.read(currentShelfProvider.notifier).open(shelf.parentId);
  await repo.deleteShelf(shelf.id, deleteContents: choice == 'all');
}

/// Result of [pickShelf]: `id == null` means the top level.
typedef ShelfPick = ({String? id});

/// Lets the user choose a destination shelf (or the top level).
Future<ShelfPick?> pickShelf(BuildContext context, WidgetRef ref, {required String title, String? exclude}) {
  final shelves = ref.read(shelvesProvider).value ?? const <Shelf>[];
  final tree = ShelfTree([for (final s in shelves) s.node]);
  final blocked = exclude == null ? <String>{} : {exclude, ...tree.descendantIds(exclude)};
  final expanded = {for (final s in shelves) s.id};
  final rows = tree.rows(expanded).where((r) => !blocked.contains(r.node.id)).toList();

  return showDialog<ShelfPick>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, (id: null)),
          child: const Row(children: [Icon(Icons.home_outlined), SizedBox(width: 12), Text('Library (top level)')]),
        ),
        for (final r in rows)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, (id: r.node.id)),
            child: Padding(
              padding: EdgeInsets.only(left: 16.0 * r.depth),
              child: Row(children: [
                const Icon(Icons.folder_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text(r.node.name, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
      ],
    ),
  );
}
