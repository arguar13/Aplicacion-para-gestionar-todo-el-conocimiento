import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/processed_image_viewer.dart';

/// Lo que se abre al tocar una entrada del Índice (F46): un documento y,
/// si se tocó una, la entrada con su lugar.
///
/// **El enganche del paso 4** («ir al lugar exacto», decisión C) es este: la
/// entrada viaja entera, con su tramo en el texto propio del documento
/// ([IndexEntry.textStart], [IndexEntry.textEnd]), su página del texto y la
/// del PDF. El paso 3 abre el texto en el lector único desde el comienzo
/// ([openIndexEntry] y el panel de al lado); el paso 4 le pasa al lector ese
/// tramo, para que lo muestre y lo resalte un momento, y suma el toque largo
/// («Abrir en el original», «Preguntar al chat», «Copiar el título»,
/// «Renombrar» una imagen) y «Descargar el índice».
@immutable
class IndexOpening {
  const IndexOpening({required this.documentId, this.entry});

  /// Una entrada de su documento.
  IndexOpening.of(IndexEntry entry)
    : documentId = entry.documentId,
      entry = entry;

  final String documentId;

  /// La entrada tocada; `null` es el documento desde el comienzo.
  final IndexEntry? entry;

  @override
  bool operator ==(Object other) =>
      other is IndexOpening &&
      other.documentId == documentId &&
      other.entry == entry;

  @override
  int get hashCode => Object.hash(documentId, entry);

  @override
  String toString() =>
      'IndexOpening($documentId${entry == null ? '' : ', ${entry!.key}'})';
}

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
/// Lo demás, el texto del documento en el lector único: al costado del Índice
/// si la pantalla tiene dos paneles ([IndexBeside]) —lo muestra el de la
/// derecha, que mira [indexSelectionProvider]—, o encima, con «atrás» de
/// vuelta al Índice donde estaba.
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
  ref.read(indexSelectionProvider.notifier).state = opening;
  if (beside) return;
  // El paso 4 suma acá el lugar de [entry] (decisión C).
  unawaited(
    context.push(
      RoutePaths.extractReading(StudyCreationKind.fullText, [
        opening.documentId,
      ]),
    ),
  );
}
