import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_item_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántos candidatos como mucho se le mandan al modelo por pedido.
///
/// Un modelo de un par de miles de millones de parámetros corriendo en el
/// dispositivo no tiene el contexto de uno de servidor: mandarle la
/// biblioteca entera de una vez sería lento y, peor, diluiría su atención
/// justo en los candidatos que sí importan. Treinta títulos con un fragmento
/// cada uno es suficiente para encontrar relaciones reales sin que el
/// pedido tarde minutos.
const _maxCandidates = 30;

/// Guía todo el flujo de "sugerir vínculos con IA" desde el grafo: primero
/// confirma que el modelo esté descargado, después pide con qué elemento
/// empezar a buscar, y por último muestra las sugerencias para revisar y
/// confirmar.
///
/// Separado en un solo punto de entrada, en vez de que el grafo arme cada
/// paso, porque los tres pasos son una sola conversación con quien usa la
/// app: mostrar solo el paso 3 sin los otros dos no tendría sentido.
///
/// La búsqueda se acota a [items]: el elemento de partida se elige entre ellos
/// y los candidatos salen de ellos, sin los que ya están vinculados con él
/// según [links].
Future<void> showAiSuggestRelationsDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<KnowledgeItem> items,
  required List<({String from, String to})> links,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final ready = await ref.read(chatModelManagerProvider).isReady();
  if (!context.mounted) return;

  if (!ready) {
    final goDownload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.graphAiModelRequiredTitle),
        content: Text(l10n.graphAiModelRequiredMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.chatModelDownloadAction),
          ),
        ],
      ),
    );
    if ((goDownload ?? false) && context.mounted) {
      await context.push(RoutePaths.chatModel);
    }
    return;
  }

  final itemsById = {for (final item in items) item.id: item};
  final seedId = await showDialog<String>(
    context: context,
    builder: (context) => PickItemDialog(scopeIds: itemsById.keys.toSet()),
  );
  if (seedId == null || !context.mounted) return;

  final seed = itemsById[seedId];
  if (seed == null) return;

  final alreadyLinked = <String>{
    for (final link in links)
      if (link.from == seedId) link.to,
    for (final link in links)
      if (link.to == seedId) link.from,
  };

  final candidates = [
    for (final item in items)
      if (item.id != seedId && !alreadyLinked.contains(item.id))
        RelationCandidate(
          itemId: item.id,
          title: item.title,
          excerpt: _excerptOf(item),
        ),
  ].take(_maxCandidates).toList();

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _AiSuggestionsDialog(
      seed: seed,
      candidates: candidates,
      itemsById: itemsById,
    ),
  );
}

String _excerptOf(KnowledgeItem item) {
  final text = item.searchableText.trim();
  if (text.isEmpty) return item.subtitle ?? '';
  return text.length > 280 ? '${text.substring(0, 280)}…' : text;
}

class _AiSuggestionsDialog extends ConsumerStatefulWidget {
  const _AiSuggestionsDialog({
    required this.seed,
    required this.candidates,
    required this.itemsById,
  });

  final KnowledgeItem seed;
  final List<RelationCandidate> candidates;
  final Map<String, KnowledgeItem> itemsById;

  @override
  ConsumerState<_AiSuggestionsDialog> createState() =>
      _AiSuggestionsDialogState();
}

class _AiSuggestionsDialogState extends ConsumerState<_AiSuggestionsDialog> {
  bool _loading = true;
  bool _failed = false;
  List<RelationSuggestion> _suggestions = const [];
  final _selected = <String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final suggestions = await ref
          .read(relationSuggestionServiceProvider)
          .suggestRelations(
            seedTitle: widget.seed.title,
            seedExcerpt: _excerptOf(widget.seed),
            candidates: widget.candidates,
          );
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        _selected
          ..clear()
          ..addAll(suggestions.map((s) => s.itemId));
        _loading = false;
      });
      // `RelationSuggestionService` no documenta qué puede lanzar
      // `flutter_gemma` por debajo, y todo lo que salga de ahí es igual de
      // "no se pudo".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    var created = 0;

    for (final suggestion in _suggestions) {
      if (!_selected.contains(suggestion.itemId)) continue;

      final result = await ref
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: widget.seed.id,
            toItemId: suggestion.itemId,
            kind: suggestion.kind,
            note: suggestion.reason,
          );
      result.match((_) {}, (_) => created++);
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.graphRelationsAdded(created))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.graphAiDialogTitle),
      content: SizedBox(width: 420, height: 420, child: _body(l10n, theme)),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        if (!_loading && !_failed && _suggestions.isNotEmpty)
          FilledButton(
            onPressed: _saving || _selected.isEmpty ? null : _confirm,
            child: Text(l10n.graphAiDialogConfirm(_selected.length)),
          ),
      ],
    );
  }

  Widget _body(AppLocalizations l10n, ThemeData theme) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.graphAiDialogLoading, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (_failed) {
      return Center(
        child: Text(l10n.graphAiDialogError, textAlign: TextAlign.center),
      );
    }

    if (_suggestions.isEmpty) {
      return Center(
        child: Text(l10n.graphAiDialogEmpty, textAlign: TextAlign.center),
      );
    }

    return ListView.builder(
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        final target = widget.itemsById[suggestion.itemId];
        if (target == null) return const SizedBox.shrink();

        return CheckboxListTile(
          value: _selected.contains(suggestion.itemId),
          onChanged: _saving
              ? null
              : (checked) => setState(() {
                  if (checked ?? false) {
                    _selected.add(suggestion.itemId);
                  } else {
                    _selected.remove(suggestion.itemId);
                  }
                }),
          secondary: Icon(
            suggestion.kind.icon,
            color: suggestion.kind.color(theme.colorScheme),
          ),
          title: Text(
            target.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            suggestion.reason,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
