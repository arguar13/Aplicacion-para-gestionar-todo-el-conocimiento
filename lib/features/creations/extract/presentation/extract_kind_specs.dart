import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/presentation/extract_exporter.dart';
import 'package:sinapsis/features/creations/extract/presentation/providers/extract_providers.dart';
import 'package:sinapsis/features/creations/extract/presentation/widgets/extract_study_chips.dart';
import 'package:sinapsis/features/creations/extract/presentation/widgets/extract_viewer.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo es en Repasar cada una de las tres de extraer (F43, paso 7): la de
/// fábrica —su tarjeta y su hoja, solo con «Fuentes»— con su visor vivo
/// ([ExtractViewer]) en **el marco de lectura** (F47, paso 1): las fichas de
/// estudiar en la fila de IA, «Escuchar» y su reproductor abajo, y la letra en
/// «Apariencia». Se descarga como Markdown.
CreationKindSpec extractKindSpec(StudyCreationKind kind) =>
    defaultCreationKindSpec(kind).copyWith(
      viewerBuilder: (context, creation) => ExtractViewer(
        key: ValueKey(creation.id),
        read: ExtractRead.ofCreation(creation),
        title: studyCreationTitle(AppLocalizations.of(context)!, creation),
      ),
      reader: CreationReaderSpec(
        bodyShowsTitle: true,
        aiRow: (context, creation, trailing) => ExtractStudyChips(
          read: ExtractRead.ofCreation(creation),
          trailing: trailing,
        ),
        ownPlayer: (context, creation) => ExtractPlayer(
          read: ExtractRead.ofCreation(creation),
          title: studyCreationTitle(AppLocalizations.of(context)!, creation),
        ),
        ownReadableId: (creation) => extractReadableId(creation.id),
      ),
      exporter: exportExtract,
    );

/// «Extraer texto completo».
final fullTextKindSpecProvider = Provider<CreationKindSpec>(
  (ref) => extractKindSpec(StudyCreationKind.fullText),
);

/// «Extraer resumen».
final summaryKindSpecProvider = Provider<CreationKindSpec>(
  (ref) => extractKindSpec(StudyCreationKind.summary),
);

/// «Extraer síntesis».
final synthesisKindSpecProvider = Provider<CreationKindSpec>(
  (ref) => extractKindSpec(StudyCreationKind.synthesis),
);
