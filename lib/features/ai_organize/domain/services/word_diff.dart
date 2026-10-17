import 'package:meta/meta.dart';

/// Qué le pasó a un pedazo de texto entre el antes y el después.
enum DiffKind {
  /// Está en los dos.
  same,

  /// Estaba antes y ya no.
  removed,

  /// No estaba y ahora sí.
  added,
}

/// Un pedazo del antes o del después de una corrección (F33), con lo que le
/// pasó: lo que se resalta al mostrarla.
@immutable
class DiffSegment {
  const DiffSegment(this.kind, this.text);

  final DiffKind kind;

  /// Las palabras, con los espacios que las separan tal como estaban.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DiffSegment && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.name}(«$text»)';
}

/// Cuántas comparaciones de palabras, como mucho, antes de dejar de buscar lo
/// que tienen en común: una tarjeta tiene decenas de palabras; un texto
/// enorme se muestra entero como quitado y agregado, sin trabar la pantalla.
const kMaxWordDiffCells = 250000;

/// [before] y [after] palabra por palabra (F33): lo que tienen en común —la
/// subsecuencia común más larga, sin distinguir mayúsculas— queda igual, y el
/// resto, quitado o agregado.
///
/// Devuelve los pedazos del antes (iguales y quitados) y los del después
/// (iguales y agregados), en orden, con dos pedazos seguidos del mismo tipo ya
/// unidos. Las palabras van con el espacio que las sigue, así que pegar los
/// textos de cada lado devuelve el texto tal cual.
({List<DiffSegment> before, List<DiffSegment> after}) wordDiff(
  String before,
  String after,
) {
  final a = _words(before);
  final b = _words(after);
  if (a.length * b.length > kMaxWordDiffCells) {
    return (
      before: [if (before.isNotEmpty) DiffSegment(DiffKind.removed, before)],
      after: [if (after.isNotEmpty) DiffSegment(DiffKind.added, after)],
    );
  }

  // lengths[i][j]: lo más largo en común entre a[i..] y b[j..].
  final lengths = List.generate(
    a.length + 1,
    (_) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lengths[i][j] = _same(a[i], b[j])
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] >= lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }

  final left = <DiffSegment>[];
  final right = <DiffSegment>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && _same(a[i], b[j])) {
      _push(left, DiffKind.same, a[i++]);
      _push(right, DiffKind.same, b[j++]);
    } else if (j < b.length &&
        (i == a.length || lengths[i][j + 1] >= lengths[i + 1][j])) {
      _push(right, DiffKind.added, b[j++]);
    } else {
      _push(left, DiffKind.removed, a[i++]);
    }
  }
  return (before: left, after: right);
}

/// Las palabras de [text], cada una con los espacios que la siguen; lo que
/// hay antes de la primera va pegado a ella.
List<String> _words(String text) => [
  for (final match in RegExp(r'\s*\S+\s*').allMatches(text)) match.group(0)!,
];

bool _same(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

void _push(List<DiffSegment> segments, DiffKind kind, String text) {
  if (segments.isNotEmpty && segments.last.kind == kind) {
    segments.last = DiffSegment(kind, segments.last.text + text);
  } else {
    segments.add(DiffSegment(kind, text));
  }
}
