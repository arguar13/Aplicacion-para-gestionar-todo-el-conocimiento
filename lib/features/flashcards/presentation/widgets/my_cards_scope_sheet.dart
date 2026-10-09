import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Elegir qué tarjetas mirar (F31, ola 2, decisión 72): todo, un tema, una
/// etiqueta o un cuaderno. Devuelve el recorte elegido, o `null` si se cerró
/// sin elegir. Es el mismo [StudyScope] de la cola de estudio.
Future<StudyScope?> showMyCardsScopeSheet(
  BuildContext context, {
  required StudyScope current,
}) {
  return showModalBottomSheet<StudyScope>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _ScopeList(current: current, controller: controller),
    ),
  );
}

class _ScopeList extends ConsumerWidget {
  const _ScopeList({required this.current, required this.controller});

  final StudyScope current;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const [];
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const [];
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? const [];

    Widget tile(String label, StudyScope scope, {Key? key}) => ListTile(
      key: key,
      title: Text(label),
      selected: scope == current,
      trailing: scope == current ? const Icon(Icons.check) : null,
      onTap: () => Navigator.of(context).pop(scope),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );

    return ListView(
      controller: controller,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.myCardsScopeTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        tile(
          l10n.myCardsScopeAll,
          const StudyScope.all(),
          key: const Key('my-cards-scope-all'),
        ),
        if (current.kind == StudyScopeKind.item)
          // Llegar de un elemento deja ese recorte puesto; acá se ve y se
          // puede dejar, aunque no se elige uno nuevo desde la lista.
          tile(l10n.myCardsScopeThisItem, current),
        if (spaces.isNotEmpty) heading(l10n.myCardsScopeSpaces),
        for (final space in spaces)
          tile(
            space.name,
            StudyScope.space(space.id),
            key: Key('my-cards-scope-space-${space.id}'),
          ),
        if (tags.isNotEmpty) heading(l10n.myCardsScopeTags),
        for (final tag in tags)
          tile(
            tag.name,
            StudyScope.value(tag.id),
            key: Key('my-cards-scope-tag-${tag.id}'),
          ),
        if (notebooks.isNotEmpty) heading(l10n.myCardsScopeNotebooks),
        for (final notebook in notebooks)
          tile(
            notebook.name,
            StudyScope.notebook(notebook.id),
            key: Key('my-cards-scope-notebook-${notebook.id}'),
          ),
        if (spaces.isEmpty && tags.isEmpty && notebooks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.myCardsScopeNone),
          ),
      ],
    );
  }
}

/// El nombre del recorte, para el botón que lo muestra. `null` mientras se lee
/// o si no existe más.
String? myCardsScopeName(WidgetRef ref, StudyScope scope) {
  switch (scope.kind) {
    case StudyScopeKind.all:
      return null;
    case StudyScopeKind.space:
      final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const [];
      return spaces.where((s) => s.id == scope.id).firstOrNull?.name;
    case StudyScopeKind.value:
      final tags = ref.watch(allTagsProvider).valueOrNull ?? const [];
      return tags.where((t) => t.id == scope.id).firstOrNull?.name;
    case StudyScopeKind.notebook:
      final notebooks = ref.watch(notebooksProvider).valueOrNull ?? const [];
      return notebooks.where((n) => n.id == scope.id).firstOrNull?.name;
    case StudyScopeKind.item:
      return ref.watch(libraryItemProvider(scope.id!)).valueOrNull?.title;
  }
}
