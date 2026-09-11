import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
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
              onPressed: () => _addRelation(context, ref),
            ),
          ],
        ),
        for (final relation in relations)
          ListTile(
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
              onPressed: () => ref
                  .read(organizeRepositoryProvider)
                  .deleteRelation(relation.relationId),
            ),
            onTap: () =>
                context.push(RoutePaths.itemDetail(relation.otherItemId)),
          ),
      ],
    );
  }

  Future<void> _addRelation(BuildContext context, WidgetRef ref) async {
    final otherId = await showDialog<String>(
      context: context,
      builder: (context) => _PickItemDialog(excludeItemId: item.id),
    );
    if (otherId == null || !context.mounted) return;

    final picked = await showDialog<({RelationKind kind, String? note})>(
      context: context,
      builder: (context) => const _PickRelationDialog(),
    );
    if (picked == null || !context.mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final result = await ref
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: item.id,
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
}

/// Elige con qué otro elemento vincular.
///
/// Es su propio paso, separado de qué tipo de vínculo crear: elegir *con
/// qué* y elegir *cómo* son dos decisiones independientes, y juntarlas en un
/// solo formulario obligaría a construir la lista completa de la biblioteca
/// aunque el usuario todavía no haya decidido con qué se relaciona.
class _PickItemDialog extends ConsumerStatefulWidget {
  const _PickItemDialog({required this.excludeItemId});

  final String excludeItemId;

  @override
  ConsumerState<_PickItemDialog> createState() => _PickItemDialogState();
}

class _PickItemDialogState extends ConsumerState<_PickItemDialog> {
  final _controller = TextEditingController();

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

    final query = LibraryQuery(
      searchText: searchText.isEmpty ? null : searchText,
    );
    final items =
        (ref.watch(libraryItemsProvider(query)).valueOrNull ??
                const <KnowledgeItem>[])
            .where((i) => i.id != widget.excludeItemId)
            .toList();

    return AlertDialog(
      title: Text(l10n.pickItemTitle),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.pickItemSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildList(context, l10n, items, searchText)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    AppLocalizations l10n,
    List<KnowledgeItem> items,
    String searchText,
  ) {
    if (items.isEmpty) {
      final message = searchText.isEmpty
          ? l10n.pickItemNoOthers
          : l10n.pickItemNoMatches(searchText);

      return Center(child: Text(message, textAlign: TextAlign.center));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: Icon(item.source.kind.icon),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.of(context).pop(item.id),
        );
      },
    );
  }
}

/// Elige qué tipo de vínculo es, y opcionalmente por qué.
class _PickRelationDialog extends StatefulWidget {
  const _PickRelationDialog();

  @override
  State<_PickRelationDialog> createState() => _PickRelationDialogState();
}

class _PickRelationDialogState extends State<_PickRelationDialog> {
  RelationKind _kind = RelationKind.relatedTo;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.pickRelationKindTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in RelationKind.values)
                  ChoiceChip(
                    label: Text(kind.shortLabel(l10n)),
                    avatar: Icon(kind.icon, size: 18),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(hintText: l10n.pickRelationNoteHint),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop((
            kind: _kind,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          )),
          child: Text(l10n.detailAddRelation),
        ),
      ],
    );
  }
}
