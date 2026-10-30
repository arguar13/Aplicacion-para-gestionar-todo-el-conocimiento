import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/graph/presentation/widgets/ai_suggest_relations_dialog.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «✨ Sugerir vínculos con IA» entre los documentos [ids] del Mapa: el lienzo
/// con los que tiene a la vista, el Resumen con los sueltos. [links] son los
/// vínculos que ya los unen, para que la IA no los proponga otra vez.
///
/// Lee de cada documento lo que la IA necesita —la escena solo trae el
/// título—: son documentos procesados, como todo lo del Mapa (F41, paso 6). Si
/// leerlos falla, lo dice en un aviso. Nada se vincula sin que la persona lo
/// confirme.
Future<void> suggestLinksAmong(
  BuildContext context,
  WidgetRef ref, {
  required Set<String> ids,
  List<({String from, String to})> links = const [],
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final loaded = await ref
      .read(libraryRepositoryProvider)
      .list(LibraryQuery(ids: ids, scope: LibraryScope.processed));
  if (!context.mounted) return;

  final failure = loaded.getLeft().toNullable();
  if (failure != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    return;
  }
  await showAiSuggestRelationsDialog(
    context,
    ref,
    items: loaded.getRight().toNullable() ?? const [],
    links: links,
  );
}
