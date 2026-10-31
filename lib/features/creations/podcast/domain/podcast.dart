import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';

/// De dónde sale lo que dice un tramo: unas palabras literales del material,
/// ya comprobadas —están en el texto que leyó la IA (`PodcastChecker`)—, y el
/// documento procesado en el que están. Tocarla lleva al pasaje.
@immutable
class PodcastCitation {
  const PodcastCitation({
    required this.quote,
    this.documentId,
    this.documentTitle,
  });

  /// Las palabras del material, tal como las copió la IA.
  final String quote;

  /// El documento en cuyo texto se encontró [quote]; `null` solo si el
  /// material no dice de quién es cada tramo.
  final String? documentId;
  final String? documentTitle;

  @override
  bool operator ==(Object other) =>
      other is PodcastCitation &&
      other.quote == quote &&
      other.documentId == documentId &&
      other.documentTitle == documentTitle;

  @override
  int get hashCode => Object.hash(quote, documentId, documentTitle);

  @override
  String toString() => 'PodcastCitation($documentId, «$quote»)';
}

/// Qué clase de tramo es.
enum PodcastSegmentKind {
  /// Dice algo del material: lleva al menos una cita.
  data('data'),

  /// Une: un saludo, una pregunta, una transición. Corto y sin datos
  /// (`kPodcastMaxLinkWords`, sin cifras); uno más largo se trata como dato.
  link('link');

  const PodcastSegmentKind(this.storageKey);

  final String storageKey;

  static PodcastSegmentKind? fromStorageKey(Object? key) {
    for (final kind in values) {
      if (kind.storageKey == key) return kind;
    }
    return null;
  }
}

/// Un tramo del guion: quién lo dice, qué dice, de dónde sale y cuánto se
/// espera después de decirlo.
@immutable
class PodcastSegment {
  const PodcastSegment({
    required this.speaker,
    required this.text,
    required this.kind,
    this.citations = const [],
    this.pauseAfter = Duration.zero,
  });

  final PodcastSpeaker speaker;

  /// Lo que se dice, para escuchar.
  final String text;
  final PodcastSegmentKind kind;

  /// Sus citas, ya comprobadas, sin repetir.
  final List<PodcastCitation> citations;

  /// El silencio que va después (`podcastPauseAfter`): un respiro si sigue la
  /// misma voz, una pausa si cambia o si la IA pidió una larga. El audio lo
  /// respeta tal cual.
  final Duration pauseAfter;

  /// Cuántas palabras dice.
  int get words => countPodcastWords(text);

  @override
  bool operator ==(Object other) =>
      other is PodcastSegment &&
      other.speaker == speaker &&
      other.text == text &&
      other.kind == kind &&
      listEquals(other.citations, citations) &&
      other.pauseAfter == pauseAfter;

  @override
  int get hashCode =>
      Object.hash(speaker, text, kind, Object.hashAll(citations), pauseAfter);

  @override
  String toString() =>
      'PodcastSegment(${speaker.storageKey}, ${kind.storageKey}, '
      '${citations.length} citas, «$text»)';
}

/// Por qué se quitó un tramo al comprobar el guion.
enum PodcastDiscardReason {
  /// Decía algo del material sin ninguna cita.
  noCitation('no_citation'),

  /// Sus citas no están en el material: la IA las inventó o las cambió tanto
  /// que ya no son las del texto.
  quoteNotInMaterial('quote_not_in_material'),

  /// Decía una cifra que no aparece en el material.
  numberNotInMaterial('number_not_in_material');

  const PodcastDiscardReason(this.storageKey);

  final String storageKey;

  static PodcastDiscardReason? fromStorageKey(Object? key) {
    for (final reason in values) {
      if (reason.storageKey == key) return reason;
    }
    return null;
  }
}

/// Un tramo que la IA escribió y la comprobación quitó, con por qué: el visor
/// lo muestra aparte, tachado, para que se sepa qué se sacó.
@immutable
class PodcastDiscard {
  const PodcastDiscard({required this.reason, required this.text});

  final PodcastDiscardReason reason;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PodcastDiscard && other.reason == reason && other.text == text;

  @override
  int get hashCode => Object.hash(reason, text);
}

/// Un podcast de «Lo creado» (F47, punto 5 del plan): el guion ya comprobado,
/// por tramos, con quién habla en cada uno, sus citas y sus silencios. Es lo
/// que se guarda en `StudyCreation.content`; el audio de cada tramo se genera
/// después, con las voces de las opciones (`PodcastCast`).
@immutable
class Podcast {
  const Podcast({
    required this.title,
    required this.format,
    required this.length,
    required this.segments,
    required this.requestedWords,
    required this.targetWords,
    this.discarded = const [],
  });

  final String title;
  final PodcastFormat format;

  /// La duración pedida.
  final PodcastLength length;

  final List<PodcastSegment> segments;

  /// Las palabras de la duración pedida.
  final int requestedWords;

  /// Las palabras a las que se apuntó: las pedidas, o menos si el material no
  /// daba para tanto sin rellenar (`podcastTargetWords`).
  final int targetWords;

  /// Lo que la comprobación quitó.
  final List<PodcastDiscard> discarded;

  /// Cuántas palabras se dicen, en total.
  int get words => segments.fold(0, (sum, s) => sum + s.words);

  /// Si salió más corto de lo pedido porque el material no daba para más.
  bool get shortenedByMaterial => targetWords < requestedWords;

  /// Cuánto dura, estimado: las palabras a [kPodcastWordsPerMinute] y los
  /// silencios entre tramos.
  Duration get estimatedDuration =>
      Duration(milliseconds: (words * 60000 / kPodcastWordsPerMinute).round()) +
      segments.fold(Duration.zero, (sum, s) => sum + s.pauseAfter);

  /// Las citas de todos los tramos, sin repetir, en orden.
  List<PodcastCitation> get citations {
    final seen = <PodcastCitation>{};
    return [
      for (final segment in segments)
        for (final citation in segment.citations)
          if (seen.add(citation)) citation,
    ];
  }

  /// Quiénes hablan, en el orden en que aparecen.
  List<PodcastSpeaker> get speakers =>
      {for (final segment in segments) segment.speaker}.toList();

  @override
  bool operator ==(Object other) =>
      other is Podcast &&
      other.title == title &&
      other.format == format &&
      other.length == length &&
      listEquals(other.segments, segments) &&
      other.requestedWords == requestedWords &&
      other.targetWords == targetWords &&
      listEquals(other.discarded, discarded);

  @override
  int get hashCode => Object.hash(
    title,
    format,
    length,
    Object.hashAll(segments),
    requestedWords,
    targetWords,
    Object.hashAll(discarded),
  );
}

/// Cuántas palabras tiene [text]: lo que va entre espacios.
int countPodcastWords(String text) {
  var words = 0;
  var inWord = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    final space = c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;
    if (space) {
      inWord = false;
    } else if (!inWord) {
      inWord = true;
      words++;
    }
  }
  return words;
}

/// El respiro entre dos tramos de la misma voz.
const kPodcastBreath = Duration(milliseconds: 300);

/// La pausa cuando cambia quien habla.
const kPodcastTurnPause = Duration(milliseconds: 550);

/// La pausa larga, cuando la IA la pidió: para pensar una pregunta de la
/// clase, o para que un momento del relato pese.
const kPodcastLongPause = Duration(milliseconds: 1200);

/// El silencio después de un tramo de [speaker], si sigue [next] (`null` si
/// es el último: nada) y si la IA pidió una pausa larga ([long]).
Duration podcastPauseAfter(
  PodcastSpeaker speaker, {
  required PodcastSpeaker? next,
  bool long = false,
}) {
  if (next == null) return Duration.zero;
  if (long) return kPodcastLongPause;
  return next == speaker ? kPodcastBreath : kPodcastTurnPause;
}
