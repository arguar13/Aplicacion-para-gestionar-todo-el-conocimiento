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

/// El audio de un podcast (F47, paso 6b): un archivo de la bóveda con la voz
/// de cada tramo, generado en el teléfono.
@immutable
class PodcastAudio {
  const PodcastAudio({
    required this.reference,
    required this.mimeType,
    required this.fingerprint,
    required this.duration,
    required this.starts,
  });

  /// La ruta relativa del archivo en la bóveda
  /// (`originales/<creación>/audio/…`): en el contenido, `audio_ref`.
  final String reference;

  /// `audio/mp4` (M4A) o `audio/wav`.
  final String mimeType;

  /// La huella de lo que se dijo (`podcastAudioFingerprint`): cada tramo con
  /// su voz y su pausa. Si el guion o las voces cambian, deja de coincidir, y
  /// el audio es de otra versión.
  final String fingerprint;

  final Duration duration;

  /// Dónde empieza cada tramo del guion, en orden.
  final List<Duration> starts;

  @override
  bool operator ==(Object other) =>
      other is PodcastAudio &&
      other.reference == reference &&
      other.mimeType == mimeType &&
      other.fingerprint == fingerprint &&
      other.duration == duration &&
      listEquals(other.starts, starts);

  @override
  int get hashCode => Object.hash(
    reference,
    mimeType,
    fingerprint,
    duration,
    Object.hashAll(starts),
  );
}

/// Por qué un podcast quedó sin audio.
enum PodcastAudioProblem {
  /// Una voz no está en el teléfono —falta bajarla— o este dispositivo no
  /// sabe hacerla.
  voiceMissing('voice_missing'),

  /// El motor de una voz falló.
  engine('engine'),

  /// No se pudo armar o guardar el archivo.
  file('file');

  const PodcastAudioProblem(this.storageKey);

  final String storageKey;

  static PodcastAudioProblem? fromStorageKey(Object? key) {
    for (final problem in values) {
      if (problem.storageKey == key) return problem;
    }
    return null;
  }
}

/// Lo que impidió generar el audio de un podcast: el guion quedó, y el visor
/// lo dice y ofrece generarlo de nuevo.
@immutable
class PodcastAudioIssue {
  const PodcastAudioIssue(this.problem, {this.voiceId});

  final PodcastAudioProblem problem;

  /// La voz que faltó o falló, si se sabe.
  final String? voiceId;

  @override
  bool operator ==(Object other) =>
      other is PodcastAudioIssue &&
      other.problem == problem &&
      other.voiceId == voiceId;

  @override
  int get hashCode => Object.hash(problem, voiceId);
}

/// Un podcast de «Lo creado» (F47, punto 5 del plan): el guion ya comprobado,
/// por tramos, con quién habla en cada uno, sus citas y sus silencios. Es lo
/// que se guarda en `StudyCreation.content`, con su audio ([audio]) una vez
/// generado con las voces de las opciones (`PodcastCast`) —o por qué no se
/// pudo ([audioIssue])—.
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
    this.audio,
    this.audioIssue,
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

  /// El audio, si ya se generó.
  final PodcastAudio? audio;

  /// Por qué no se generó el audio, si se intentó y no se pudo.
  final PodcastAudioIssue? audioIssue;

  /// El mismo guion, con [audio] y sin problema.
  Podcast withAudio(PodcastAudio audio) => _with(audio: audio);

  /// El mismo guion, sin audio, por [issue].
  Podcast withAudioIssue(PodcastAudioIssue issue) => _with(issue: issue);

  /// El mismo guion, sin audio ni problema: lo que se vuelve a dar voz.
  Podcast withoutAudio() => _with();

  Podcast _with({PodcastAudio? audio, PodcastAudioIssue? issue}) => Podcast(
    title: title,
    format: format,
    length: length,
    segments: segments,
    requestedWords: requestedWords,
    targetWords: targetWords,
    discarded: discarded,
    audio: audio,
    audioIssue: issue,
  );

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
      listEquals(other.discarded, discarded) &&
      other.audio == audio &&
      other.audioIssue == audioIssue;

  @override
  int get hashCode => Object.hash(
    title,
    format,
    length,
    Object.hashAll(segments),
    requestedWords,
    targetWords,
    Object.hashAll(discarded),
    audio,
    audioIssue,
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
