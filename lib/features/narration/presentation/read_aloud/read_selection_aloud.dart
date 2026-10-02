import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';

/// Cuántas veces se pidió leer una selección: cada pedido es un documento
/// nuevo para el lector —ver [ReadAloudController.open]—, aunque se repita
/// la misma selección, para que vuelva a empezar en vez de solo abrirse.
var _requests = 0;

/// "Leer en voz alta", del menú de selección de texto: el lector flotante
/// lee lo seleccionado y se detiene ahí (F25).
///
/// Si lo seleccionado es parte del texto que la pantalla ofrece para leer
/// —[sourceKey] es el de ese texto y [start]–[end] son posiciones en él,
/// tal cual se guarda—, se leen las líneas que toca la selección, con el
/// resaltado amarillo de siempre: las mismas líneas que leería el botón
/// flotante, sin las marcas de tiempo ni los símbolos de formato. Si no —un
/// texto que no se ofrece para leer—, se lee [text] tal cual, sin resaltar.
Future<void> readSelectionAloud(
  WidgetRef ref, {
  required String text,
  String? sourceKey,
  int? start,
  int? end,
}) {
  final controller = ref.read(readAloudControllerProvider.notifier);
  final request = ++_requests;
  final offered = ref.read(currentReadableProvider);

  if (offered != null && sourceKey != null && start != null && end != null) {
    final touched = [
      for (final segment in offered.segments)
        if (segment.sourceKey == sourceKey &&
            segment.start < end &&
            segment.end > start)
          segment,
    ];
    if (touched.isNotEmpty) {
      return controller.open(
        ReadableDocument(
          id: '${offered.id}#selección-$request',
          title: offered.title,
          segments: touched,
        ),
      );
    }
  }

  return controller.open(
    // Sin un texto ofrecido no hay título: el comienzo de lo seleccionado
    // dice qué se está leyendo.
    documentFrom('selección-$request', offered?.title ?? _excerpt(text), [
      (
        sourceKey: 'selección-$request',
        text: text,
        markdown: false,
        transcript: false,
      ),
    ]),
  );
}

String _excerpt(String text) {
  final oneLine = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return oneLine.length <= 60 ? oneLine : '${oneLine.substring(0, 59)}…';
}
