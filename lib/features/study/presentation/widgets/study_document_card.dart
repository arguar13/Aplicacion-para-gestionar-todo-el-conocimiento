import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_extracts.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La tarjeta «Estudiar el documento» del detalle (F36): entre el original y
/// lo demás, en un documento o una página web.
///
/// - **Arriba, los tres botones** —ver [StudyToggles]— y una leyenda chica
///   con sus colores. Lo que prenden se resalta en el original, en «Leer como
///   libro» y en el texto extraído.
/// - **Mientras analiza**, una franja con la parte que va, su barra y
///   «Parar». Si se corta o una parte no se pudo leer, lo dice ahí mismo.
/// - **Abajo, «Extraer»**: el texto extraído —en un documento, si viene
///   [extractedText]—, el resumen, la síntesis y las palabras clave, cada uno
///   plegado, con cuánto tiene y «Copiar».
/// - En su menú, **«Volver a analizar»**, que pregunta antes: reemplaza
///   también las palabras elegidas a mano.
class StudyDocumentCard extends ConsumerWidget {
  const StudyDocumentCard({
    required this.text,
    this.webPage = false,
    this.extractedText,
    this.extractedTextSubtitle,
    super.key,
  });

  final StudyText text;

  /// Si es una página web: cambia solo el título.
  final bool webPage;

  /// El texto extraído, armado recién al desplegar su fila: el de un libro
  /// entero no se arma si nadie lo abre. Sin él, no hay fila de texto.
  final WidgetBuilder? extractedText;

  /// Para qué está el texto extraído, debajo de su fila.
  final String? extractedTextSubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final study =
        ref.watch(documentStudyProvider(text.renditionId)).valueOrNull ??
        DocumentStudy.notStarted;

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
                  child: Text(
                    webPage ? l10n.studyCardTitleWebPage : l10n.studyCardTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _StudyMenu(text: text),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  StudyToggles(text: text),
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
                title: l10n.studyExtractText,
                subtitle: extractedTextSubtitle,
                child: Builder(builder: builder),
              ),
            _SentencesRow(
              key: const Key('study-extract-summary'),
              title: l10n.studyExtractSummary,
              color: StudyPalette.of(theme.brightness).summary,
              content: text.content,
              study: study,
              kind: StudyMarkKind.summary,
            ),
            _SentencesRow(
              key: const Key('study-extract-synthesis'),
              title: l10n.studyExtractSynthesis,
              color: StudyPalette.of(theme.brightness).synthesis,
              content: text.content,
              study: study,
              kind: StudyMarkKind.synthesis,
            ),
            _KeywordsRow(content: text.content, study: study),
          ],
        ),
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
      StudyAnalysisRunning(:final progress) => _Strip(
        key: const Key('study-progress'),
        message: progress == null
            ? l10n.studyPreparing
            : l10n.studyAnalyzing(
                (progress.partsDone + 1).clamp(1, progress.partsTotal),
                progress.partsTotal,
              ),
        running: true,
        progress: progress == null || progress.partsTotal == 0
            ? null
            : progress.partsDone / progress.partsTotal,
        action: l10n.studyStop,
        onAction: notifier.stop,
      ),
      StudyAnalysisDone(:final unreadParts) => _Strip(
        key: const Key('study-unread'),
        message: l10n.studyUnreadParts(unreadParts),
        action: l10n.studyUnreadAcknowledge,
        onAction: notifier.acknowledge,
      ),
      StudyAnalysisFailed() => _Strip(
        key: const Key('study-failed'),
        message: l10n.studyFailed,
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
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      enabled: enabled,
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
/// texto corrido, con cuántas oraciones y palabras son.
class _SentencesRow extends StatelessWidget {
  const _SentencesRow({
    required this.title,
    required this.color,
    required this.content,
    required this.study,
    required this.kind,
    super.key,
  });

  final String title;
  final Color color;
  final String content;
  final DocumentStudy study;
  final StudyMarkKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final extract = studySentencesExtract(content, study, kind);
    final has = extract.sentences > 0;

    return _ExtractRow(
      icon: Icons.format_color_fill_outlined,
      iconColor: color,
      title: title,
      subtitle: has
          ? '${l10n.studySentenceCount(extract.sentences)} · '
                '${l10n.studyWordCount(extract.words)}'
          : _emptyHint(l10n, study),
      enabled: has,
      child: _Extracted(
        copyText: extract.text,
        child: SelectableText(extract.text),
      ),
    );
  }
}

/// «Extraer palabras clave»: como etiquetas, en el orden en que aparecen.
class _KeywordsRow extends StatelessWidget {
  const _KeywordsRow({required this.content, required this.study});

  final String content;
  final DocumentStudy study;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = StudyPalette.of(Theme.of(context).brightness);
    final words = studyKeywordsExtract(content, study);

    return _ExtractRow(
      key: const Key('study-extract-keywords'),
      icon: Icons.key_outlined,
      iconColor: palette.keyword,
      title: l10n.studyExtractKeywords,
      subtitle: words.isNotEmpty
          ? l10n.studyKeywordCount(words.length)
          : _emptyHint(l10n, study),
      enabled: words.isNotEmpty,
      child: _Extracted(
        copyText: words.join(', '),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final word in words)
              Chip(
                label: Text(word),
                labelStyle: const TextStyle(color: StudyPalette.ink),
                backgroundColor: palette.keyword,
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

/// Lo extraído y su «Copiar».
class _Extracted extends StatelessWidget {
  const _Extracted({required this.copyText, required this.child});

  final String copyText;
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
          child: TextButton.icon(
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
        ),
      ],
    );
  }
}
