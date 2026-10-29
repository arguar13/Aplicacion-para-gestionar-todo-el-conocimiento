import 'package:sinapsis/features/creations/report/domain/report.dart';

/// Las opciones de [question] en el orden en que se muestran: mezcladas,
/// porque la IA suele escribir la correcta primero y mostrarlas tal cual
/// volvería trivial la pregunta (lo mismo que hace el quiz de F20).
///
/// La mezcla es **fija**: sale del texto de la pregunta, no del azar. El
/// visor, el PDF y el Markdown muestran el mismo orden —la «B» del papel es
/// la «B» de la pantalla— y volver a abrir el informe no lo cambia.
List<ReportOption> reportOptionOrder(ReportQuestion question) {
  final order = List.of(question.options);
  var state = _seedOf(question.question);
  for (var i = order.length - 1; i > 0; i--) {
    // El generador «estándar mínimo» de Park y Miller: el mismo en cualquier
    // plataforma —sus cuentas no pasan de 2^53—, a diferencia de `Random` o
    // de `String.hashCode`.
    state = state * 48271 % _modulus;
    final j = state % (i + 1);
    final swap = order[i];
    order[i] = order[j];
    order[j] = swap;
  }
  return order;
}

/// La letra de la opción [index] (desde 0): A, B, C…
String reportOptionLetter(int index) => String.fromCharCode(0x41 + index);

const _modulus = 2147483647;

/// Una semilla de 1 a 2^31 − 2 sacada de [text].
int _seedOf(String text) {
  var hash = 7;
  for (final unit in text.codeUnits) {
    hash = (hash * 31 + unit) % _modulus;
  }
  return hash == 0 ? 1 : hash;
}
