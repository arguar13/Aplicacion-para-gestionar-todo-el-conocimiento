import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_place.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/processed_image_viewer.dart';

/// Lo que se abre al tocar una entrada del Índice (F46): un documento y,
/// si se tocó una, la entrada con su lugar.
///
/// **Ir al lugar exacto** (paso 4, decisión C): la entrada viaja entera, con
/// su tramo en el texto propio del documento ([IndexEntry.textStart],
/// [IndexEntry.textEnd]); el lector único va justo ahí y lo resalta un
/// momento ([place]).
@immutable
class IndexOpening {
  const IndexOpening({required this.documentId, this.entry, this.visit = 0});

  /// Una entrada de su documento.
  IndexOpening.of(IndexEntry entry)
    : documentId = entry.documentId,
      entry = entry,
      visit = 0;

  final String documentId;

  /// La entrada tocada; `null` es el documento desde el comienzo.
  final IndexEntry? entry;

  /// Qué toque es: cada uno, el suyo ([openIndexEntry]). Al costado, el lector
  /// ya está abierto, y tocar otra vez el mismo capítulo vuelve a llevar ahí.
  final int visit;

  /// Adónde va el lector: el título de un capítulo ubicado en el texto. Nada
  /// en «Texto completo» —es el texto entero, desde el comienzo—, en una
  /// imagen —se abre en su galería— ni en un marcador que no se pudo ubicar
  /// en el texto: ese abre el texto desde el comienzo.
  ExtractPlace? get place {
    final entry = this.entry;
    if (entry == null || entry.isImage || entry.isWholeText) return null;
    final (start, end) = (entry.textStart, entry.textEnd);
    if (start == null || end == null || end <= start) return null;
    return ExtractPlace(
      documentId: documentId,
      start: start,
      end: end,
      visit: visit,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IndexOpening &&
      other.documentId == documentId &&
      other.entry == entry &&
      other.visit == visit;

  @override
  int get hashCode => Object.hash(documentId, entry, visit);

  @override
  String toString() =>
      'IndexOpening($documentId${entry == null ? '' : ', ${entry!.key}'}'
      ' #$visit)';
}

/// Cuántas veces se abrió algo desde el Índice: el [IndexOpening.visit] de
/// cada toque.
var _visits = 0;

/// Lo abierto al costado del Índice en una pantalla ancha, y lo último que se
/// abrió en una angosta: su fila queda marcada, así «atrás» vuelve a donde
/// se estaba. `null` es nada.
final indexSelectionProvider = StateProvider<IndexOpening?>((ref) => null);

/// Si el Índice tiene el documento al costado —una pantalla ancha, con dos
/// paneles—: lo que se abre va ahí y no encima. Lo pone la pantalla.
class IndexBeside extends InheritedWidget {
  const IndexBeside({required this.beside, required super.child, super.key});

  final bool beside;

  /// El de arriba; fuera del Índice, ninguno: se abre encima. Se lee al
  /// tocar, no al dibujar: no hace falta volver a dibujar nada si cambia.
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<IndexBeside>()?.beside ?? false;

  @override
  bool updateShouldNotify(IndexBeside oldWidget) => oldWidget.beside != beside;
}

/// Abre [opening]. Una imagen, en su galería a pantalla completa, en su lugar.
/// Lo demás, el texto del documento en el lector único, justo en el título de
/// la entrada ([IndexOpening.place]), que se resalta un momento: al costado
/// del Índice si la pantalla tiene dos paneles ([IndexBeside]) —lo muestra el
/// de la derecha, que mira [indexSelectionProvider]—, o encima, con «atrás»
/// de vuelta al Índice donde estaba —lo desplegado y la posición son del
/// Índice, que sigue debajo—.
void openIndexEntry(BuildContext context, WidgetRef ref, IndexOpening opening) {
  final beside = IndexBeside.of(context);
  final entry = opening.entry;
  if (entry != null && entry.isImage) {
    // Su lugar en la galería es su posición: las imágenes de un documento se
    // numeran sin huecos, y la galería también tiene las que el relleno
    // todavía no tituló.
    unawaited(
      openProcessedImageViewer(
        context,
        documentId: entry.documentId,
        initialIndex: entry.position,
      ),
    );
    return;
  }
  final visited = IndexOpening(
    documentId: opening.documentId,
    entry: entry,
    visit: ++_visits,
  );
  ref.read(indexSelectionProvider.notifier).state = visited;
  if (beside) return;
  unawaited(
    context.push(
      RoutePaths.extractReading(StudyCreationKind.fullText, [
        opening.documentId,
      ], at: visited.place),
    ),
  );
}
