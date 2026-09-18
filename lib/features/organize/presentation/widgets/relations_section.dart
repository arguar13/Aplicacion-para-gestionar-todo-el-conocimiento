import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_item_dialog.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_relation_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Con qué otros elementos está vinculado este, y la forma de agregar uno
/// nuevo.
///
/// Es lo que convierte una pila de recortes en una red: un elemento no vive
/// solo, y poder decir "esto contradice aquello" o "esto sigue a lo otro"
/// vale más que confiar en acordarse de la relación.
class RelationsSection extends ConsumerWidget {
  const RelationsSection({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final relations =
        ref.watch(itemRelationsProvider(item.id)).valueOrNull ??
        const <ItemRelation>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.detailRelationsTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: l10n.detailAddRelation,
              onPressed: () =>
                  addRelationFlow(context, ref, fromItemId: item.id),
            ),
          ],
        ),
        for (final relation in relations)
          RelationTile(
            relation: relation,
            onDelete: () => ref
                .read(organizeRepositoryProvider)
                .deleteRelation(relation.relationId),
          ),
      ],
    );
  }
}

/// Abre el flujo de dos pasos para vincular [fromItemId] con otro elemento
/// —elegir con qué, después qué tipo de vínculo—. Cancelar cualquiera de
/// los dos pasos no crea nada.
///
/// Aparte de [RelationsSection] para que `MapNoteLinksSection` (ver la
/// decisión sobre F6) lo reuse tal cual, sin duplicar el diálogo.
Future<void> addRelationFlow(
  BuildContext context,
  WidgetRef ref, {
  required String fromItemId,
}) async {
  final otherId = await showDialog<String>(
    context: context,
    builder: (context) => PickItemDialog(excludeItemId: fromItemId),
  );
  if (otherId == null || !context.mounted) return;

  final picked = await showDialog<({RelationKind kind, String? note})>(
    context: context,
    builder: (context) => const PickRelationDialog(),
  );
  if (picked == null || !context.mounted) return;

  final l10n = AppLocalizations.of(context)!;
  final result = await ref
      .read(organizeRepositoryProvider)
      .createRelation(
        fromItemId: fromItemId,
        toItemId: otherId,
        kind: picked.kind,
        note: picked.note,
      );

  result.match((failure) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
  }, (_) {});
}

/// Una fila con un vínculo ya existente: ícono, descripción con el sentido
/// correcto según desde dónde se mire, la nota si tiene, y un botón para
/// borrarlo. Tocarla navega al otro elemento.
///
/// Aparte de [RelationsSection] para que `MapNoteLinksSection` (ver la
/// decisión sobre F6) pinte cada fila igual, sin duplicar el `ListTile`.
class RelationTile extends StatelessWidget {
  const RelationTile({
    required this.relation,
    required this.onDelete,
    super.key,
  });

  final ItemRelation relation;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(relation.kind.icon),
      title: Text(
        relation.kind.describe(
          l10n,
          direction: relation.direction,
          otherItemTitle: relation.otherItemTitle,
        ),
      ),
      subtitle: relation.note == null ? null : Text(relation.note!),
      trailing: IconButton(
        icon: const Icon(Icons.link_off),
        tooltip: l10n.detailRemoveRelation,
        onPressed: onDelete,
      ),
      onTap: () => context.push(RoutePaths.itemDetail(relation.otherItemId)),
    );
  }
}
