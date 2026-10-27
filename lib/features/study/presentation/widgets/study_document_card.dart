import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/export/presentation/providers/marked_download_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_extracts.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/study_progress_texts.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_download_sheet.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La tarjeta «Estudiar el documento» del detalle (F36): entre el original y
/// lo demás, en todo lo que trae un texto propio —un documento, una página,
/// una publicación, una imagen, un audio, un video (F39)—.
///
/// - **Arriba, los tres botones** —ver [StudyToggles]— y una leyenda chica
///   con sus colores. Lo que prenden se resalta en el original, en «Leer como
///   libro» y en el texto extraído.
/// - **Mientras analiza**, una franja con la parte que va, su barra y
///   «Parar». Si se corta o una parte no se pudo leer, lo dice ahí mismo.
/// - **Abajo, «Extraer»**: el texto extraído —si viene [extractedText]; la
///   transcripción, en un audio o un video—, las fotos de una página o una
///   publicación —con [photos]—, el resumen, la síntesis y las palabras
///   clave, cada uno plegado, con cuánto tiene, «Copiar» y «Escuchar» (F39).
///   El texto entero y las fotos van plegados acá y no desplegados debajo de
///   la tarjeta: ocupan mucho.
/// - **«Escuchar»** lee en voz alta, con el lector flotante, solo lo de esa
///   fila: las oraciones del resumen o de la síntesis, o las palabras clave,
///   en el orden del texto. Se resalta en amarillo en su lugar del texto y en
///   la propia fila.
/// - Con [item], **«Descargar»** (F38): el original en su mismo formato con
///   el resumen, la síntesis, las palabras clave o los subrayados marcados.
///   Solo aparece si el formato del original se puede marcar.
/// - En su menú, **«Volver a analizar»**, que pregunta antes: reemplaza
///   también las palabras elegidas a mano.
class StudyDocumentCard extends ConsumerWidget {
  const StudyDocumentCard({
    required this.text,
    this.item,
    this.kind = SourceKind.document,
    this.extractedText,
    this.extractedTextTitle,
    this.extractedTextSubtitle,
    this.extractedTextController,
    this.photoCount = 0,
    this.photos,
    super.key,
  });

  final StudyText text;

  /// El elemento, para descargar su original marcado. Sin él no hay botón
  /// «Descargar».
  final KnowledgeItem? item;

  /// Qué es lo que se estudia: cambia solo el título.
  final SourceKind kind;

  /// El texto extraído, armado recién al desplegar su fila: el de un libro
  /// entero no se arma si nadie lo abre. Sin él, no hay fila de texto.
  final WidgetBuilder? extractedText;

  /// El nombre de la fila del texto; sin él, «Extraer texto».
  final String? extractedTextTitle;

  /// Para qué está el texto extraído, debajo de su fila.
  final String? extractedTextSubtitle;

  /// Para desplegar la fila del texto desde afuera: «Volver al audio», con
  /// la transcripción plegada, la despliega para mostrar lo que suena.
  final ExpansibleController? extractedTextController;

  /// Cuántas fotos trae la página o la publicación (F39); sin ninguna, no
  /// hay fila «Fotos».
  final int photoCount;

  /// Las fotos, armadas recién al desplegar su fila.
  final WidgetBuilder? photos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final study =
        ref.watch(documentStudyProvider(text.renditionId)).valueOrNull ??
        DocumentStudy.notStarted;
    final listening = _Listening(
      text: text,
      study: study,
      title: item?.title ?? '',
      transcript: item != null && isTranscriptSource(item!.source),
    );

    return Material(
      key: const Key('study-document-card'),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.school_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(switch (kind) {
                    SourceKind.webPage => l10n.studyCardTitleWebPage,
                    SourceKind.socialPost => l10n.studyCardTitlePost,
                    SourceKind.image => l10n.studyCardTitleImage,
                    SourceKind.audio => l10n.studyCardTitleAudio,
                    SourceKind.video ||
                    SourceKind.youtube => l10n.studyCardTitleVideo,
                    _ => l10n.studyCardTitle,
                  }, style: theme.textTheme.titleMedium),
                ),
                if (item case final item?)
                  _DownloadButton(item: item, text: text),
                _StudyMenu(text: text),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  StudyToggles(
                    text: text,
                    onManual: extractedTextController?.expand,
                  ),
                  const SizedBox(height: 8),
                  const _StudyLegend(),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _StudyProgressStrip(text: text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(
              height: 1,
              endIndent: 12,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                l10n.studyExtractTitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (extractedText case final builder?)
              _ExtractRow(
                key: const Key('study-extract-text'),
                icon: Icons.notes_outlined,
                title: extractedTextTitle ?? l10n.studyExtractText,
                subtitle: extractedTextSubtitle,
                controller: extractedTextController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: _ListenButton(
                        listening: listening,
                        scope: ReadScope.all,
                      ),
                    ),
                    Builder(builder: builder),
                  ],
                ),
              ),
            if (photos case final builder? when photoCount > 0)
              _ExtractRow(
                key: const Key('study-extract-photos'),
                icon: Icons.photo_library_outlined,
                title: l10n.studyExtractPhotos,
                subtitle: l10n.studyPhotoCount(photoCount),
                child: Builder(builder: builder),
              ),
            _SentencesRow(
              key: const Key('study-extract-summary'),
              title: l10n.studyExtractSummary,
              color: StudyPalette.of(theme.brightness).summary,
              text: text,
              study: study,
              listening: listening,
              kind: StudyMarkKind.summary,
              onManual: extractedTextController?.expand,
            ),
            _SentencesRow(
              key: const Key('study-extract-synthesis'),
              title: l10n.studyExtractSynthesis,
              color: StudyPalette.of(theme.brightness).synthesis,
              text: text,
              study: study,
              listening: listening,
              kind: StudyMarkKind.synthesis,
              onManual: extractedTextController?.expand,
            ),
            _KeywordsRow(
              text: text,
              study: study,
              listening: listening,
              onManual: extractedTextController?.expand,
            ),
          ],
        ),
      ),
    );
  }
}

/// «Descargar» (F38): abre la hoja con lo que se puede marcar en el original.
/// No aparece si el original no es de un formato que se sepa marcar.
class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.item, required this.text});

  final KnowledgeItem item;
  final StudyText text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final format = ref
        .watch(
          markedDownloadFormatProvider((
            kind: item.source.kind,
            path: item.source.originalFilePath,
          )),
        )
        .valueOrNull;
    if (format == null) return const SizedBox.shrink();

    return TextButton.icon(
      key: const Key('study-download'),
      icon: const Icon(Icons.download_outlined, size: 20),
      label: Text(l10n.studyDownload),
      onPressed: () => unawaited(
        showStudyDownloadSheet(context, item: item, text: text, format: format),
      ),
    );
  }
}

/// Los tres colores y qué es cada uno.
class _StudyLegend extends StatelessWidget {
  const _StudyLegend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = StudyPalette.of(theme.brightness);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget entry(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        entry(palette.summary, l10n.studyLegendSummary),
        entry(palette.synthesis, l10n.studyLegendSynthesis),
        entry(palette.keyword, l10n.studyKeywords),
      ],
    );
  }
}

/// Cómo va el análisis: la parte que va y «Parar»; si se cortó,
/// «Reintentar»; si una parte no se pudo leer, cuántas. Sin nada que
/// contar, no ocupa lugar.
class _StudyProgressStrip extends ConsumerWidget {
  const _StudyProgressStrip({required this.text});

  final StudyText text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(studyAnalysisProvider(text.renditionId));
    final notifier = ref.read(studyAnalysisProvider(text.renditionId).notifier);

    return switch (state) {
      StudyAnalysisIdle() || StudyAnalysisDone(unreadParts: 0) =>
        const SizedBox(width: double.infinity),
      final StudyAnalysisRunning running => _Strip(
        key: const Key('study-progress'),
        message: studyRunningMessage(l10n, running),
        running: true,
        progress: running.progress == null || running.progress!.partsTotal == 0
            ? null
            : running.progress!.partsDone / running.progress!.partsTotal,
        action: l10n.studyStop,
        onAction: notifier.stop,
      ),
      StudyAnalysisDone(:final unreadParts) => _Strip(
        key: const Key('study-unread'),
        message: l10n.studyUnreadParts(unreadParts),
        action: l10n.studyUnreadAcknowledge,
        onAction: notifier.acknowledge,
      ),
      final StudyAnalysisFailed failed => _Strip(
        key: const Key('study-failed'),
        message: studyFailedMessage(l10n, failed),
        action: l10n.studyRetry,
        onAction: () {
          notifier.acknowledge();
          unawaited(analyzeForStudyIfNeeded(ref, context, text));
        },
      ),
    };
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.message,
    required this.action,
    required this.onAction,
    this.running = false,
    this.progress,
    super.key,
  });

  final String message;

  /// Si está analizando: lleva la barra. Un aviso va sin ella.
  final bool running;

  /// Cuánto va, de 0 a 1; `null`, sin saber todavía.
  final double? progress;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
              TextButton(onPressed: onAction, child: Text(action)),
            ],
          ),
          if (running)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
        ],
      ),
    );
  }
}

/// El menú de la tarjeta: «Volver a analizar», después de preguntar.
class _StudyMenu extends ConsumerWidget {
  const _StudyMenu({required this.text});

  final StudyText text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final running =
        ref.watch(studyAnalysisProvider(text.renditionId))
            is StudyAnalysisRunning;

    return PopupMenuButton<void>(
      key: const Key('study-menu'),
      tooltip: l10n.studyMoreTooltip,
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          key: const Key('study-reanalyze'),
          enabled: !running,
          onTap: () => unawaited(_reanalyze(context, ref)),
          child: Text(l10n.studyReanalyze),
        ),
      ],
    );
  }

  Future<void> _reanalyze(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.studyReanalyzeTitle),
        content: Text(l10n.studyReanalyzeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('study-reanalyze-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.studyReanalyze),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ready = await ensureStudyModelReady(context, ref);
    if (!ready || !context.mounted) return;
    await reanalyzeForStudy(
      ref,
      renditionId: text.renditionId,
      content: text.content,
      markdown: text.markdown,
      itemId: text.itemId,
    );
  }
}

/// Una fila de «Extraer», plegada: se arma recién al desplegarla.
class _ExtractRow extends StatelessWidget {
  const _ExtractRow({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.iconColor,
    this.controller,
    super.key,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final ExpansibleController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      controller: controller,
      tilePadding: const EdgeInsets.only(right: 12),
      childrenPadding: const EdgeInsets.only(right: 12, bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      leading: Icon(icon, color: iconColor),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      children: [child],
    );
  }
}

/// «Extraer resumen» o «Extraer síntesis»: sus oraciones en orden, como
/// texto corrido, con cuántas oraciones y palabras son. Vacía, al
/// desplegarla ofrece armarlo con la IA o a mano (F39).
///
/// Con «Escuchar», la oración que suena se resalta en amarillo acá mismo,
/// además de en el texto.
class _SentencesRow extends ConsumerWidget {
  const _SentencesRow({
    required this.title,
    required this.color,
    required this.text,
    required this.study,
    required this.listening,
    required this.kind,
    this.onManual,
    super.key,
  });

  final String title;
  final Color color;
  final StudyText text;
  final DocumentStudy study;
  final _Listening listening;
  final StudyMarkKind kind;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final parts = studySentenceParts(text.content, study, kind);
    final extract = studySentencesExtract(text.content, study, kind);
    final has = extract.sentences > 0;

    return _ExtractRow(
      icon: Icons.format_color_fill_outlined,
      iconColor: color,
      title: title,
      subtitle: has
          ? '${l10n.studySentenceCount(extract.sentences)} · '
                '${l10n.studyWordCount(extract.words)}'
          : _emptyHint(l10n, study),
      child: has
          ? _Extracted(
              copyText: extract.text,
              listen: _ListenButton(
                listening: listening,
                scope: kind == StudyMarkKind.summary
                    ? ReadScope.summary
                    : ReadScope.synthesis,
              ),
              child: _ReadingSentences(
                parts: parts,
                renditionId: text.renditionId,
              ),
            )
          : _EmptyExtract(text: text, kind: kind, onManual: onManual),
    );
  }
}

/// Las oraciones del resumen o de la síntesis, una tras otra; la que el
/// lector en voz alta está leyendo, en amarillo.
class _ReadingSentences extends ConsumerWidget {
  const _ReadingSentences({required this.parts, required this.renditionId});

  final List<StudySentencePart> parts;
  final String renditionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(readAloudHighlightProvider(renditionId));
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final (index, part) in parts.indexed) ...[
            if (index > 0) const TextSpan(text: ' '),
            TextSpan(
              text: part.text,
              style: _readingStyle(reading, part.mark.start, part.mark.end),
            ),
          ],
        ],
      ),
    );
  }
}

/// Si `[start, end)` del texto toca lo que el lector está leyendo.
bool _isBeingRead((int, int)? reading, int start, int end) =>
    reading != null && start < reading.$2 && end > reading.$1;

/// El amarillo de lo que suena, con letra oscura también en modo oscuro, si
/// `[start, end)` toca lo que se está leyendo; si no, ningún estilo.
TextStyle? _readingStyle((int, int)? reading, int start, int end) =>
    _isBeingRead(reading, start, end)
    ? const TextStyle(
        backgroundColor: RenderedMarkdown.playingColor,
        color: Colors.black87,
      )
    : null;

/// «Extraer palabras clave»: como etiquetas, en el orden en que aparecen.
/// La que suena con «Escuchar» se resalta en amarillo.
class _KeywordsRow extends ConsumerWidget {
  const _KeywordsRow({
    required this.text,
    required this.study,
    required this.listening,
    this.onManual,
  });

  final StudyText text;
  final DocumentStudy study;
  final _Listening listening;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final palette = StudyPalette.of(Theme.of(context).brightness);
    final parts = studyKeywordParts(text.content, study);
    if (parts.isEmpty) {
      return _ExtractRow(
        key: const Key('study-extract-keywords'),
        icon: Icons.key_outlined,
        iconColor: palette.keyword,
        title: l10n.studyExtractKeywords,
        subtitle: _emptyHint(l10n, study),
        child: _EmptyExtract(
          text: text,
          kind: StudyMarkKind.keyword,
          onManual: onManual,
        ),
      );
    }

    final reading = ref.watch(readAloudHighlightProvider(text.renditionId));
    return _ExtractRow(
      key: const Key('study-extract-keywords'),
      icon: Icons.key_outlined,
      iconColor: palette.keyword,
      title: l10n.studyExtractKeywords,
      subtitle: l10n.studyKeywordCount(parts.length),
      child: _Extracted(
        copyText: [for (final part in parts) part.word].join(', '),
        listen: _ListenButton(listening: listening, scope: ReadScope.keywords),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final part in parts)
              Chip(
                label: Text(part.word),
                labelStyle: const TextStyle(color: StudyPalette.ink),
                backgroundColor:
                    _isBeingRead(reading, part.mark.start, part.mark.end)
                    ? RenderedMarkdown.playingColor
                    : palette.keyword,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

/// Antes de analizar, cómo empezar; después, que no hay nada.
String _emptyHint(AppLocalizations l10n, DocumentStudy study) =>
    study.started ? l10n.studyExtractEmpty : l10n.studyExtractStart;

/// Una fila de «Extraer» vacía, desplegada (F39): mientras la IA analiza, que
/// va a aparecer acá; si no, los dos caminos para armarlo.
class _EmptyExtract extends ConsumerWidget {
  const _EmptyExtract({required this.text, required this.kind, this.onManual});

  final StudyText text;
  final StudyMarkKind kind;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running =
        ref.watch(studyAnalysisProvider(text.renditionId))
            is StudyAnalysisRunning;
    if (running) {
      return Text(AppLocalizations.of(context)!.studyExtractRunning);
    }
    return StudySuggestion(
      text: text,
      kind: kind,
      onChosen: (choice) => unawaited(
        applyStudySuggestion(
          ref,
          context,
          text,
          kind,
          choice,
          onManual: onManual,
        ),
      ),
    );
  }
}

/// Lo extraído, con su «Escuchar» y su «Copiar».
class _Extracted extends StatelessWidget {
  const _Extracted({
    required this.copyText,
    required this.listen,
    required this.child,
  });

  final String copyText;
  final Widget listen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        child,
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            children: [
              listen,
              TextButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(l10n.studyCopy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: copyText));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(l10n.studyCopied)));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lo que hace falta para escuchar el texto estudiado (F39): armar lo que se
/// ofrece al lector flotante recién cuando se toca «Escuchar», y no con cada
/// cuadro —el texto de un libro entero se parte en líneas una vez—.
@immutable
class _Listening {
  const _Listening({
    required this.text,
    required this.study,
    required this.title,
    required this.transcript,
  });

  final StudyText text;
  final DocumentStudy study;
  final String title;
  final bool transcript;

  String get documentId => studyReadableId(text.renditionId);

  /// El mismo texto, con los mismos pedazos y posiciones que ofrece el
  /// detalle: lo que suena cae en su lugar. Se parte sin trabar la interfaz:
  /// el texto de un libro entero son segundos en un teléfono.
  Future<ReadableDocument> document() => studyReadableDocumentOff(
    text: text,
    title: title,
    scopes: studyReadScopes(
      sourceKey: text.renditionId,
      content: text.content,
      study: study,
      markdown: text.markdown,
    ),
    transcript: transcript,
  );
}

/// «Escuchar» (F39): lee en voz alta con el lector flotante solo lo de la
/// fila —el texto entero, las oraciones del resumen o de la síntesis, o las
/// palabras clave—. Mientras suena dice «Pausar»; en pausa, vuelve a leer.
class _ListenButton extends ConsumerStatefulWidget {
  const _ListenButton({required this.listening, required this.scope});

  final _Listening listening;
  final ReadScope scope;

  @override
  ConsumerState<_ListenButton> createState() => _ListenButtonState();
}

class _ListenButtonState extends ConsumerState<_ListenButton> {
  /// Mientras se arma lo que se va a leer —el de un libro entero tarda unos
  /// segundos—: el botón espera en vez de dejar tocar de nuevo.
  var _preparing = false;

  Future<void> _open(ReadAloudController controller) async {
    setState(() => _preparing = true);
    try {
      final document = await widget.listening.document();
      if (!mounted) return;
      await controller.open(document, scope: widget.scope);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scope = widget.scope;
    final run = ref.watch(
      readAloudRunProvider((
        documentId: widget.listening.documentId,
        scope: scope,
      )),
    );
    final playing = run == ReadAloudRun.playing;

    return TextButton.icon(
      key: Key('study-listen-${scope.name}'),
      icon: _preparing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              playing ? Icons.pause_outlined : Icons.volume_up_outlined,
              size: 18,
            ),
      label: Text(playing ? l10n.mediaPlayerPause : l10n.studyListen),
      onPressed: _preparing
          ? null
          : () {
              final controller = ref.read(readAloudControllerProvider.notifier);
              unawaited(switch (run) {
                ReadAloudRun.playing => controller.pause(),
                ReadAloudRun.paused => controller.play(),
                ReadAloudRun.none => _open(controller),
              });
            },
    );
  }
}
