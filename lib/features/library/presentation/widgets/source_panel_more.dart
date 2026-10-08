import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/core/util/transcript_timestamps.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organize_now.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/features/content_trash/presentation/content_trash_actions.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/reextract_text.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/open_document_viewer.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se usa de vez en cuando con una fuente, en la hoja "Más" del
/// panel de la fuente (F26, decisión A): a la vista solo lo de todos los
/// días —leer, resumir, copiar—, y esto a un toque más.
enum SourceMoreAction {
  /// Que la IA lo organice ahora, antes que lo demás (F27): lo de la
  /// biblioteca existente sin esperar al cargador, o lo que se deshizo y la
  /// IA no vuelve a tocar sola.
  organizeWithAi,

  /// Volver a extraer el texto, con el idioma (F22).
  reextract,

  /// Quitar las marcas de tiempo de una transcripción (F22).
  removeTimestamps,

  /// Borrar el archivo pesado y quedarse con el texto: el archivo va a la
  /// papelera de la app por 30 días (F30, decisión 68).
  deleteOriginalFile,

  /// Borrar el texto de un libro o un documento y quedarse con el archivo: el
  /// texto va a la papelera de la app por 30 días y no se vuelve a extraer
  /// solo (F30, decisión 68).
  deleteText,

  /// El documento original a pantalla completa.
  fullScreen,
}

/// Las opciones de "Más" que aplican a [item], en el orden de la hoja: solo
/// las que se pueden hacer ahora. A una página web o una nota lista solo se
/// le puede pedir que la organice la IA; mientras algo se procesa, o si
/// falló sin texto, no hay nada que ofrecer.
List<SourceMoreAction> sourceMoreActionsFor(KnowledgeItem item) {
  final hasText = item.renditions.whereType<TextRendition>().isNotEmpty;
  return [
    // Solo lo que está listo, como la cola de la IA: organizar a medio
    // procesar sería vincular y hacer tarjetas de un texto que va a cambiar.
    if (item.processingState == ProcessingState.ready)
      SourceMoreAction.organizeWithAi,
    // También en «solo el libro» (F30, decisión 68): sin texto a propósito,
    // la persona sí puede pedir que se vuelva a extraer.
    if ((hasText || item.source.onlyFile) && canReextractText(item))
      SourceMoreAction.reextract,
    // Mientras se vuelve a extraer, el texto no se ve y va a ser
    // reemplazado: ni quitarle las marcas ni soltar el archivo que se está
    // leyendo de nuevo.
    if (!item.isBeingProcessed && _timestamped(item).isNotEmpty)
      SourceMoreAction.removeTimestamps,
    if (!item.isBeingProcessed && canKeepOnlyText(item))
      SourceMoreAction.deleteOriginalFile,
    if (!item.isBeingProcessed && canKeepOnlyFile(item))
      SourceMoreAction.deleteText,
    if (item.source.kind == SourceKind.document &&
        item.source.originalFilePath != null)
      SourceMoreAction.fullScreen,
  ];
}

/// Las formas de texto de una transcripción que todavía tienen marcas de
/// tiempo —`[mm:ss]` al principio de cada línea, las pone
/// `formatTranscript`—. Solo en una transcripción: un PDF con una línea que
/// empieza con "[12:30]" no tiene marcas que quitar (F22).
List<TextRendition> _timestamped(KnowledgeItem item) {
  if (!isTranscriptSource(item.source)) return const [];
  return [
    for (final rendition in item.renditions.whereType<TextRendition>())
      if (rendition.kind != RenditionKind.blocks &&
          hasTimestamps(rendition.content))
        rendition,
  ];
}

/// Si tiene sentido ofrecer "borrar el archivo, quedarme con el texto".
///
/// Hace falta que el original sea un video, un audio, una publicación o un
/// libro o documento (F30) —los formatos pesados, donde soltar el archivo
/// cambia algo— y que ya haya un texto guardado aparte: sin él, soltar el
/// archivo se llevaría todo el contenido del elemento.
bool canKeepOnlyText(KnowledgeItem item) {
  const keepable = {
    SourceKind.youtube,
    SourceKind.audio,
    SourceKind.video,
    SourceKind.socialPost,
    SourceKind.document,
  };
  if (!keepable.contains(item.source.kind)) return false;
  // Sin archivo no hay nada que soltar: un video de YouTube cuyo audio no se
  // bajó —ya no se baja solo (F21)— tiene transcripción pero ningún archivo.
  if (item.source.originalFilePath == null) return false;

  return _hasOwnText(item);
}

/// Si tiene sentido ofrecer "borrar el texto, quedarme con el libro" (F30,
/// decisión 68): un libro o un documento con su archivo y con un texto que
/// soltar. Solo ahí: el texto de un audio o de una página no se puede volver
/// a sacar de nada que la persona quiera conservar como «el libro».
bool canKeepOnlyFile(KnowledgeItem item) =>
    item.source.kind == SourceKind.document &&
    item.source.originalFilePath != null &&
    _hasOwnText(item);

/// Si el elemento tiene un texto propio con algo escrito: el mismo que se
/// lee y del que se sacan notas, no el de un archivo de su «Contenido».
bool _hasOwnText(KnowledgeItem item) =>
    extractableRendition(item)?.content.trim().isNotEmpty ?? false;

/// Abre la hoja "Más" con [actions] y hace la que se elija.
///
/// La hoja se cierra antes de hacerla: volver a extraer y borrar el archivo
/// abren su propio diálogo, que no tiene que quedar encima de la hoja.
Future<void> showSourceMoreSheet(
  BuildContext context,
  WidgetRef ref,
  KnowledgeItem item,
  List<SourceMoreAction> actions,
) async {
  final chosen = await showModalBottomSheet<SourceMoreAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => _SourceMoreSheet(actions: actions),
  );
  if (chosen == null || !context.mounted) return;

  switch (chosen) {
    case SourceMoreAction.organizeWithAi:
      await organizeNowWithAi(context, ref, itemId: item.id);
    case SourceMoreAction.reextract:
      await reextractText(context, ref, item);
    case SourceMoreAction.removeTimestamps:
      await _removeTimestamps(context, ref, item);
    case SourceMoreAction.deleteOriginalFile:
      await trashOriginalFile(context, ref, item);
    case SourceMoreAction.deleteText:
      await trashExtractedText(context, ref, item);
    case SourceMoreAction.fullScreen:
      await openDocumentViewer(context, ref, item);
  }
}

class _SourceMoreSheet extends StatelessWidget {
  const _SourceMoreSheet({required this.actions});

  final List<SourceMoreAction> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.sourcePanelMoreTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            for (final action in actions)
              ListTile(
                key: Key('source-more-${action.name}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                // Lo de la IA lleva su ✨, el mismo de todo lo que hace sola.
                leading: action == SourceMoreAction.organizeWithAi
                    ? const AiSparkCircle(size: 40)
                    : SourcePanelIconCircle(
                        icon: action.icon,
                        tone:
                            action == SourceMoreAction.deleteOriginalFile ||
                                action == SourceMoreAction.deleteText
                            ? SourcePanelTone.error
                            : SourcePanelTone.neutral,
                      ),
                title: Text(action.title(l10n)),
                subtitle: Text(action.hint(l10n)),
                onTap: () => Navigator.of(context).pop(action),
              ),
          ],
        ),
      ),
    );
  }
}

extension on SourceMoreAction {
  IconData get icon => switch (this) {
    SourceMoreAction.organizeWithAi => Icons.auto_awesome,
    SourceMoreAction.reextract => Icons.refresh,
    SourceMoreAction.removeTimestamps => Icons.timer_off_outlined,
    SourceMoreAction.deleteOriginalFile => Icons.delete_sweep_outlined,
    SourceMoreAction.deleteText => Icons.notes_outlined,
    SourceMoreAction.fullScreen => Icons.open_in_full,
  };

  String title(AppLocalizations l10n) => switch (this) {
    SourceMoreAction.organizeWithAi => l10n.sourcePanelOrganizeWithAi,
    SourceMoreAction.reextract => l10n.detailReextract,
    SourceMoreAction.removeTimestamps => l10n.detailRemoveTimestamps,
    SourceMoreAction.deleteOriginalFile => l10n.detailDeleteOriginalFile,
    SourceMoreAction.deleteText => l10n.detailDeleteText,
    SourceMoreAction.fullScreen => l10n.detailExpandViewer,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    SourceMoreAction.organizeWithAi => l10n.sourcePanelOrganizeWithAiHint,
    SourceMoreAction.reextract => l10n.sourcePanelReextractHint,
    SourceMoreAction.removeTimestamps => l10n.sourcePanelRemoveTimestampsHint,
    SourceMoreAction.deleteOriginalFile => l10n.sourcePanelTrashFileHint,
    SourceMoreAction.deleteText => l10n.sourcePanelDeleteTextHint,
    SourceMoreAction.fullScreen => l10n.sourcePanelFullScreenHint,
  };
}

/// Lo que el usuario pide es no ver los minutos, no que se toque lo dicho:
/// ver `stripTimestamps`.
Future<void> _removeTimestamps(
  BuildContext context,
  WidgetRef ref,
  KnowledgeItem item,
) async {
  final l10n = AppLocalizations.of(context)!;
  final timestamped = {for (final r in _timestamped(item)) r.id};

  final updated = item.copyWith(
    renditions: [
      for (final r in item.renditions)
        if (r is TextRendition && timestamped.contains(r.id))
          r.copyWith(content: stripTimestamps(r.content))
        else
          r,
    ],
  );

  final result = await ref.read(libraryRepositoryProvider).save(updated);
  if (!context.mounted) return;

  result.match(
    (failure) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
    (_) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.detailTimestampsRemoved))),
  );
}
