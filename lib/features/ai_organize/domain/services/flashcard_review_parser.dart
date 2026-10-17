import 'package:sinapsis/features/ai_organize/domain/services/flashcard_reviewer.dart';

final _header = RegExp(
  r'^TARJETA\s*(\d+)\s*[:\-–]\s*(bien|corregir|sacar)\b',
  caseSensitive: false,
);
final _question = RegExp(r'^P\s*:\s*(.+)$', caseSensitive: false);
final _answer = RegExp(r'^R\s*:\s*(.+)$', caseSensitive: false);
final _reason = RegExp(
  r'^(?:POR\s*QU[ÉE]|MOTIVO)\s*:\s*(.+)$',
  caseSensitive: false,
);

/// Lo que el modelo agrega por costumbre aunque se le pida que no: negritas,
/// viñetas, numeración.
final _decoration = RegExp(r'^[\s*_#>\-•]+|[\s*_]+$');

/// Lee la respuesta del revisor de tarjetas (F33) sobre las de [originals],
/// en ese orden.
///
/// Función pura, como `parseFlashcardDrafts`: lo único que puede fallar acá
/// es el formato de un texto, y se prueba sin modelo. El formato pedido es,
/// por cada tarjeta, un encabezado `TARJETA <n>: bien | corregir | sacar`;
/// una corrección sigue con `P:`, `R:` y `POR QUÉ:`, y una que se saca, con
/// `POR QUÉ:`.
///
/// **Lo que no se entiende no se propone** —sería cambiar algo de la persona
/// por un malentendido—, así que es estricto donde importa y tolerante en lo
/// demás:
///
/// - se ignoran las líneas sueltas, las negritas y las viñetas;
/// - un veredicto sin su `POR QUÉ:`, una corrección sin pregunta o sin
///   respuesta, o un número fuera de la lista, se descartan;
/// - si una tarjeta aparece dos veces, vale la primera;
/// - una «corrección» que deja la tarjeta igual a [originals] —sin contar
///   mayúsculas ni espacios— no es una corrección.
List<FlashcardVerdict> parseFlashcardReview(
  String raw, {
  required List<({String front, String back})> originals,
}) {
  final verdicts = <FlashcardVerdict>[];
  final seen = <int>{};
  _Open? open;

  void close() {
    final current = open;
    open = null;
    if (current == null) return;
    final verdict = current.verdict(originals);
    if (verdict != null && seen.add(verdict.index)) verdicts.add(verdict);
  }

  for (final rawLine in raw.split('\n')) {
    final line = rawLine.replaceAll(_decoration, '').trim();
    if (line.isEmpty) continue;

    final header = _header.firstMatch(line);
    if (header != null) {
      close();
      final index = int.parse(header.group(1)!) - 1;
      final kind = header.group(2)!.toLowerCase();
      if (index < 0 || index >= originals.length || kind == 'bien') continue;
      open = _Open(index: index, removes: kind == 'sacar');
      continue;
    }

    final current = open;
    if (current == null) continue;
    if (_question.firstMatch(line) case final match?) {
      current.front ??= match.group(1)!.trim();
    } else if (_answer.firstMatch(line) case final match?) {
      current.back ??= match.group(1)!.trim();
    } else if (_reason.firstMatch(line) case final match?) {
      current.reason ??= match.group(1)!.trim();
    }
  }
  close();
  return verdicts;
}

/// El veredicto que se está leyendo.
class _Open {
  _Open({required this.index, required this.removes});

  final int index;
  final bool removes;
  String? front;
  String? back;
  String? reason;

  FlashcardVerdict? verdict(List<({String front, String back})> originals) {
    final why = reason;
    if (why == null || why.isEmpty) return null;
    if (removes) return FlashcardRemoval(index: index, reason: why);

    final newFront = front;
    final newBack = back;
    if (newFront == null || newFront.isEmpty) return null;
    if (newBack == null || newBack.isEmpty) return null;
    final original = originals[index];
    if (_same(newFront, original.front) && _same(newBack, original.back)) {
      return null;
    }
    return FlashcardCorrection(
      index: index,
      reason: why,
      front: newFront,
      back: newBack,
    );
  }
}

bool _same(String a, String b) =>
    a.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase() ==
    b.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
