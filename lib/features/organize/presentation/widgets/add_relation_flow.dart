import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_item_dialog.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_relation_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Vincula dos elementos cualquiera de la biblioteca, sin partir del detalle
/// de ninguno: elige el primero, elige el segundo, elige el tipo de vínculo y
/// lo guarda.
///
/// Son tres pasos de una sola conversación —dejarla a medias no crea nada—, y
/// si guardar falla lo dice en un aviso. Lo usa el grafo del mapa, desde donde
/// no hay un elemento "de partida".
Future<void> showAddRelationFlow(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;

  final fromId = await showDialog<String>(
    context: context,
    builder: (context) => PickItemDialog(title: l10n.graphPickFirstItemTitle),
  );
  if (fromId == null || !context.mounted) return;

  final toId = await showDialog<String>(
    context: context,
    builder: (context) => PickItemDialog(
      excludeItemId: fromId,
      title: l10n.graphPickSecondItemTitle,
    ),
  );
  if (toId == null || !context.mounted) return;

  final picked = await showDialog<({RelationKind kind, String? note})>(
    context: context,
    builder: (context) => const PickRelationDialog(),
  );
  if (picked == null || !context.mounted) return;

  final result = await ref
      .read(organizeRepositoryProvider)
      .createRelation(
        fromItemId: fromId,
        toItemId: toId,
        kind: picked.kind,
        note: picked.note,
      );

  if (!context.mounted) return;
  result.match((failure) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
  }, (_) {});
}
