import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/notebooks/presentation/widgets/processed_member.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántos documentos muestra el selector de una vez: con más, se busca.
const kPickProcessedLimit = 200;

/// «Agregar» a un cuaderno a mano (F41, paso 5): elige **documentos
/// procesados**, varios a la vez, con buscador —en el título y en el texto de
/// sus partes—. Lo tildado se mantiene aunque cambie la búsqueda, y lo que ya
/// está en el cuaderno ([alreadyIn]) aparece marcado y no se puede tocar.
///
/// Devuelve los ids elegidos, o `null` si se canceló. Las fuentes de la
/// Biblioteca no aparecen: un cuaderno se llena solo con procesados.
Future<Set<String>?> showPickProcessedDialog(
  BuildContext context, {
  required Set<String> alreadyIn,
}) => showDialog<Set<String>>(
  context: context,
  builder: (context) => PickProcessedDialog(alreadyIn: alreadyIn),
);

class PickProcessedDialog extends ConsumerStatefulWidget {
  const PickProcessedDialog({this.alreadyIn = const {}, super.key});

  final Set<String> alreadyIn;

  @override
  ConsumerState<PickProcessedDialog> createState() =>
      _PickProcessedDialogState();
}

class _PickProcessedDialogState extends ConsumerState<PickProcessedDialog> {
  final _controller = TextEditingController();
  final _chosen = <String>{};

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searchText = _controller.text.trim();
    final documents = ref
        .watch(
          processedDocumentsProvider(
            ProcessedQuery(
              searchText: searchText.isEmpty ? null : searchText,
              limit: kPickProcessedLimit,
            ),
          ),
        )
        .valueOrNull;

    return AlertDialog(
      title: Text(l10n.notebookPickProcessedTitle),
      content: SizedBox(
        width: 460,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('pick-processed-search'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.notebookPickProcessedSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: switch (documents) {
                null => const Center(child: CircularProgressIndicator()),
                [] => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      searchText.isEmpty
                          ? l10n.notebookPickProcessedNone
                          : l10n.notebookPickProcessedNoMatches(searchText),
                      key: const Key('pick-processed-empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                final List<ProcessedDocumentSummary> documents =>
                  ListView.builder(
                    itemCount: documents.length,
                    itemBuilder: (context, index) =>
                        _tile(l10n, documents[index]),
                  ),
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('pick-processed-confirm'),
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set.of(_chosen)),
          child: Text(l10n.pickItemsAdd(_chosen.length)),
        ),
      ],
    );
  }

  Widget _tile(AppLocalizations l10n, ProcessedDocumentSummary document) {
    final inside = widget.alreadyIn.contains(document.id);
    return CheckboxListTile(
      key: Key('pick-processed-${document.id}'),
      value: inside || _chosen.contains(document.id),
      onChanged: inside ? null : (_) => _toggle(document.id),
      secondary: ProcessedOriginBadge(document: document),
      // El ícono y los chips no se leen sueltos: el título dice todo junto.
      title: Semantics(
        label: processedMemberSemantics(l10n, document),
        excludeSemantics: true,
        child: Text(
          document.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: inside
            ? Text(l10n.pickItemsAlreadyIn)
            : ProcessedPartChips(document: document),
      ),
    );
  }

  void _toggle(String id) => setState(() {
    if (!_chosen.remove(id)) _chosen.add(id);
  });
}
