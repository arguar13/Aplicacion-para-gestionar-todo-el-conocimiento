import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/spaces_picker_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La lista de lo que no está en ningún tema (F37), para ordenarlo de a
/// varios: se marcan los que van juntos y se les eligen uno o varios temas
/// con la misma hoja de siempre.
///
/// Lo que recibe un tema sale solo de la lista —la consulta es «sin tema»—,
/// así que lo que queda es siempre lo que falta. Se llega desde la tarjeta de
/// la Biblioteca (`UnsortedItemsCard`).
class UnsortedItemsScreen extends ConsumerStatefulWidget {
  const UnsortedItemsScreen({super.key});

  @override
  ConsumerState<UnsortedItemsScreen> createState() =>
      _UnsortedItemsScreenState();
}

class _UnsortedItemsScreenState extends ConsumerState<UnsortedItemsScreen> {
  final _selected = <String>{};
  var _saving = false;

  Future<void> _chooseSpaces(List<KnowledgeItem> items) async {
    final l10n = AppLocalizations.of(context)!;
    // Solo los que siguen en la lista: uno marcado puede haber recibido un
    // tema desde otro lado mientras tanto.
    final ids = [
      for (final item in items)
        if (_selected.contains(item.id)) item.id,
    ];
    if (ids.isEmpty) return;

    final chosen = await showSpacesPickerSheet(
      context,
      selected: const {},
      requireOne: true,
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    setState(() => _saving = true);
    final result = await ref
        .read(libraryRepositoryProvider)
        .changeSpaces(
          itemIds: ids,
          add: {for (final space in chosen) space.id},
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.isRight()) _selected.removeAll(ids);
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.match(
              (failure) => failure.localizedMessage(l10n),
              (_) => l10n.unsortedDone(
                ids.length,
                chosen.map((space) => space.name).join(' · '),
              ),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(libraryItemsProvider(unsortedItemsQuery));
    final list = items.valueOrNull ?? const <KnowledgeItem>[];
    final present = {for (final item in list) item.id};
    final count = _selected.where(present.contains).length;
    final allTicked = list.isNotEmpty && count == list.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.unsortedTitle),
        actions: [
          if (list.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (allTicked) {
                  _selected.clear();
                } else {
                  _selected.addAll(present);
                }
              }),
              child: Text(
                allTicked ? l10n.unsortedSelectNone : l10n.unsortedSelectAll,
              ),
            ),
        ],
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (list) => list.isEmpty
            ? EmptyStateView(
                icon: Icons.folder_outlined,
                title: l10n.unsortedEmptyTitle,
                message: l10n.unsortedEmptyBody,
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: list.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(l10n.unsortedHint),
                    );
                  }
                  final item = list[index - 1];
                  return CheckboxListTile(
                    value: _selected.contains(item.id),
                    onChanged: (ticked) => setState(() {
                      if (ticked ?? false) {
                        _selected.add(item.id);
                      } else {
                        _selected.remove(item.id);
                      }
                    }),
                    secondary: Icon(item.source.kind.icon),
                    title: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.subtitle ?? item.source.kind.label(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
      ),
      // Un botón y no un `FloatingActionButton`: sin nada marcado tiene que
      // verse apagado, y un FAB no tiene estado deshabilitado.
      bottomNavigationBar: list.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: count == 0 || _saving
                      ? null
                      : () => _chooseSpaces(list),
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(l10n.unsortedChoose(count)),
                ),
              ),
            ),
    );
  }
}
