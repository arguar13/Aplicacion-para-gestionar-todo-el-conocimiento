import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_generator.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_json.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_exporter.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_scene.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_viewer.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Quien genera los mapas mentales: lo que suma `creationGeneratorsProvider`.
final mindMapGeneratorProvider = Provider<CreationGenerator>(
  (ref) => const MindMapGenerator(),
);

/// El mapa mental en Repasar (F43, paso 9): la tarjeta y la hoja de fábrica
/// —Idioma, Fuentes y Tema—, su visor, su botón de guardarlo como imagen y
/// el PNG de «Descargar». Lo que suma `creationKindSpecsProvider`.
final mindMapKindSpecProvider = Provider<CreationKindSpec>(
  (ref) => mindMapKindSpec(),
);

/// Lo de [mindMapKindSpecProvider], suelto: lo que usan las pruebas.
CreationKindSpec mindMapKindSpec() =>
    defaultCreationKindSpec(StudyCreationKind.mindMap).copyWith(
      // Unas cincuenta ideas con su nota, su fuente y su pasaje.
      expectedOutputTokens: (_) => 2800,
      viewerBuilder: (context, creation) =>
          MindMapViewer(key: ValueKey(creation.id), creation: creation),
      viewerActions: mindMapViewerActions,
      exporter: exportMindMap,
    );

/// El PNG de [creation], con los colores del tema de ahora; `null` si el mapa
/// no tiene ideas.
Future<CreationExportFile?> exportMindMap(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final map = MindMapJson.decode(creation.decodedContent);
  if (map.root.label.isEmpty) return null;
  final l10n = AppLocalizations.of(context)!;
  final palette = MindMapPalette.of(
    Theme.of(context),
    mindMapAccent.of(context),
  );
  final metrics = MindMapMetrics.of(
    context,
    interactive: false,
    textScaler: TextScaler.noScaling,
  );
  final bytes = await const MindMapExporter().toPng(
    map: map,
    palette: palette,
    metrics: metrics,
  );
  return CreationExportFile(
    fileName: '${sanitizeFileName(studyCreationTitle(l10n, creation))}.png',
    bytes: bytes,
    mimeType: 'image/png',
  );
}
