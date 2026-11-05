/// El audio del podcast (F47, paso 6b): de qué tramos se arma, con qué voz
/// cada uno, cómo se sabe si un audio guardado es el de este guion y quién lo
/// genera.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// La voz con que se genera lo que dice una persona que eligió [voiceId] en
/// un podcast en [languageCode]: la misma, con su prefijo de origen; la del
/// teléfono por defecto (`null`) es la que el teléfono use para ese idioma.
String podcastSpeechVoiceId(String? voiceId, String languageCode) =>
    voiceId ?? SpeechVoiceIds.device(locale: languageCode);

/// Lo que se dice en [podcast], tramo por tramo, con la voz de quien habla
/// en [cast] y la pausa de después: lo que se le pide a la pieza común del
/// audio (`SpeechAudioRenderer`).
List<SpeechAudioPiece> podcastSpeechPieces(
  Podcast podcast,
  List<PodcastVoiceChoice> cast,
  String languageCode,
) {
  final voices = {
    for (final choice in cast)
      choice.speaker: podcastSpeechVoiceId(choice.voiceId, languageCode),
  };
  final fallback = podcastSpeechVoiceId(null, languageCode);
  return [
    for (final segment in podcast.segments)
      SpeechAudioPiece(
        text: segment.text,
        voiceId: voices[segment.speaker] ?? fallback,
        pauseAfter: segment.pauseAfter,
      ),
  ];
}

/// La huella de [pieces]: cambia si cambia un texto, una voz o una pausa.
/// Es lo que dice si un audio guardado es de este guion con estas voces.
String podcastAudioFingerprint(List<SpeechAudioPiece> pieces) {
  final digest = sha256.convert(
    utf8.encode(
      jsonEncode([
        for (final piece in pieces)
          [piece.voiceId, piece.pauseAfter.inMilliseconds, piece.text],
      ]),
    ),
  );
  return digest.toString().substring(0, 32);
}

/// En qué está el audio de un podcast, para su visor.
enum PodcastAudioState {
  /// Está, y es de este guion con estas voces: se puede escuchar.
  ready,

  /// Hay uno, pero de otra versión del guion o de otras voces: no se finge;
  /// se dice y se ofrece generarlo de nuevo.
  stale,

  /// Se intentó y no se pudo: `Podcast.audioIssue` dice por qué.
  failed,

  /// Nunca se generó: un podcast de antes del audio.
  none,
}

/// El estado del audio de [podcast] con las voces de [cast].
PodcastAudioState podcastAudioStateOf(
  Podcast podcast,
  List<PodcastVoiceChoice> cast,
  String languageCode,
) {
  final audio = podcast.audio;
  if (audio == null) {
    return podcast.audioIssue == null
        ? PodcastAudioState.none
        : PodcastAudioState.failed;
  }
  final current = podcastAudioFingerprint(
    podcastSpeechPieces(podcast, cast, languageCode),
  );
  return audio.fingerprint == current &&
          audio.starts.length == podcast.segments.length
      ? PodcastAudioState.ready
      : PodcastAudioState.stale;
}

/// Quien genera el audio de un podcast y lo guarda en la bóveda (decisión F:
/// nunca en la nube). Devuelve el mismo podcast con su audio
/// (`Podcast.withAudio`) o, si no se pudo, con por qué
/// (`Podcast.withAudioIssue`): el guion no se pierde por la voz. Solo lanza
/// si se cancela ([ProcessingCancelledException]).
// ignore: one_member_abstracts
abstract interface class PodcastVoicer {
  Future<Podcast> voice({
    required String creationId,
    required Podcast podcast,
    required List<PodcastVoiceChoice> cast,
    required String languageCode,
    CancellationSignal? cancellation,
    void Function(double progress)? onProgress,
  });
}
