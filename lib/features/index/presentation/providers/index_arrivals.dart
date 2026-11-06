import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';

/// Qué llegó al Índice mientras se lo miraba (F46): lo que «aparece en su
/// lugar, con un brillo suave».
///
/// Cada lista que se muestra —los documentos de un tema, todos los
/// documentos, las entradas de uno— le cuenta lo que trae cada vez
/// ([observe]); lo que no estaba la vez anterior de esa misma lista, llegó.
/// La primera vez de una lista no llega nada: es lo que había. Así un tema
/// que se despliega, o uno que entra en la pantalla al desplazarse, no se
/// ilumina entero.
class IndexArrivals {
  IndexArrivals(this._clock);

  final Clock _clock;

  /// Cuánto dura el brillo de lo que llegó.
  static const glow = Duration(milliseconds: 1600);

  final _seen = <String, Set<String>>{};
  final _arrived = <String, DateTime>{};

  /// Lo que trae ahora la lista [list]: lo que no traía antes, llegó.
  void observe(String list, Iterable<String> ids) {
    final now = ids.toSet();
    final before = _seen[list];
    _seen[list] = now;
    if (before == null) return;
    final at = _clock();
    for (final id in now) {
      if (!before.contains(id)) _arrived[id] = at;
    }
    // Lo que ya brilló no se guarda para siempre.
    _arrived.removeWhere((_, when) => at.difference(when) > glow * 4);
  }

  /// Cuándo llegó [id], si fue hace menos que lo que dura el brillo.
  DateTime? freshArrival(String id) {
    final when = _arrived[id];
    if (when == null) return null;
    return _clock().difference(when) <= glow ? when : null;
  }
}

/// La identidad con que se reconoce un documento entre una lectura y otra.
String indexDocumentIdentity(IndexDocument document) => 'doc:${document.id}';

/// La identidad de cada entrada de [entries], en su orden: su documento, su
/// clase, su nivel y su título, y cuántas iguales hubo antes. No es su clave
/// en la base, que cambia cada vez que el documento se vuelve a indexar:
/// corregir una página rehace todas sus filas, y ninguna «llegó».
List<String> indexEntryIdentities(List<IndexEntry> entries) {
  final repeated = <String, int>{};
  return [
    for (final entry in entries)
      () {
        final base = entry.isImage
            ? '${entry.documentId}:img:${entry.imageId}'
            : '${entry.documentId}:${entry.origin.name}:${entry.level}:'
                  '${entry.title}';
        final n = repeated.update(base, (n) => n + 1, ifAbsent: () => 0);
        return '$base#$n';
      }(),
  ];
}

/// Lo que llegó mientras se miraba el Índice. Vive lo que la app: volver a la
/// pantalla no hace llegar otra vez lo que ya estaba.
final indexArrivalsProvider = Provider<IndexArrivals>(
  (ref) => IndexArrivals(ref.watch(clockProvider)),
);
