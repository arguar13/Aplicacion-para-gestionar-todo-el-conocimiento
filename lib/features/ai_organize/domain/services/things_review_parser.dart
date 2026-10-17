import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_intro.dart';
import 'package:sinapsis/features/ai_organize/domain/services/things_reviewer.dart';

final _header = RegExp(
  r'^DATO\s*(\d+)\s*[:\-–]\s*(bien|corregir|sacar)\b',
  caseSensitive: false,
);
final _value = RegExp(r'^VALOR\s*:\s*(.+)$', caseSensitive: false);
final _kind = RegExp(r'^TIPO\s*:\s*(.+)$', caseSensitive: false);
final _note = RegExp(r'^FRASE\s*:\s*(.+)$', caseSensitive: false);
final _reason = RegExp(
  r'^(?:POR\s*QU[ÉE]|MOTIVO)\s*:\s*(.+)$',
  caseSensitive: false,
);

/// Lo que el modelo agrega por costumbre aunque se le pida que no: negritas,
/// viñetas, numeración.
final _decoration = RegExp(r'^[\s*_#>\-•]+|[\s*_]+$');
final _spaces = RegExp(r'\s+');

/// Lee la respuesta del revisor de «lo demás» (F33) sobre [things], en ese
/// orden.
///
/// Función pura, como `parseFlashcardReview`, con el mismo formato: por cada
/// cosa, un encabezado `DATO <n>: bien | corregir | sacar`; una corrección
/// sigue con `VALOR:` —en un vínculo, `TIPO:` y `FRASE:`— y `POR QUÉ:`, y lo
/// que se saca, con `POR QUÉ:`.
///
/// **Lo que no se entiende no se propone**, y lo que no cumple las reglas de
/// cada cosa tampoco:
///
/// - un veredicto sin su `POR QUÉ:`, o un número fuera de la lista, se
///   descarta; si una cosa aparece dos veces, vale la primera;
/// - sacar lo que no se saca (una introducción) o corregir lo que no se
///   corrige (una etiqueta que no es de texto) se descarta;
/// - con opciones, el valor tiene que ser una de ellas —sin contar
///   mayúsculas ni espacios—, y queda escrito como la opción;
/// - en un vínculo, lo que no dice queda como estaba: un `TIPO:` sin
///   `FRASE:` cambia solo el tipo;
/// - la introducción de una nota mapa se limpia como la escribe la IA
///   (`cleanMapIntro`);
/// - una «corrección» que deja todo igual no es una corrección.
List<ThingVerdict> parseThingsReview(
  String raw, {
  required List<ThingToReview> things,
}) {
  final verdicts = <ThingVerdict>[];
  final seen = <int>{};
  _Open? open;

  void close() {
    final current = open;
    open = null;
    if (current == null) return;
    final verdict = current.verdict(things[current.index]);
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
      if (index < 0 || index >= things.length || kind == 'bien') continue;
      open = _Open(index: index, removes: kind == 'sacar');
      continue;
    }

    final current = open;
    if (current == null) continue;
    if (_value.firstMatch(line) case final match?) {
      current.value ??= match.group(1)!.trim();
    } else if (_kind.firstMatch(line) case final match?) {
      current.kind ??= match.group(1)!.trim();
    } else if (_note.firstMatch(line) case final match?) {
      current.note ??= match.group(1)!.trim();
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
  String? value;
  String? kind;
  String? note;
  String? reason;

  ThingVerdict? verdict(ThingToReview thing) {
    final why = reason;
    if (why == null || why.isEmpty) return null;
    if (removes) {
      return thing.canRemove ? ThingRemoval(index: index, reason: why) : null;
    }
    if (!thing.canFix) return null;

    if (thing.subject == CorrectionSubject.relation) {
      final newKind = _option(kind ?? value ?? thing.value, thing.options);
      if (newKind == null) return null;
      final newNote = (note ?? thing.note ?? '')
          .replaceAll(_spaces, ' ')
          .trim();
      if (newKind == thing.value && _same(newNote, thing.note ?? '')) {
        return null;
      }
      return ThingCorrection(
        index: index,
        reason: why,
        value: newKind,
        note: newNote,
      );
    }

    final proposed = value;
    if (proposed == null) return null;
    final String? newValue;
    if (thing.options.isNotEmpty) {
      newValue = _option(proposed, thing.options);
    } else if (thing.subject == CorrectionSubject.mapIntro) {
      newValue = cleanMapIntro(proposed);
    } else {
      newValue = proposed.replaceAll(_spaces, ' ').trim();
    }
    if (newValue == null || newValue.isEmpty) return null;
    if (_same(newValue, thing.value)) return null;
    return ThingCorrection(index: index, reason: why, value: newValue);
  }
}

/// La opción de [options] que es [text], escrita como la opción; `null` si no
/// es ninguna.
String? _option(String text, List<String> options) {
  final wanted = _plain(text);
  for (final option in options) {
    if (_plain(option) == wanted) return option;
  }
  return null;
}

bool _same(String a, String b) => _plain(a) == _plain(b);

String _plain(String text) =>
    text.trim().replaceAll(_spaces, ' ').toLowerCase();
