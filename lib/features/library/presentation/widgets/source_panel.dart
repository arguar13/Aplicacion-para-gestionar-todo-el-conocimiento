import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/blocks/presentation/screens/block_editor_screen.dart';
import 'package:sinapsis/features/library/presentation/widgets/reextract_text.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_more.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/features/library/presentation/widgets/summarize_button.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/transform/presentation/widgets/processing_status.dart';
import 'package:sinapsis/features/transform/presentation/widgets/youtube_audio_download_section.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El panel de la fuente (F26): todo lo que se hace con un elemento, en una
/// sola tarjeta entre su vista previa y su texto, siempre en el mismo lugar
/// y una sola vez por elemento.
///
/// Antes eran hasta ocho controles sueltos —cinco tipos de botón, filas
/// alineadas a la derecha y otras a la izquierda, una fila repetida por cada
/// texto, las acciones de un PDF escondidas dentro del texto plegado—. Ahora,
/// de arriba abajo y cada parte solo cuando hace falta:
///
/// 1. **El audio** de un video, un TikTok o un video de YouTube (decisión
///    B): el mismo reproductor que el video de arriba. En un audio no, porque
///    la vista previa ya es el reproductor.
/// 2. **Lo que está pasando**: bajando el audio, extrayendo o volviendo a
///    extraer el texto, un fallo con su único "Reintentar", el modelo que
///    falta. Ver [SourcePanelStatus].
/// 3. **Cuatro mosaicos** iguales (decisión A): Leer, Resumir, Copiar y
///    Más —en una nota de bloques, Editar en vez de Más—. Ver
///    [SourcePanelTile].
/// 4. Lo que se le sume después, en [extraSections].
///
/// Las partes que aparecen o se van —una descarga que termina, un fallo que
/// se reintenta— lo hacen con una animación de alto, sin saltos.
class SourcePanel extends ConsumerWidget {
  const SourcePanel({
    required this.item,
    this.extraSections = const [],
    super.key,
  });

  final KnowledgeItem item;

  /// Secciones de más, debajo de los mosaicos y con el mismo separador: el
  /// lugar donde F27 cuenta lo que la IA organizó sola ("La IA organizó
  /// esto: …") —ver `AiOrganizedLine`—. Cada una va solo si tiene algo que
  /// decir: una vacía dejaría su separador suelto.
  final List<Widget> extraSections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final videoAudio = _videoAudioPath(ref);

    final sections = [
      if (_hasYouTubeAudio(item))
        YouTubeAudioDownloadSection(item: item)
      else if (videoAudio != null)
        SourcePanelAudio(
          path: videoAudio,
          playerKey: const Key('video-audio-player'),
        ),
      if (_hasStatus(item)) _ProcessingStatus(item: item),
      _ActionTiles(item: item),
      ...extraSections,
    ];

    // `Material` y no una caja pintada: la onda de los mosaicos se dibuja en
    // el `Material` más cercano, y debajo de una caja con color quedaría
    // tapada.
    return Material(
      key: const Key('source-panel'),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, section) in sections.indexed) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: sourcePanelInset,
                  endIndent: sourcePanelInset,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              section,
            ],
          ],
        ),
      ),
    );
  }

  /// El archivo de un video del teléfono o un TikTok con video, para
  /// escuchar su audio en el panel; `null` si no es un video. En la web no
  /// hay archivo que abrir —ver `EmbeddedFileViewer`—.
  String? _videoAudioPath(WidgetRef ref) {
    final kind = item.source.kind;
    if (kIsWeb ||
        item.source.originalFilePath == null ||
        (kind != SourceKind.video && kind != SourceKind.socialPost)) {
      return null;
    }
    return switch (ref.watch(resolvedFileViewerProvider(item))) {
      AsyncData(value: MediaResolvedViewer(:final path, isVideo: true)) => path,
      _ => null,
    };
  }
}

/// Si el panel muestra el audio de un video de YouTube —bajado, o
/// bajándose—. En la web no hay dónde guardarlo como archivo (F24).
bool _hasYouTubeAudio(KnowledgeItem item) =>
    !kIsWeb &&
    item.source.kind == SourceKind.youtube &&
    (item.source.originalFilePath != null || item.source.url != null);

/// Si hay algo que contar del texto: que todavía no llegó, que se está
/// volviendo a extraer o que algo falló.
bool _hasStatus(KnowledgeItem item) =>
    !_hasText(item) ||
    item.isBeingProcessed ||
    item.processingState == ProcessingState.failed;

bool _hasText(KnowledgeItem item) =>
    item.renditions.whereType<TextRendition>().isNotEmpty;

/// La franja de estado del texto del elemento (F26): lo que antes eran el
/// aviso de "todavía no hay contenido", la barra de avance y el motivo de un
/// fallo, cada uno con su forma, ahora en la misma franja del panel.
///
/// Dice explícitamente que lo guardado sigue ahí: sin esa aclaración, una
/// pantalla sin texto se lee como "no se guardó nada" y el usuario vuelve a
/// capturarlo, o peor, deja de confiar en la app.
class _ProcessingStatus extends ConsumerWidget {
  const _ProcessingStatus({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Los dos se escuchan siempre y se usan según el estado. Escucharlos
    // solo cuando corresponde suscribía y desuscribía la consulta en medio
    // de un cuadro cada vez que el elemento cambiaba de estado —al tocar
    // "Reintentar", por ejemplo—.
    final activeProgress = ref.watch(processingProgressProvider(item.id));
    final failure = ref.watch(processingFailureProvider(item.id)).valueOrNull;
    final failed = item.processingState == ProcessingState.failed;
    final hasText = _hasText(item);

    final Widget status;
    if (failed) {
      // La causa real del fallo, no un "no se pudo" genérico (F21): lo que
      // falta —un modelo, la conexión— dice también qué hacer.
      status = SourcePanelStatus(
        icon: Icons.error_outline,
        tone: SourcePanelTone.error,
        message:
            failureMessage(l10n, failure) ??
            (hasText
                ? l10n.sourcePanelReextractFailed
                : _emptyStateMessage(l10n, item: item, failed: true)),
        action: failure == ProcessingFailureReason.transcriptionModelMissing
            // Reintentar sin el modelo volvería a fallar igual: lo que
            // resuelve es descargarlo, y al terminar este elemento se
            // retoma solo.
            ? SourcePanelStatusButton(
                icon: Icons.download,
                label: l10n.failureTranscriptionModelAction,
                onPressed: () => context.push(RoutePaths.transcriptionModel),
              )
            // Reintentar es a pedido y no automático en cada arranque: un
            // fallo puede ser permanente —un video borrado, una página que
            // ya no existe— y volver a intentarlo solo gastaría batería y
            // datos para fallar de nuevo. Quien sabe si vale la pena es el
            // usuario.
            : SourcePanelStatusButton(
                icon: Icons.refresh,
                label: l10n.detailRetry,
                onPressed: () => unawaited(
                  ref.read(processingQueueProvider.notifier).retry(item.id),
                ),
              ),
      );
    } else {
      // Un libro de cientos de páginas o un video de horas: la barra dice
      // cuánto va, y el original se puede abrir y leer mientras tanto.
      final progress = activeProgress == null
          ? null
          : ProcessingProgressBar(
              progress: activeProgress,
              kind: item.source.kind,
            );
      // «Solo el libro» (F30, decisión 68): sin texto a propósito. No es que
      // falte —no hay nada que esperar—: se dice, y se ofrece traerlo.
      final onlyFile =
          item.source.onlyFile && !hasText && !item.isBeingProcessed;
      status = onlyFile
          ? SourcePanelStatus(
              icon: Icons.menu_book_outlined,
              message: l10n.sourcePanelOnlyFile,
              messageKey: const Key('only-file-status'),
              action: SourcePanelStatusButton(
                icon: Icons.refresh,
                label: l10n.sourcePanelOnlyFileAction,
                onPressed: () => unawaited(reextractText(context, ref, item)),
              ),
            )
          : hasText
          // Volviendo a extraer: el texto viejo ya no se muestra —el usuario
          // lo pidió así: que no quede a la vista algo que se está
          // reemplazando—, pero sigue guardado hasta que el nuevo está
          // listo; si falla, vuelve a verse con el motivo.
          ? SourcePanelStatus(
              icon: Icons.autorenew,
              message: l10n.detailReextractInProgress,
              messageKey: const Key('reextracting-text'),
              progress: progress,
            )
          : SourcePanelStatus(
              icon: switch (item.processingState) {
                ProcessingState.pending => Icons.schedule,
                ProcessingState.processing => Icons.hourglass_empty,
                _ => Icons.info_outline,
              },
              message: _emptyStateMessage(l10n, item: item, failed: false),
              progress: progress,
            );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(
        key: ValueKey((failed, hasText, item.processingState)),
        child: status,
      ),
    );
  }
}

/// Qué decir cuando todavía no hay contenido.
///
/// El mensaje cambia según de dónde vino el elemento, y no es un matiz: a
/// quien guardó un enlace le importa saber que el enlace está a salvo, y a
/// quien guardó un PDF le importa saber que el archivo está a salvo. Decirle
/// "el enlace sigue guardado" a alguien que nunca guardó un enlace suena a
/// mensaje equivocado, y hace dudar de si su documento sigue ahí.
String _emptyStateMessage(
  AppLocalizations l10n, {
  required KnowledgeItem item,
  required bool failed,
}) {
  final fromFile = item.source.originalFilePath != null;

  if (failed) {
    return fromFile
        ? l10n.detailExtractionFailedFile
        : l10n.detailExtractionFailed;
  }

  return fromFile ? l10n.detailNoContentYetFile : l10n.detailNoContentYet;
}

/// Las cuatro acciones a la vista (F26, decisión A), siempre las mismas y en
/// el mismo lugar: sin texto todavía —o mientras se vuelve a extraer— se ven
/// apagadas, no desaparecen.
class _ActionTiles extends ConsumerWidget {
  const _ActionTiles({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final text = item.isBeingProcessed ? null : _workingText(item);
    final blocks = _blocksRendition(item);
    final readable =
        !item.isBeingProcessed && extractableRendition(item) != null;
    final more = sourceMoreActionsFor(item);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SourcePanelTile(
              key: const Key('source-panel-read'),
              icon: Icons.menu_book_outlined,
              label: l10n.sourcePanelRead,
              tooltip: readable
                  ? l10n.readingOpenAction
                  : text != null
                  // Una nota de bloques: la lectura para destilar trabaja
                  // sobre el texto de una fuente —ver `extractableRendition`—.
                  ? l10n.sourcePanelReadNeedsSource
                  : l10n.sourcePanelNeedsText,
              onTap: readable
                  ? () => context.push(RoutePaths.reading(item.id))
                  : null,
            ),
          ),
          Expanded(child: _SummarizeTile(content: text)),
          Expanded(
            child: SourcePanelTile(
              key: const Key('source-panel-copy'),
              icon: Icons.copy_outlined,
              label: l10n.sourcePanelCopy,
              tooltip: text == null
                  ? l10n.sourcePanelNeedsText
                  : l10n.detailCopyContent,
              onTap: text == null ? null : () => _copy(context, text),
            ),
          ),
          Expanded(
            child: blocks != null
                ? SourcePanelTile(
                    key: const Key('source-panel-edit'),
                    icon: Icons.edit_outlined,
                    label: l10n.blocksEditAction,
                    tooltip: l10n.sourcePanelEditTooltip,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) =>
                            BlockEditorScreen(existingItem: item),
                      ),
                    ),
                  )
                : SourcePanelTile(
                    key: const Key('source-panel-more'),
                    icon: Icons.more_horiz,
                    label: l10n.sourcePanelMore,
                    tooltip: more.isEmpty
                        ? l10n.sourcePanelNothingMore
                        : l10n.sourcePanelMoreTitle,
                    onTap: more.isEmpty
                        ? null
                        : () => unawaited(
                            showSourceMoreSheet(context, ref, item, more),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.detailContentCopied)));
  }
}

/// "Resumir" con el mismo comportamiento que el botón de siempre —ver
/// [SummarizeOnDemand]—: mientras espera el resumen, el ícono gira.
class _SummarizeTile extends ConsumerStatefulWidget {
  const _SummarizeTile({required this.content});

  /// Lo que se resume; `null` si todavía no hay texto.
  final String? content;

  @override
  ConsumerState<_SummarizeTile> createState() => _SummarizeTileState();
}

class _SummarizeTileState extends ConsumerState<_SummarizeTile>
    with SummarizeOnDemand {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final content = widget.content;

    return SourcePanelTile(
      key: const Key('source-panel-summarize'),
      icon: Icons.auto_awesome_outlined,
      label: l10n.sourcePanelSummarize,
      tooltip: content == null
          ? l10n.sourcePanelNeedsText
          : l10n.summarizeAction,
      busy: summarizing,
      onTap: content == null ? null : () => unawaited(summarize(content)),
    );
  }
}

/// La nota de bloques del elemento, si es una.
TextRendition? _blocksRendition(KnowledgeItem item) => item.renditions
    .whereType<TextRendition>()
    .where((r) => r.kind == RenditionKind.blocks)
    .firstOrNull;

/// El texto con que trabajan Resumir y Copiar: el mismo que se lee para
/// destilar —ver `extractableRendition`—, o el de una nota de bloques.
///
/// De una nota de bloques, el texto de cada bloque con un punto y aparte: un
/// resumen o una copia no distinguen encabezados de párrafos, y el JSON con
/// que se guarda no es para leer tal cual.
String? _workingText(KnowledgeItem item) {
  if (extractableRendition(item) case final rendition?) {
    return rendition.content;
  }
  if (_blocksRendition(item) case final blocks?) {
    return decodeContentBlocks(blocks.content).map((b) => b.text).join('\n\n');
  }
  return null;
}
