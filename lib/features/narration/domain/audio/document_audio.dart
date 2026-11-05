/// El audio descargado de un documento (F47, paso 5): de qué tramos se arma
/// —uno por pedazo de lo que lee el lector, con la voz de su idioma—, cómo se
/// guarda en la bóveda y cómo se sabe si sigue siendo el de ahora.
///
/// Lo genera la pieza común (`SpeechAudioRenderer`, paso 6b), igual que el
/// audio de un podcast; esto solo dice qué pedirle y qué guardar.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/passage_languages.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';

/// La carpeta de la bóveda donde viven los audios descargados de los
/// documentos: `originales/audio-documentos/<clave>/`, una por documento
/// ([documentAudioKeyOf]). Dentro de `originales/`, así la copia de la bóveda
/// los lleva; ninguna fila los nombra, así que la unión de bóvedas no los
/// trae —se vuelven a generar con las voces de ese teléfono—.
const kDocumentAudioFolder = 'audio-documentos';

/// El silencio entre dos pedazos de un mismo texto: el respiro entre dos
/// renglones u oraciones, como el que deja la voz al leer.
const kDocumentAudioPause = Duration(milliseconds: 350);

/// El silencio al pasar de un texto a otro —de un documento al siguiente de
/// lo creado, del texto al resumen—: un poco más largo, para que se note.
const kDocumentAudioTextPause = Duration(milliseconds: 900);

/// La clave de [documentId] —el id con que el lector conoce al documento
/// (`ReadableDocument.id`)— como nombre de carpeta: un id puede traer `:` o
/// `/`, y una carpeta no. Es estable: el mismo documento, la misma carpeta.
String documentAudioKeyOf(String documentId) =>
    sha256.convert(utf8.encode(documentId)).toString().substring(0, 24);

/// El trabajo de la pieza común para el audio de [documentId]: el mismo en
/// cada intento, así que lo ya generado de un intento cortado no se rehace.
String documentAudioWorkKey(String documentId) =>
    'doc-${documentAudioKeyOf(documentId)}';

/// El id de la pieza común (`SpeechVoiceIds`) de la voz con que el lector lee
/// algo: una propia (`mia:<id>`) tal cual, una sin conexión con su prefijo y
/// una del teléfono con su acento y su nombre. Sin voz —el lector usa la del
/// teléfono—, la que el teléfono tenga para [locale].
String speechVoiceIdOf(NarrationVoice? voice, {required String locale}) {
  if (voice == null) return SpeechVoiceIds.device(locale: locale);
  if (isMyVoice(voice) || voice.engine == NarrationEngine.cloud) {
    return voice.name;
  }
  if (voice.engine == NarrationEngine.offline) {
    return SpeechVoiceIds.offline(voice.name);
  }
  return SpeechVoiceIds.device(
    locale: normalizeAccent(voice.locale),
    name: voice.name,
  );
}

/// Qué se genera para el audio de un documento: un tramo por pedazo de lo
/// que lee el lector con «Todo», con la voz que lo leería ahora —la de su
/// idioma, decisión L— y su pausa.
///
/// Un pedazo sin nada que decir no lleva tramo: empieza donde empieza el
/// siguiente. Así el audio tiene un comienzo para cada pedazo
/// ([segmentStarts]) y el lector resalta el que suena, como en un podcast.
@immutable
class DocumentAudioPlan {
  const DocumentAudioPlan._({
    required this.pieces,
    required this.pieceOfSegment,
    required this.voices,
  });

  /// El de [segments] con [voices] —la voz de cada pedazo, en su orden—.
  /// [fallbackLocale] es el idioma de la voz del teléfono para un pedazo sin
  /// voz y sin idioma reconocido: el del teléfono.
  factory DocumentAudioPlan.of(
    List<ReadableSegment> segments,
    List<NarrationVoice?> voices, {
    required String fallbackLocale,
  }) {
    assert(voices.length == segments.length, 'una voz por pedazo');
    final languages = PassageLanguages.of(segments);
    final spoken = <int>[
      for (var i = 0; i < segments.length; i++)
        if (segments[i].spoken.trim().isNotEmpty) i,
    ];
    final pieces = <SpeechAudioPiece>[];
    for (final (n, i) in spoken.indexed) {
      final next = n + 1 < spoken.length ? spoken[n + 1] : null;
      final voice = voices.elementAtOrNull(i);
      pieces.add(
        SpeechAudioPiece(
          text: segments[i].spoken.trim(),
          voiceId: speechVoiceIdOf(
            voice,
            locale: languages.at(i) ?? fallbackLocale,
          ),
          pauseAfter: next == null
              ? Duration.zero
              : segments[next].sourceKey == segments[i].sourceKey
              ? kDocumentAudioPause
              : kDocumentAudioTextPause,
        ),
      );
    }
    // El tramo de cada pedazo: el suyo, o —sin nada que decir— el siguiente.
    final pieceOf = List<int>.filled(segments.length, pieces.length);
    var piece = pieces.length;
    for (var i = segments.length - 1; i >= 0; i--) {
      if (segments[i].spoken.trim().isNotEmpty) piece--;
      pieceOf[i] = piece;
    }
    return DocumentAudioPlan._(
      pieces: List.unmodifiable(pieces),
      pieceOfSegment: List.unmodifiable(pieceOf),
      voices: List.unmodifiable([
        for (var i = 0; i < segments.length; i++) voices.elementAtOrNull(i),
      ]),
    );
  }

  /// Lo que se le pide a la pieza común, en orden.
  final List<SpeechAudioPiece> pieces;

  /// El tramo con que empieza cada pedazo; `pieces.length` si después de él
  /// no se dice nada más.
  final List<int> pieceOfSegment;

  /// La voz de cada pedazo, para la cara del reproductor.
  final List<NarrationVoice?> voices;

  /// Si no hay nada que decir.
  bool get isEmpty => pieces.isEmpty;

  /// La huella de lo que se dice ([speechAudioFingerprint]): si cambia un
  /// texto, una voz o una pausa, el audio guardado quedó viejo.
  String get fingerprint =>
      _fingerprints[this] ??= speechAudioFingerprint(pieces);

  static final _fingerprints = Expando<String>('huella del plan');

  /// Dónde empieza cada pedazo en el audio, de dónde empieza cada tramo
  /// ([pieceStarts]) y cuánto dura ([total]): un pedazo sin tramo propio
  /// empieza con el siguiente, y al final si no hay ninguno después.
  List<Duration> segmentStarts(List<Duration> pieceStarts, Duration total) => [
    for (final piece in pieceOfSegment)
      if (piece < pieceStarts.length) pieceStarts[piece] else total,
  ];
}

/// En qué está el audio descargado de un documento.
enum DocumentAudioStatus {
  /// No tiene.
  none,

  /// Tiene, y es el de este texto con estas voces: suena desde él.
  ready,

  /// Tiene, pero de otro texto o de otras voces: no se finge; se dice y se
  /// ofrece generarlo de nuevo.
  stale,
}

/// El estado de [audio] para el documento de [segments] con [plan].
DocumentAudioStatus documentAudioStatusOf(
  DocumentAudio? audio,
  DocumentAudioPlan plan,
  List<ReadableSegment> segments,
) {
  if (audio == null) return DocumentAudioStatus.none;
  return audio.fingerprint == plan.fingerprint &&
          audio.starts.length == segments.length
      ? DocumentAudioStatus.ready
      : DocumentAudioStatus.stale;
}

/// El audio descargado de un documento, como queda en la bóveda: su ficha
/// (`audio.json`) junto al archivo.
@immutable
class DocumentAudio {
  const DocumentAudio({
    required this.documentId,
    required this.title,
    required this.fingerprint,
    required this.reference,
    required this.mimeType,
    required this.duration,
    required this.starts,
    required this.voices,
    required this.createdAt,
  });

  /// La versión de la ficha: una más nueva que no se entiende no se usa.
  static const version = 1;

  /// El id con que el lector conoce al documento.
  final String documentId;

  /// Su título cuando se generó: el nombre del archivo al exportarlo.
  final String title;

  /// La huella de lo que se dijo ([DocumentAudioPlan.fingerprint]).
  final String fingerprint;

  /// La ruta del archivo en la bóveda.
  final String reference;

  /// `audio/mp4` (M4A) o `audio/wav` donde no hubo con qué comprimir.
  final String mimeType;

  final Duration duration;

  /// Dónde empieza cada pedazo del documento.
  final List<Duration> starts;

  /// La voz de cada pedazo, si se sabe.
  final List<NarrationVoice?> voices;

  final DateTime createdAt;

  /// La extensión del archivo según [mimeType].
  String get extension => mimeType == 'audio/wav' ? 'wav' : 'm4a';

  /// Lo que hace sonar el lector, con el archivo en [path].
  RecordedSpeech recordingAt(String path) => RecordedSpeech(
    path: path,
    duration: duration,
    starts: starts,
    voices: voices,
  );

  Map<String, Object?> toJson() {
    final table = <NarrationVoice>[];
    int indexOf(NarrationVoice? voice) {
      if (voice == null) return -1;
      final at = table.indexOf(voice);
      if (at >= 0) return at;
      table.add(voice);
      return table.length - 1;
    }

    final voiceOf = [for (final voice in voices) indexOf(voice)];
    return {
      'version': version,
      'documentId': documentId,
      'title': title,
      'fingerprint': fingerprint,
      'reference': reference,
      'mimeType': mimeType,
      'durationMs': duration.inMilliseconds,
      'startsMs': [for (final start in starts) start.inMilliseconds],
      'voices': [
        for (final voice in table)
          {
            'name': voice.name,
            'locale': voice.locale,
            'engine': voice.engine.name,
          },
      ],
      'voiceOf': voiceOf,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  /// La ficha de [json], o `null` si no se entiende —rota, de otra versión—:
  /// un audio que no se sabe qué es no suena como si fuera el de ahora.
  static DocumentAudio? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    try {
      if (json['version'] != version) return null;
      final table = [
        for (final voice in json['voices']! as List<Object?>)
          () {
            final map = voice! as Map<String, Object?>;
            return NarrationVoice(
              name: map['name']! as String,
              locale: map['locale']! as String,
              engine: NarrationEngine.values.byName(map['engine']! as String),
            );
          }(),
      ];
      final starts = [
        for (final ms in json['startsMs']! as List<Object?>)
          Duration(milliseconds: ms! as int),
      ];
      final voiceOf = [
        for (final at in json['voiceOf']! as List<Object?>) at! as int,
      ];
      if (voiceOf.length != starts.length) return null;
      return DocumentAudio(
        documentId: json['documentId']! as String,
        title: json['title']! as String,
        fingerprint: json['fingerprint']! as String,
        reference: json['reference']! as String,
        mimeType: json['mimeType']! as String,
        duration: Duration(milliseconds: json['durationMs']! as int),
        starts: List.unmodifiable(starts),
        voices: List.unmodifiable([
          for (final at in voiceOf)
            if (at >= 0 && at < table.length) table[at] else null,
        ]),
        createdAt: DateTime.parse(json['createdAt']! as String),
      );
    } on Object {
      // Un campo que falta o de otro tipo (`TypeError`), un motor que no
      // existe (`ArgumentError`), una fecha rota (`FormatException`): la
      // ficha no se entiende.
      return null;
    }
  }
}
