import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_options.dart';
import 'package:sinapsis/features/export/domain/services/document_marks_builder.dart';
import 'package:sinapsis/features/export/domain/usecases/download_marked_document_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/marked_download_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_keywords_fill_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la hoja para descargar el original con lo estudiado y lo subrayado
/// marcado, en [format] (F38).
Future<void> showStudyDownloadSheet(
  BuildContext context, {
  required KnowledgeItem item,
  required StudyText text,
  required MarkedDocumentFormat format,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) =>
        StudyDownloadSheet(item: item, text: text, format: format),
  );
}

/// La hoja de «Descargar» (F38): las cuatro cosas que se pueden marcar —se
/// combinan—, apagadas las que no tienen nada para marcar, y «Guardar».
///
/// Mientras arma el archivo muestra una barra, y al terminar dice qué pasó
/// sin cerrarse: si se guardó, si se canceló o por qué falló, para poder
/// descargar otra combinación enseguida.
class StudyDownloadSheet extends ConsumerStatefulWidget {
  const StudyDownloadSheet({
    required this.item,
    required this.text,
    required this.format,
    super.key,
  });

  final KnowledgeItem item;
  final StudyText text;
  final MarkedDocumentFormat format;

  @override
  ConsumerState<StudyDownloadSheet> createState() => _StudyDownloadSheetState();
}

class _StudyDownloadSheetState extends ConsumerState<StudyDownloadSheet> {
  late MarkedDocumentOptions _chosen;
  bool _working = false;

  /// Lo que pasó con la última descarga, ya dicho para la persona.
  String? _result;
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    // Se arranca con lo que ya se ve resaltado en el original: lo más
    // probable es que quiera llevarse eso.
    final view = ref.read(studyViewProvider(widget.text.renditionId));
    _chosen = MarkedDocumentOptions(
      summary: view.summary,
      synthesis: view.synthesis,
      keywords: view.keywords,
    );
    // Lo que se descarga con las palabras clave las lleva en todas las
    // oraciones, también si se analizó antes de que el análisis lo asegurara.
    unawaited(ensureStudyKeywords(ref, widget.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final renditionId = widget.text.renditionId;
    final study =
        ref.watch(documentStudyProvider(renditionId)).valueOrNull ??
        DocumentStudy.notStarted;
    final highlights =
        ref.watch(renditionHighlightsProvider(renditionId)).valueOrNull ??
        const [];
    final available = availableMarkedOptions(
      content: widget.text.content,
      study: study,
      highlights: highlights,
    );
    // Lo elegido que ya no tiene nada para marcar —se borró el último
    // subrayado— no cuenta.
    final chosen = _chosen.intersect(available);

    Widget option({
      required Key key,
      required String title,
      required String missing,
      required bool has,
      required bool value,
      required MarkedDocumentOptions Function({required bool on}) change,
    }) => CheckboxListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(title),
      subtitle: has ? null : Text(missing),
      value: has && value,
      onChanged: has && !_working
          ? (on) => setState(() => _chosen = change(on: on ?? false))
          : null,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          key: const Key('study-download-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.studyDownloadTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              l10n.studyDownloadBody(
                l10n.studyDownloadFormat(widget.format.name),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            option(
              key: const Key('study-download-summary'),
              title: l10n.studyDownloadSummary,
              missing: l10n.studyDownloadNoSummary,
              has: available.summary,
              value: chosen.summary,
              change: ({required on}) => _chosen.copyWith(summary: on),
            ),
            option(
              key: const Key('study-download-synthesis'),
              title: l10n.studyDownloadSynthesis,
              missing: l10n.studyDownloadNoSynthesis,
              has: available.synthesis,
              value: chosen.synthesis,
              change: ({required on}) => _chosen.copyWith(synthesis: on),
            ),
            option(
              key: const Key('study-download-keywords'),
              title: l10n.studyDownloadKeywords,
              missing: l10n.studyDownloadNoKeywords,
              has: available.keywords,
              value: chosen.keywords,
              change: ({required on}) => _chosen.copyWith(keywords: on),
            ),
            option(
              key: const Key('study-download-mine'),
              title: l10n.studyDownloadMine,
              missing: l10n.studyDownloadNoMine,
              has: available.myHighlights,
              value: chosen.myHighlights,
              change: ({required on}) => _chosen.copyWith(myHighlights: on),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _working
                  ? Padding(
                      key: const Key('study-download-progress'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.studyDownloadWorking,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: const LinearProgressIndicator(minHeight: 6),
                          ),
                        ],
                      ),
                    )
                  : _result == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _result!,
                        key: const Key('study-download-result'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _resultIsError
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('study-download-save'),
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.studyDownloadSave),
              onPressed: chosen.isEmpty || _working
                  ? null
                  : () => _save(chosen, study, highlights),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(
    MarkedDocumentOptions options,
    DocumentStudy study,
    List<Highlight> highlights,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final download = ref.read(downloadMarkedDocumentUseCaseProvider);
    setState(() {
      _working = true;
      _result = null;
    });

    final result = await download(
      DownloadMarkedDocumentParams(
        item: widget.item,
        content: widget.text.content,
        study: study,
        highlights: highlights,
        options: options,
      ),
    );
    if (!mounted) return;

    setState(() {
      _working = false;
      _resultIsError = result.isLeft();
      _result = result.match(
        (failure) => _errorMessage(l10n, failure.error),
        (done) => done.path != null || kIsWeb
            ? l10n.studyDownloadSaved(done.fileName)
            : l10n.studyDownloadCancelled,
      );
    });
  }

  String _errorMessage(
    AppLocalizations l10n,
    MarkedDownloadError error,
  ) => switch (error) {
    MarkedDownloadError.nothingSelected =>
      l10n.studyDownloadErrorNothingSelected,
    MarkedDownloadError.nothingToMark => l10n.studyDownloadErrorNothingToMark,
    MarkedDownloadError.originalMissing =>
      l10n.studyDownloadErrorOriginalMissing,
    MarkedDownloadError.unsupportedFormat => l10n.studyDownloadErrorUnsupported,
    MarkedDownloadError.writeFailed => l10n.studyDownloadErrorWrite,
    MarkedDownloadError.saveFailed => l10n.studyDownloadErrorSave,
  };
}
