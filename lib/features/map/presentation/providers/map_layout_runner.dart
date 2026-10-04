import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/map/domain/services/map_layout.dart';

/// Lo que hace falta para acomodar una escena con el layout de fuerzas: solo
/// números y listas, que cruzan sin problema a otro isolate.
typedef MapLayoutJob = ({
  int count,
  List<MapLayoutLink> links,
  Int32List? groups,
  Float64List? startX,
  Float64List? startY,
  int iterations,
  // El tamaño de la caja de cada nodo, con su etiqueta: lo que el layout
  // separa para que no se pisen.
  Float64List widths,
  Float64List heights,
});

/// Cómo se acomoda una escena. Se inyecta para que las pruebas la calculen sin
/// isolate; en la app es [runLayoutInIsolate].
typedef MapLayoutRunner = Future<MapLayout> Function(MapLayoutJob job);

/// Con menos nodos que estos, acomodar cuesta menos que lanzar un isolate.
const kInlineLayoutNodes = 40;

/// El layout de [job], en el isolate de quien lo llama.
MapLayout runLayout(MapLayoutJob job) => layoutReadable(
  count: job.count,
  links: job.links,
  groups: job.groups,
  startX: job.startX,
  startY: job.startY,
  iterations: job.iterations,
  widths: job.widths,
  heights: job.heights,
);

/// [runLayout] fuera del isolate de la interfaz: el layout cuesta el cuadrado
/// de los nodos, y con unos cientos son decenas de milisegundos que serían
/// cuadros perdidos. Las escenas chicas se acomodan en el propio isolate.
Future<MapLayout> runLayoutInIsolate(MapLayoutJob job) async {
  if (job.count < kInlineLayoutNodes) return runLayout(job);
  return Isolate.run(() => runLayout(job));
}

/// El acomodador de escenas que usa la pantalla.
final mapLayoutRunnerProvider = Provider<MapLayoutRunner>(
  (ref) => runLayoutInIsolate,
);
