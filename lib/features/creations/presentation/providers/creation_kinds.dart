import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/data/services/system_creation_sharer.dart';
import 'package:sinapsis/features/creations/data_table/data_table_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/presentation/extract_kind_specs.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/flashcards_kind.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_kind_spec.dart';
import 'package:sinapsis/features/creations/mind_map/mind_map_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/presentation_kind_spec.dart';
import 'package:sinapsis/features/creations/quiz/presentation/quiz_kind.dart';
import 'package:sinapsis/features/creations/report/presentation/report_kind.dart';

/// Los tipos de creación de Repasar (F43, ola 3): **uno por tipo, y sumar uno
/// es una línea acá**, con el proveedor que arma el suyo en la carpeta de su
/// tipo (`lib/features/creations/<tipo>/`):
///
/// ```dart
/// final creationKindSpecsProvider = Provider<List<CreationKindSpec>>(
///   (ref) => [
///     ref.watch(mindMapKindSpecProvider),
///   ],
/// );
/// ```
///
/// Un tipo que no está acá usa el de fábrica (`defaultCreationKindSpec`): su
/// tarjeta y su hoja ya funcionan, y su visor dice «en camino». Es la pareja
/// de `creationGeneratorsProvider`, que suma lo que lo genera.
final creationKindSpecsProvider = Provider<List<CreationKindSpec>>(
  (ref) => [
    ref.watch(fullTextKindSpecProvider),
    ref.watch(summaryKindSpecProvider),
    ref.watch(synthesisKindSpecProvider),
    ref.watch(infographicKindSpecProvider),
    ref.watch(reportKindSpecProvider),
    ref.watch(mindMapKindSpecProvider),
    ref.watch(dataTableKindSpecProvider),
    ref.watch(flashcardsKindSpecProvider),
    ref.watch(quizKindSpecProvider),
    ref.watch(presentationKindSpecProvider),
  ],
);

/// Los tipos, ya con el de fábrica donde no hay otro: lo que leen la grilla,
/// la hoja, «Lo creado» y el visor. Dos para el mismo tipo es un error de
/// armado, y se dice en el acto.
final creationKindRegistryProvider = Provider<CreationKindRegistry>(
  (ref) => CreationKindRegistry(ref.watch(creationKindSpecsProvider)),
);

/// Cómo es cada tipo de creación: el registrado o el de fábrica.
class CreationKindRegistry {
  CreationKindRegistry(List<CreationKindSpec> registered)
    : _registered = _index(registered);

  final Map<StudyCreationKind, CreationKindSpec> _registered;

  static Map<StudyCreationKind, CreationKindSpec> _index(
    List<CreationKindSpec> specs,
  ) {
    final index = <StudyCreationKind, CreationKindSpec>{};
    for (final spec in specs) {
      if (index.containsKey(spec.kind)) {
        throw StateError('Dos tipos registrados para ${spec.kind.storageKey}.');
      }
      index[spec.kind] = spec;
    }
    return Map.unmodifiable(index);
  }

  /// El de [kind].
  CreationKindSpec of(StudyCreationKind kind) =>
      _registered[kind] ?? defaultCreationKindSpec(kind);

  /// Todos, en el orden de la grilla (el de `StudyCreationKind`).
  List<CreationKindSpec> get all => [
    for (final kind in StudyCreationKind.values) of(kind),
  ];

  /// Si [kind] ya tiene su visor.
  bool hasViewer(StudyCreationKind kind) => of(kind).viewerBuilder != null;
}

/// Quien pasa el archivo de una creación a otra app («Compartir»): la hoja
/// de compartir del sistema. [origin] es de dónde sale la hoja en un iPad o
/// una Mac.
typedef CreationSharer =
    Future<void> Function(
      CreationExportFile file, {
      required String title,
      Rect? origin,
    });

/// El que comparte —la hoja del sistema, con `share_plus`—, o `null` donde
/// esa hoja no acepta archivos (Linux): ahí «Compartir» no se ofrece y
/// «Descargar» sí, con el selector de archivos de siempre. Aparece en el
/// menú de cada creación que exporta.
final creationSharerProvider = Provider<CreationSharer?>(
  (ref) => systemShareSupportsFiles() ? SystemCreationSharer().call : null,
);
