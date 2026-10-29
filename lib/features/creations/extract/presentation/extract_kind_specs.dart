import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/presentation/extract_exporter.dart';
import 'package:sinapsis/features/creations/extract/presentation/widgets/extract_actions.dart';
import 'package:sinapsis/features/creations/extract/presentation/widgets/extract_viewer.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';

/// Cómo es en Repasar cada una de las tres de extraer (F43, paso 7): la de
/// fábrica —su tarjeta y su hoja, solo con «Fuentes»— con su visor vivo
/// ([ExtractViewer]), «Escuchar» y «Lectura» arriba, y su archivo Markdown.
CreationKindSpec extractKindSpec(StudyCreationKind kind) =>
    defaultCreationKindSpec(kind).copyWith(
      viewerBuilder: (context, creation) =>
          ExtractViewer(key: ValueKey(creation.id), creation: creation),
      viewerActions: extractViewerActions,
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
