import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_markdown.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_text.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El archivo de una extracción (F43, paso 7), para «Descargar» y
/// «Compartir»: un **Markdown** con el título, un apartado por documento y lo
/// extraído —el texto entero, o las oraciones en párrafos—, con las palabras
/// clave en **negrita** si se resaltan (`extractMarkdown`). Se abre en
/// cualquier editor y en Obsidian, y se lee bien como texto.
///
/// Como el visor, se arma en el momento con lo que el documento tiene hoy
/// (decisión E): lo que se descarga es lo que se ve.
Future<CreationExportFile?> exportExtract(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final processed = ref.read(processedRepositoryProvider);
  final studies = ref.read(studyRepositoryProvider);
  final needs = extractNeeds(creation.kind);
  final sections = <ExtractExportSection>[];
  for (final id in creation.sourceIds) {
    final document = await processed.watchDocument(id).first;
    if (document == null || document.inTrash) {
      sections.add(ExtractExportSection(title: l10n.f43StudioSourceDeleted));
      continue;
    }
    final own = (await processed.studyTextOf(id)).getRight().toNullable();
    if (own == null) {
      sections.add(
        ExtractExportSection(title: document.title, note: l10n.f43TextNoText),
      );
      continue;
    }
    final study = await studies.read(own.key);
    sections.add(
      ExtractExportSection(
        title: document.title,
        content: own.content,
        markdown: own.markdown,
        study: study,
        keywordsShown: ref.read(processedKeywordsShownProvider(id)),
        note: study.of(needs).isEmpty && needs != StudyMarkKind.keyword
            ? _missing(l10n, needs)
            : null,
      ),
    );
  }
  final title = studyCreationTitle(l10n, creation);
  final markdown = extractMarkdown(
    title: title,
    kind: creation.kind,
    sections: sections,
  );
  return CreationExportFile(
    fileName: '${sanitizeFileName(title)}.md',
    bytes: utf8.encode(markdown),
    mimeType: 'text/markdown',
  );
}

String _missing(AppLocalizations l10n, StudyMarkKind kind) => switch (kind) {
  StudyMarkKind.summary => l10n.f43TextMissingSummary,
  StudyMarkKind.synthesis => l10n.f43TextMissingSynthesis,
  StudyMarkKind.keyword => l10n.f43TextMissingKeywords,
};
