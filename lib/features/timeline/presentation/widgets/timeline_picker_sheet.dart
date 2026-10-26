import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una fila de la hoja de elección: lo que se ve y lo que se devuelve al
/// elegirla.
class _PickerEntry {
  const _PickerEntry({required this.scope, required this.icon, this.subtitle});

  final TimelineScope scope;
  final IconData icon;
  final String? subtitle;

  String get title => scope.label;
}

/// Abre la hoja para recortar la línea de tiempo a un tema (F40): todos los
/// temas de la bóveda, con un buscador. Devuelve el recorte elegido, o `null`
/// si se cerró sin elegir.
Future<TimelineScope?> showTimelineTopicPicker(BuildContext context) {
  return showModalBottomSheet<TimelineScope>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _PickerSheet(kind: TimelineScopeKind.topic),
  );
}

/// Lo mismo para un documento: los elementos que tienen alguna fecha.
Future<TimelineScope?> showTimelineDocumentPicker(BuildContext context) {
  return showModalBottomSheet<TimelineScope>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _PickerSheet(kind: TimelineScopeKind.document),
  );
}

/// La hoja de elección de un tema o de un documento: un buscador y la lista
/// filtrada por lo que se escribe, sin distinguir mayúsculas ni acentos, igual
/// que el vocabulario.
///
/// Las filas llegan de un proveedor y no de quien abre la hoja, así que la
/// lista sigue viva mientras está abierta: un documento que se fecha en otra
/// parte aparece sin cerrarla.
class _PickerSheet extends ConsumerStatefulWidget {
  const _PickerSheet({required this.kind});

  final TimelineScopeKind kind;

  @override
  ConsumerState<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends ConsumerState<_PickerSheet> {
  final _searchController = TextEditingController();

  bool get _topics => widget.kind == TimelineScopeKind.topic;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Las filas del proveedor que corresponde, o `null` mientras carga.
  List<_PickerEntry>? _entries(AppLocalizations l10n) {
    if (_topics) {
      final spaces = ref.watch(allSpacesProvider).valueOrNull;
      if (spaces == null) return null;
      return [
        for (final space in spaces)
          _PickerEntry(
            scope: TimelineScope.topic(spaceId: space.id, label: space.name),
            icon: Icons.folder_outlined,
          ),
      ];
    }
    final documents = ref.watch(timelineDocumentsProvider).valueOrNull;
    if (documents == null) return null;
    return [
      for (final document in documents)
        _PickerEntry(
          scope: TimelineScope.document(
            itemId: document.itemId,
            label: document.title,
          ),
          icon: document.sourceKind.icon,
          subtitle: l10n.timelineDocumentSubtitle(
            document.eventCount,
            document.range,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final entries = _entries(l10n);

    final needle = normalizeVocabularyLabel(_searchController.text);
    final visible = entries == null || needle.isEmpty
        ? entries
        : [
            for (final entry in entries)
              if (normalizeVocabularyLabel(entry.title).contains(needle)) entry,
          ];

    return Padding(
      // Con el teclado arriba, la lista que se filtra queda a la vista.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  _topics
                      ? l10n.timelineTopicSheetTitle
                      : l10n.timelineDocumentSheetTitle,
                  style: theme.textTheme.titleMedium,
                ),
                dense: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _topics
                        ? l10n.timelineTopicSearchHint
                        : l10n.timelineDocumentSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(28)),
                    ),
                  ),
                ),
              ),
              Flexible(child: _body(l10n, theme, entries, visible)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    AppLocalizations l10n,
    ThemeData theme,
    List<_PickerEntry>? all,
    List<_PickerEntry>? visible,
  ) {
    if (visible == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (visible.isEmpty) {
      final nothingAtAll = all!.isEmpty;
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          nothingAtAll
              ? (_topics
                    ? l10n.timelineTopicsEmpty
                    : l10n.timelineDocumentsEmpty)
              : l10n.timelinePickerNoMatch,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final entry = visible[index];
        return ListTile(
          key: ValueKey('timeline-pick-${entry.scope.id}'),
          leading: Icon(entry.icon),
          title: Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
          onTap: () => Navigator.of(context).pop(entry.scope),
        );
      },
    );
  }
}
