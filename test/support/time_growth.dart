import 'dart:async';
import 'dart:math' as math;

/// Cuánto crece el tiempo de [big] respecto del de [small] (el cociente), para
/// probar que un trabajo no depende —o depende solo en línea recta— del tamaño
/// del texto sin fijar cuánto tarda en milisegundos: con la máquina cargada los
/// dos tamaños se frenan juntos, y el cociente casi no se mueve.
///
/// Cada uno devuelve los microsegundos que tardó. Se toma lo mejor de [rounds]
/// vueltas, intercaladas —un tirón de la máquina no cae siempre sobre el mismo
/// tamaño—, después de una vuelta de calentamiento. [floor] son los
/// microsegundos que se suman a los dos: un trabajo que no tarda nada no da un
/// cociente enorme por una diferencia de unos pocos microsegundos.
///
/// Con cuatro veces más texto, un trabajo lineal da cerca de 4, uno cuadrático
/// cerca de 16 y uno que mira solo el comienzo, cerca de 1.
Future<double> timeGrowth(
  Future<int> Function() small,
  Future<int> Function() big, {
  int rounds = 3,
  int floor = 2000,
}) async {
  await small();
  await big();
  var bestSmall = await small();
  var bestBig = await big();
  for (var i = 1; i < rounds; i++) {
    bestSmall = math.min(bestSmall, await small());
    bestBig = math.min(bestBig, await big());
  }
  return (bestBig + floor) / (bestSmall + floor);
}

/// Qué parte del tiempo de [work] el hilo principal estuvo sin poder atender
/// nada: el mayor hueco entre dos ticks de un temporizador, sobre lo que tardó
/// en total. Cerca de 1 si [work] corre en el hilo y lo traba entero; una
/// fracción chica si corre en otro. Es un cociente: la máquina cargada frena
/// los dos números juntos.
Future<double> stallShare(Future<void> Function() work) async {
  var last = Stopwatch()..start();
  var longest = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
    longest = math.max(longest, last.elapsedMicroseconds);
    last = Stopwatch()..start();
  });
  final total = Stopwatch()..start();
  await work();
  final took = total.elapsedMicroseconds;
  // Un tick más, para que registre el hueco de un trabajo que no soltó el hilo.
  await Future<void>.delayed(const Duration(milliseconds: 6));
  timer.cancel();
  return longest / math.max(took, 1);
}

/// Los microsegundos que tarda [work].
Future<int> micros(FutureOr<void> Function() work) async {
  final watch = Stopwatch()..start();
  await work();
  return watch.elapsedMicroseconds;
}
