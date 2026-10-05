import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Elige con qué elemento vincular, buscando en toda la biblioteca.
///
/// Es su propio paso, separado de qué tipo de vínculo crear: elegir *con
/// qué* y elegir *cómo* son dos decisiones independientes, y juntarlas en un
/// solo formulario obligaría a construir la lista completa de la biblioteca
/// aunque quien la usa todavía no haya decidido con qué se relaciona.
///
/// Compartido entre `RelationsSection` —vincular desde el detalle de un
/// elemento— y el grafo del mapa —vincular dos elementos cualquiera, o elegir
/// entre los de un tema—: todos necesitan exactamente el mismo paso.
class PickItemDialog extends ConsumerStatefulWidget {
  const PickItemDialog({
    this.excludeItemId,
    this.title,
    this.scopeIds,
    super.key,
  });

  /// Si no es `null`, la lista se limita a estos elementos y a ningún otro, en
  /// vez de buscar en toda la biblioteca: para quien ya sabe entre cuáles se
  /// elige, como los elementos de un tema.
  final Set<String>? scopeIds;

  /// Un elemento que no debe aparecer en la lista — normalmente, aquel
  /// desde el que se está armando el vínculo. `null` cuando no hay ninguno
  /// que excluir todavía, como al elegir el primero de los dos elementos en
  /// el grafo.
  final String? excludeItemId;

  /// Reemplaza el título por defecto —"Elegir con qué vincular"—, para
  /// cuando el mismo diálogo se usa dos veces seguidas con un sentido
  /// distinto cada vez, como al armar un vínculo desde cero en el grafo:
  /// la primera vez es "elegí el primer elemento", la segunda es "con qué
  /// vincularlo".
  final String? title;

  @override
  ConsumerState<PickItemDialog> createState() => _PickItemDialogState();
}

class _PickItemDialogState extends ConsumerState<PickItemDialog> {
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
      ids: widget.scopeIds,
    );
    final items =
        (ref.watch(libraryItemsProvider(query)).valueOrNull ??
                const <KnowledgeItem>[])
            .where((i) => i.id != widget.excludeItemId)
            .toList();

    return AlertDialog(
      title: Text(widget.title ?? l10n.pickItemTitle),
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

/// Elige VARIOS elementos a la vez, buscando en toda la biblioteca (F30): lo
/// que necesita un cuaderno para no agregar de a uno.
///
/// Lo elegido se mantiene aunque se cambie la búsqueda: se puede buscar
/// «Roma», marcar tres, buscar «Senado» y marcar dos más. [alreadyIn] son los
/// que ya están —se ven marcados y no se pueden tocar—. Devuelve los nuevos
/// elegidos, o `null` si se canceló.
class PickItemsDialog extends ConsumerStatefulWidget {
  const PickItemsDialog({
    required this.title,
    this.alreadyIn = const {},
    super.key,
  });

  final String title;
  final Set<String> alreadyIn;

  @override
  ConsumerState<PickItemsDialog> createState() => _PickItemsDialogState();
}

class _PickItemsDialogState extends ConsumerState<PickItemsDialog> {
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
    final items =
        ref
            .watch(
              libraryItemsProvider(
                LibraryQuery(
                  searchText: searchText.isEmpty ? null : searchText,
                ),
              ),
            )
            .valueOrNull ??
        const <KnowledgeItem>[];

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 460,
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
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        searchText.isEmpty
                            ? l10n.pickItemNoOthers
                            : l10n.pickItemNoMatches(searchText),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _tile(l10n, items[index]),
                    ),
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
          key: const Key('pick-items-confirm'),
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set.of(_chosen)),
          child: Text(l10n.pickItemsAdd(_chosen.length)),
        ),
      ],
    );
  }

  Widget _tile(AppLocalizations l10n, KnowledgeItem item) {
    final inside = widget.alreadyIn.contains(item.id);
    return CheckboxListTile(
      key: Key('pick-items-${item.id}'),
      value: inside || _chosen.contains(item.id),
      onChanged: inside
          ? null
          : (checked) => setState(() {
              if (checked ?? false) {
                _chosen.add(item.id);
              } else {
                _chosen.remove(item.id);
              }
            }),
      secondary: Icon(item.source.kind.icon),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: inside ? Text(l10n.pickItemsAlreadyIn) : null,
    );
  }
}
