import 'dart:io';

import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/data/creation_files.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/narration/data/audio/speech_audio_renderer.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// [PodcastVoicer] con la pieza común del audio (F47, paso 6b): cada tramo
/// con la voz de quien lo dice y su pausa ([podcastSpeechPieces]), generado
/// en el teléfono por [SpeechAudioRenderer] y guardado en la bóveda, en la
/// carpeta de la creación (`originales/<creación>/audio/`), nunca en la nube
/// (decisión F).
///
/// - **Retomable por tramo**: el trabajo es `podcast-<creación>`, el mismo en
///   cada intento, así que lo ya dicho no se vuelve a generar; volver a dar
///   voz a un guion que cambió en un tramo genera solo ese.
/// - **El archivo nuevo no pisa al de antes**: queda al lado, y el de antes
///   se va cuando el contenido nuevo queda guardado (el barrido del
///   repositorio, por `audio_ref`).
/// - **Lo que no se puede** —una voz que falta, un motor que falla— vuelve
///   como `PodcastAudioIssue` y el guion queda: lo hecho se guarda para el
///   próximo intento.
class ServicePodcastVoicer implements PodcastVoicer {
  ServicePodcastVoicer({
    required SpeechAudioRenderer renderer,
    required FileStore files,
  }) : _renderer = renderer,
       _files = files;

  final SpeechAudioRenderer _renderer;
  final FileStore _files;

  /// El trabajo de la pieza común para la creación [creationId].
  static String workKeyOf(String creationId) => 'podcast-$creationId';

  @override
  Future<Podcast> voice({
    required String creationId,
    required Podcast podcast,
    required List<PodcastVoiceChoice> cast,
    required String languageCode,
    CancellationSignal? cancellation,
    void Function(double progress)? onProgress,
  }) async {
    final pieces = podcastSpeechPieces(podcast, cast, languageCode);
    final workKey = workKeyOf(creationId);
    final SpeechAudioResult result;
    try {
      result = await _renderer.render(
        SpeechAudioRequest(workKey: workKey, pieces: pieces),
        cancellation: cancellation,
        onProgress: (done, total) => onProgress?.call(done / total),
      );
    } on SpeechAudioException catch (e) {
      return podcast.withAudioIssue(
        PodcastAudioIssue(switch (e.failure) {
          SpeechAudioFailure.voiceMissing => PodcastAudioProblem.voiceMissing,
          SpeechAudioFailure.engine => PodcastAudioProblem.engine,
          SpeechAudioFailure.file => PodcastAudioProblem.file,
        }, voiceId: e.voiceId),
      );
    }
    cancellation?.throwIfCancelled();
    final fingerprint = podcastAudioFingerprint(pieces);
    final String reference;
    try {
      reference = await _files.saveStream(
        bytes: File(result.path).openRead(),
        suggestedName:
            'podcast-${fingerprint.substring(0, 8)}.'
            '${result.extension}',
        id: creationId,
        folder: kCreationAudioFolder,
        unique: true,
      );
    } on FileSystemException {
      return podcast.withAudioIssue(
        const PodcastAudioIssue(PodcastAudioProblem.file),
      );
    }
    // Ya está en la bóveda: lo del trabajo sobra.
    await _renderer.discard(workKey);
    return podcast.withAudio(
      PodcastAudio(
        reference: reference,
        mimeType: result.mimeType,
        fingerprint: fingerprint,
        duration: result.duration,
        starts: result.starts,
      ),
    );
  }
}
