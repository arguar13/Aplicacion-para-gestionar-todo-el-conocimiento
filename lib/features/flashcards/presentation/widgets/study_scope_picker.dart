import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la hoja donde se elige qué estudiar (F31, ola 2): todo, o un tema, una
/// etiqueta, un cuaderno o un elemento. Devuelve el recorte elegido, o `null`
/// si se cierra sin elegir.
Future<StudyScope?> showStudyScopePicker(BuildContext context) {
  return showModalBottomSheet<StudyScope>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const StudyScopePicker(),
  );
}

/// El nombre de cada tipo de recorte.
String studyScopeKindLabel(AppLocalizations l10n, StudyScopeKind kind) =>
    switch (kind) {
      StudyScopeKind.all => l10n.reviewEntryScopeAll,
      StudyScopeKind.space => l10n.reviewEntryScopeSpace,
      StudyScopeKind.value => l10n.reviewEntryScopeValue,
      StudyScopeKind.notebook => l10n.reviewEntryScopeNotebook,
      StudyScopeKind.item => l10n.reviewEntryScopeItem,
    };

/// Un ícono para cada tipo de recorte.
IconData studyScopeKindIcon(StudyScopeKind kind) => switch (kind) {
  StudyScopeKind.all => Icons.local_library_outlined,
  StudyScopeKind.space => Icons.folder_outlined,
  StudyScopeKind.value => Icons.label_outline,
  StudyScopeKind.notebook => Icons.menu_book_outlined,
  StudyScopeKind.item => Icons.description_outlined,
};

/// La hoja de elegir qué estudiar. Elegir «Todo» cierra de una; los demás
/// muestran la lista de lo que hay (con búsqueda donde puede ser larga) y
/// tocar uno lo elige.
class StudyScopePicker extends ConsumerStatefulWidget {
  const StudyScopePicker({super.key});

  @override
  ConsumerState<StudyScopePicker> createState() => _StudyScopePickerState();
}

class _StudyScopePickerState extends ConsumerState<StudyScopePicker> {
  var _kind = StudyScopeKind.space;
  var _search = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.reviewEntryScopeSheetTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final kind in StudyScopeKind.values)
                    ChoiceChip(
                      key: Key('scope-kind-${kind.name}'),
                      label: Text(studyScopeKindLabel(l10n, kind)),
                      avatar: Icon(studyScopeKindIcon(kind), size: 18),
                      showCheckmark: false,
                      selected: _kind == kind && kind != StudyScopeKind.all,
                      onSelected: (_) {
                        if (kind == StudyScopeKind.all) {
                          Navigator.of(context).pop(const StudyScope.all());
                        } else {
                          setState(() {
                            _kind = kind;
                            _search = '';
                          });
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_kind == StudyScopeKind.value || _kind == StudyScopeKind.item)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    key: const Key('scope-search'),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.reviewEntryScopeSearch,
                      isDense: true,
                    ),
                    onChanged: (text) => setState(() => _search = text.trim()),
                  ),
                ),
              Flexible(child: _options(l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _options(AppLocalizations l10n) {
    final entries = switch (_kind) {
      StudyScopeKind.space =>
        ref
            .watch(allSpacesProvider)
            .whenData(
              (all) => [
                for (final s in all)
                  (id: s.id, name: s.name, detail: null as String?),
              ],
            ),
      StudyScopeKind.value =>
        ref
            .watch(vocabularyValueStatsProvider)
            .whenData(
              (all) => [
                // Una etiqueta que nadie usa no tiene nada para estudiar.
                for (final v in all)
                  if (v.usage > 0)
                    (id: v.id, name: v.label, detail: v.definitionName),
              ],
            ),
      StudyScopeKind.notebook =>
        ref
            .watch(notebooksProvider)
            .whenData(
              (all) => [
                for (final n in all)
                  (id: n.id, name: n.name, detail: null as String?),
              ],
            ),
      StudyScopeKind.item =>
        ref
            .watch(
              libraryItemsProvider(
                LibraryQuery(searchText: _search.isEmpty ? null : _search),
              ),
            )
            .whenData(
              (all) => [
                for (final i in all)
                  (id: i.id, name: i.title, detail: null as String?),
              ],
            ),
      StudyScopeKind.all =>
        const AsyncValue<List<({String id, String name, String? detail})>>.data(
          [],
        ),
    };

    final list = entries.valueOrNull;
    if (list == null) return const LinearProgressIndicator();
    final needle = _search.toLowerCase();
    final shown = _kind == StudyScopeKind.item
        ? list
        : [
            for (final e in list)
              if (needle.isEmpty || e.name.toLowerCase().contains(needle)) e,
          ];
    if (_kind != StudyScopeKind.item) {
      shown.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          l10n.reviewEntryScopeNothing,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: shown.length,
      itemBuilder: (context, index) {
        final entry = shown[index];
        return ListTile(
          key: Key('scope-option-${entry.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: entry.detail == null ? null : Text(entry.detail!),
          onTap: () => Navigator.of(context).pop(_scopeFor(_kind, entry.id)),
        );
      },
    );
  }

  static StudyScope _scopeFor(StudyScopeKind kind, String id) => switch (kind) {
    StudyScopeKind.all => const StudyScope.all(),
    StudyScopeKind.space => StudyScope.space(id),
    StudyScopeKind.value => StudyScope.value(id),
    StudyScopeKind.notebook => StudyScope.notebook(id),
    StudyScopeKind.item => StudyScope.item(id),
  };
}
