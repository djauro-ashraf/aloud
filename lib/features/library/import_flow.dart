import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/platform/file_picking.dart';
import '../../core/ui/widgets.dart';
import '../../data/import/import_exception.dart';
import '../../data/import/import_service.dart';
import '../../data/models/models.dart';

/// Lets the user pick documents and imports them into [shelfId].
Future<void> pickAndImport(BuildContext context, WidgetRef ref, {String? shelfId}) async {
  final services = ref.read(servicesProvider);
  List<PickedFile> files;
  try {
    files = await FilePort.pickDocuments(services.paths.tempDir, extensions: ImportService.supportedExtensions);
  } on Exception catch (e) {
    if (context.mounted) context.snack('Could not open the file picker: $e');
    return;
  }
  if (files.isEmpty || !context.mounted) return;
  await importFiles(context, ref, files, shelfId: shelfId);
}

/// Imports [files] one after another behind a cancellable progress dialog.
Future<List<Doc>> importFiles(
  BuildContext context,
  WidgetRef ref,
  List<PickedFile> files, {
  String? shelfId,
}) async {
  final services = ref.read(servicesProvider);
  final progress = ValueNotifier<(double, String)>((0, 'Starting…'));
  var cancelled = false;

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _ProgressDialog(progress: progress, onCancel: () => cancelled = true),
    ),
  ));

  final docs = <Doc>[];
  final errors = <String>[];
  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    try {
      final doc = await services.importer.importFile(
        f.path,
        shelfId: shelfId,
        displayName: f.name,
        onProgress: (frac, status) => progress.value = ((i + frac) / files.length, '${f.name}\n$status'),
        isCancelled: () => cancelled,
      );
      docs.add(doc);
    } on ImportException catch (e) {
      errors.add('${f.name}: ${e.message}');
    } on Exception catch (e) {
      errors.add('${f.name}: $e');
    } finally {
      try {
        await File(f.path).delete();
      } on FileSystemException {
        // Temp copy already gone.
      }
    }
    if (cancelled) break;
  }

  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
    if (errors.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(docs.isEmpty ? 'Import failed' : 'Some files were skipped'),
          content: SingleChildScrollView(child: Text(errors.join('\n\n'))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } else if (docs.isNotEmpty && context.mounted) {
      context.snack(docs.length == 1 ? 'Added “${docs.first.title}”' : 'Added ${docs.length} items');
    }
  }
  progress.dispose();
  return docs;
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.progress, required this.onCancel});

  final ValueNotifier<(double, String)> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importing'),
      content: ValueListenableBuilder<(double, String)>(
        valueListenable: progress,
        builder: (_, p, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: p.$1 <= 0 ? null : p.$1),
            const SizedBox(height: 16),
            Text(p.$2, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      actions: [TextButton(onPressed: onCancel, child: const Text('Cancel'))],
    );
  }
}
