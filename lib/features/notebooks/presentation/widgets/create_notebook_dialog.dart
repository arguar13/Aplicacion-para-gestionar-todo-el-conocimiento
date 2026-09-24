import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/library/domain/entities/saved_view.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Crear un cuaderno (F16, D1): nombre y modo. En modo «por consulta» la
/// consulta sale de una vista ya guardada —el mismo dato con nombre que
/// `SavedView` (16.3), aplicado acá al chat en vez de a la Biblioteca—, así
/// que hace falta elegir una; sin ninguna guardada, ese modo no está
/// disponible todavía.
///
/// Devuelve el cuaderno creado, o `null` si se canceló.
Future<Notebook?> showCreateNotebookDialog(BuildContext context) {
  return showDialog<Notebook>(
    context: context,
    builder: (context) => const _CreateNotebookDialog(),
  );
}

class _CreateNotebookDialog extends ConsumerStatefulWidget {
  const _CreateNotebookDialog();

  @override
  ConsumerState<_CreateNotebookDialog> createState() =>
      _CreateNotebookDialogState();
}

class _CreateNotebookDialogState extends ConsumerState<_CreateNotebookDialog> {
  final _nameController = TextEditingController();
  var _mode = NotebookMode.manual;
  SavedView? _sourceView;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final views = ref.watch(savedViewsProvider).valueOrNull ?? const [];
    final name = _nameController.text.trim();
    final canCreate =
        name.isNotEmpty &&
        (_mode == NotebookMode.manual || _sourceView != null);

    return AlertDialog(
      title: Text(l10n.notebooksCreateDialogTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('notebook-name-field'),
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.notebooksNameHint),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            SegmentedButton<NotebookMode>(
              segments: [
                ButtonSegment(
                  value: NotebookMode.manual,
                  label: Text(l10n.notebooksModeManual),
                ),
                ButtonSegment(
                  value: NotebookMode.query,
                  label: Text(l10n.notebooksModeQuery),
                  enabled: views.isNotEmpty,
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selected) =>
                  setState(() => _mode = selected.first),
            ),
            if (_mode == NotebookMode.query) ...[
              const SizedBox(height: 16),
              if (views.isEmpty)
                Text(
                  l10n.notebooksModeQueryEmpty,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                DropdownButtonFormField<SavedView>(
                  key: const Key('notebook-source-view'),
                  initialValue: _sourceView,
                  hint: Text(l10n.notebooksSourceViewHint),
                  items: [
                    for (final view in views)
                      DropdownMenuItem(value: view, child: Text(view.name)),
                  ],
                  onChanged: (view) => setState(() => _sourceView = view),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('notebook-confirm-create'),
          onPressed: canCreate ? _create : null,
          child: Text(l10n.notebooksCreateAction),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final notebook = await ref
        .read(notebookRepositoryProvider)
        .create(
          name: _nameController.text.trim(),
          mode: _mode,
          query: _mode == NotebookMode.query ? _sourceView!.query : null,
        );
    if (!mounted) return;
    Navigator.of(context).pop(notebook);
  }
}
