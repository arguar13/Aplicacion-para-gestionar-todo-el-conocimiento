import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/util/language_guess.dart';
import 'package:sinapsis/core/util/text_script.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';

/// La red de seguridad del idioma del texto de un video (F45, paso 4): antes
/// de guardar lo que se bajó, se mira si está escrito en el idioma que se
/// habla.
///
/// F22 ya hacía que nunca se bajara una pista de subtítulos de otro idioma.
/// Pero una pista se elige por su ETIQUETA, y lo que se habla se sabe por
/// pistas que pueden fallar: la pista de audio que YouTube marca como «la de
/// siempre» puede ser un doblaje hecho con IA; una versión anterior pudo
/// guardar como idioma del video el de la pista que bajó, y desde ahí pedirla
/// otra vez como si la hubiera elegido la persona; una pista puede estar
/// mal etiquetada. El texto mismo no miente: si un video con el título en
/// español tiene su transcripción en letras árabes, esa transcripción no es
/// lo que se dijo. Se mira:
///
/// 1. **La escritura**: qué parte de sus letras es de la escritura del idioma
///    que se habla. Menos de [kVideoTextMinShare] es otro idioma.
/// 2. **El idioma**, si los dos se escriben en latín: el que reconoce
///    `guessLanguage` en el texto, cuando lo reconoce con seguridad.
///
/// Ante la duda —un texto corto, un video que mezcla dos idiomas, uno del que
/// no se sabe qué se habla—, no se rechaza nada: [VideoTextUnsure].
@immutable
sealed class VideoTextVerdict {
  const VideoTextVerdict();
}

/// Está en el idioma que se habla.
final class VideoTextFits extends VideoTextVerdict {
  const VideoTextFits();
}

/// No hay con qué juzgarlo: es corto, mezcla idiomas, o no se sabe qué se
/// habla. Se guarda como siempre.
final class VideoTextUnsure extends VideoTextVerdict {
  const VideoTextUnsure();
}

/// Está en otro idioma que el que se habla: no se guarda.
final class VideoTextForeign extends VideoTextVerdict {
  const VideoTextForeign({required this.script, this.language, this.spoken});

  /// La escritura en que está.
  final TextScript script;

  /// El idioma en que está, si se reconoce —por su escritura, como el árabe,
  /// o por sus palabras—; `null` si no.
  final String? language;

  /// El idioma que se habla, si se sabe.
  final String? spoken;

  @override
  bool operator ==(Object other) =>
      other is VideoTextForeign &&
      other.script == script &&
      other.language == language &&
      other.spoken == spoken;

  @override
  int get hashCode => Object.hash(script, language, spoken);

  @override
  String toString() => 'VideoTextForeign($script, $language, $spoken)';
}

/// Cuántas letras hacen falta, como mínimo, para juzgar un texto: menos es
/// un video corto o casi sin habla —«[Música]» y dos palabras—, y la
/// escritura de dos palabras no dice nada.
const kVideoTextMinLetters = 40;

/// Qué parte de las letras, como mínimo, tiene que estar en la escritura del
/// idioma que se habla. Bajo a propósito: un video en español que cita
/// versos en árabe, o uno que mezcla dos idiomas, no se rechaza; uno escrito
/// entero en otra escritura, sí.
const kVideoTextMinShare = 0.35;

/// Cuánto del texto se mira para reconocer su idioma por las palabras: más
/// que el comienzo de una descripción, porque una transcripción suele
/// empezar con un saludo o con música.
const kVideoTextGuessLength = 12000;

/// Lo dicho de [transcript], sin las marcas de tiempo «[3:15]», sin lo que va
/// entre corchetes —«[Música]», «[fragmento no reconocido 3:15–3:29]»— y sin
/// enlaces: lo que no es habla no dice en qué idioma se habla.
String spokenWordsOf(String transcript) => transcript
    .replaceAll(RegExp(r'\[[^\]\n]*\]'), ' ')
    .replaceAll(RegExp(r'(https?://|www\.)\S+'), ' ');

/// El idioma que se habla en un video, para juzgar su texto y para
/// transcribir su audio (F45, paso 4), o `null` si no se puede saber.
///
/// - [chosen] es el idioma guardado del video (`Source.language`). Si es uno
///   de los que la app ofrece elegir ([transcriptionLanguages]), lo eligió la
///   persona —o lo confirmó al volver a extraer— y manda, como en F22.
/// - Si no, es una pista más, como [detected] —el que dijo YouTube: el de su
///   audio original, el de su pista automática o el de su título—: vale si
///   su escritura coincide con la del título. Un idioma guardado que no se
///   ofrece lo puso la app al guardar una pista —un video en español con
///   subtítulos en árabe guardaba «ar»—, y pedirlo de nuevo volvía a bajar la
///   misma.
/// - Si ninguna pista coincide con el título, el del título y la descripción
///   ([title], [description]): el que reconoce `guessLanguage`, o el que dice
///   su escritura sola (el árabe, el ruso…).
String? expectedVideoLanguage({
  String? chosen,
  String? detected,
  String title = '',
  String description = '',
}) {
  if (chosen != null && transcriptionLanguages.contains(_primary(chosen))) {
    return _primary(chosen);
  }
  final titleScript = scriptCensusOf(title).clearScript();
  for (final hint in [chosen, detected]) {
    if (hint == null) continue;
    final script = scriptOfLanguage(hint);
    if (titleScript == null || script == null || script == titleScript) {
      return _primary(hint);
    }
  }
  if (titleScript == null) return null;
  final guessed = guessLanguage('$title\n$description');
  if (guessed != null && scriptOfLanguage(guessed) == titleScript) {
    return guessed;
  }
  return languageOfScript(titleScript);
}

/// Si [text] —el texto de un video, con sus marcas de tiempo o sin ellas—
/// está en [spoken], el idioma que se habla (F45, paso 4). Ver
/// [VideoTextVerdict].
///
/// Sin [spoken], el título ([title]) dice al menos la escritura: un título en
/// letras latinas con un texto en letras árabes no es el mismo idioma.
VideoTextVerdict checkVideoText(
  String text, {
  String? spoken,
  String title = '',
}) {
  final words = spokenWordsOf(text);
  final census = scriptCensusOf(words);
  final found = census.dominant;
  if (found == null || census.letters < kVideoTextMinLetters) {
    return const VideoTextUnsure();
  }

  final language = spoken == null ? null : _primary(spoken);
  final expected = language != null
      ? scriptOfLanguage(language)
      : scriptCensusOf(title).clearScript();
  if (expected == null) return const VideoTextUnsure();

  if (census.shareOf(expected) < kVideoTextMinShare) {
    return VideoTextForeign(
      script: found,
      language: languageOfScript(found),
      spoken: language,
    );
  }

  // La misma escritura: el idioma por sus palabras, si se reconoce con
  // seguridad. `guessLanguage` reconoce los seis que se ofrecen; con otro
  // idioma que se habla —el turco, el polaco— no hay con qué compararlo.
  if (language == null || !transcriptionLanguages.contains(language)) {
    return const VideoTextFits();
  }
  final guessed = guessLanguage(words, maximumLength: kVideoTextGuessLength);
  if (guessed != null && guessed != language) {
    return VideoTextForeign(script: found, language: guessed, spoken: language);
  }
  return const VideoTextFits();
}

String _primary(String code) => code.toLowerCase().split(RegExp('[-_]')).first;
