/// Escuchar un podcast y pedir su audio (F47, paso 6b): el documento que lee
/// el reproductor anclado, con su audio ya generado; el costo de una voz de
/// la nube, dicho antes; y «Generar el audio», por la cola de siempre.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_progress.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/voices/speech_audio_approval.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El id con que el lector conoce al podcast [creationId]: el de su
/// documento y el `sourceKey` de su transcripción.
String podcastReadableId(String creationId) => 'podcast:$creationId';

/// Los pedazos que lee el lector: uno por tramo, con sus posiciones en la
/// transcripción entera —los tramos uno tras otro, separados por un salto—,
/// así cada tramo del visor pregunta solo por lo suyo
/// (`readAloudSpanProvider`).
List<ReadableSegment> podcastReadableSegments(
  Podcast podcast,
  String creationId,
) {
  final key = podcastReadableId(creationId);
  var at = 0;
  return [
    for (final segment in podcast.segments)
      () {
        final start = at;
        at += segment.text.length + 1;
        return ReadableSegment(
          sourceKey: key,
          start: start,
          end: start + segment.text.length,
          spoken: segment.text,
        );
      }(),
  ];
}

/// Dónde empieza el tramo [index] en la transcripción entera.
int podcastSegmentStart(Podcast podcast, int index) {
  var at = 0;
  for (var i = 0; i < index; i++) {
    at += podcast.segments[i].text.length + 1;
  }
  return at;
}

/// La voz del lector de [voiceId] —para la cara del reproductor y la
/// tarjeta—, o `null` si no se sabe.
NarrationVoice? podcastNarrationVoice(String voiceId) {
  final offline = SpeechVoiceIds.offlineIdOf(voiceId);
  if (offline != null) {
    final voice = OfflineVoiceCatalog.byId(offline);
    return voice == null ? null : narrationVoiceOf(voice);
  }
  final device = SpeechVoiceIds.deviceOf(voiceId);
  if (device != null && device.name.isNotEmpty) {
    return NarrationVoice(name: device.name, locale: device.locale);
  }
  return null;
}

/// Lo que suena al escuchar [podcast] de [creation], con su audio en [path]:
/// el documento del reproductor anclado, con el título de la creación y la
/// dirección de su visor —adonde vuelven la tarjeta de lo que suena y
/// «Seguir escuchando» (F47, pasos 1 y 7a)—, también cuando se abre con
/// «Escuchar» y no desde la pantalla.
ReadableDocument podcastReadableDocument({
  required StudyCreation creation,
  required Podcast podcast,
  required PodcastAudio audio,
  required String path,
  required String title,
}) {
  final cast = PodcastCast.of(creation.options, podcast.format);
  final pieces = podcastSpeechPieces(podcast, cast, creation.languageCode);
  return ReadableDocument(
    id: podcastReadableId(creation.id),
    title: title,
    location: RoutePaths.creation(creation.id),
    segments: podcastReadableSegments(podcast, creation.id),
    recording: RecordedSpeech(
      path: path,
      duration: audio.duration,
      starts: audio.starts,
      voices: [
        for (final piece in pieces) podcastNarrationVoice(piece.voiceId),
      ],
    ),
  );
}

/// La ruta en el teléfono del audio `reference` de la bóveda, o `null` si
/// no está —llegó de otra bóveda sin él, o se borró—.
final podcastAudioPathProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, reference) async {
      final files = ref.watch(fileStoreProvider);
      if (!await files.exists(reference)) return null;
      return files.localPathOf(reference);
    });

/// Cuántos caracteres se estima que tiene cada palabra dicha, con su
/// espacio: para el costo antes de que exista el guion.
const kPodcastCharactersPerWord = 6;

/// Lo que costaría el audio de un podcast pedido con [options] en
/// [languageCode], estimado por las palabras de su duración repartidas entre
/// sus voces; `null` si sus voces son todas gratis (decisión F).
SpeechAudioCost? podcastCostEstimate(
  Map<String, Object?> options,
  String languageCode,
  SpeechAudioCost? Function(Iterable<SpeechAudioPiece> pieces) costOf,
) {
  final format = PodcastFormat.of(options);
  final cast = PodcastCast.of(options, format);
  final characters =
      PodcastLength.of(options).targetWords * kPodcastCharactersPerWord;
  final share = (characters / cast.length).ceil();
  return costOf([
    for (final choice in cast)
      SpeechAudioPiece(
        text: 'x' * share,
        voiceId: podcastSpeechVoiceId(choice.voiceId, languageCode),
      ),
  ]);
}

/// Si se sigue con [cost]: sin costo, sí; con costo, lo que diga quien
/// aprueba (`speechAudioApprovalProvider`: un aviso, o la puerta de la nube
/// del paso 4).
Future<bool> confirmPodcastCost(
  BuildContext context,
  WidgetRef ref,
  SpeechAudioCost? cost,
) async {
  if (cost == null) return true;
  return ref.read(speechAudioApprovalProvider)(context, cost);
}

/// Lo que confirma la hoja del podcast antes de pedirlo
/// (`CreationKindSpec.confirmGenerate`): el costo, si alguna voz es de la
/// nube.
Future<bool> confirmPodcastGenerate(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> options,
  String languageCode,
) {
  final renderer = ref.read(speechAudioRendererProvider);
  return confirmPodcastCost(
    context,
    ref,
    podcastCostEstimate(options, languageCode, renderer.costOf),
  );
}

/// «Generar el audio» de [creation], un podcast ya listo: con el costo
/// dicho antes si alguna voz es de la nube, deja su guion como lo que queda
/// por hacer (`PodcastVoiceProgress`) y la vuelve a la cola con «ahora»
/// —la misma fila, el mismo retome, el mismo servicio en primer plano—. La
/// cola lo termina sin la IA.
Future<void> requestPodcastAudio(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final podcast = PodcastJson.decode(creation.decodedContent);
  if (podcast == null) return;
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final renderer = ref.read(speechAudioRendererProvider);
  final cast = PodcastCast.of(creation.options, podcast.format);
  final cost = renderer.costOf(
    podcastSpeechPieces(podcast, cast, creation.languageCode),
  );
  if (!await confirmPodcastCost(context, ref, cost)) return;
  final saved = await ref
      .read(studyCreationRepositoryProvider)
      .saveCheckpoint(
        creation.id,
        PodcastVoiceProgress(podcast.withoutAudio(), keepTitle: true).encode(),
      );
  final queued = saved.isLeft()
      ? saved.map((_) => creation)
      : await ref.read(creationQueueProvider).retry(creation.id, runNow: true);
  messenger
    ..hideCurrentSnackBar()
    ..showAppSnackBar(
      AppSnackBar(
        content: Text(
          queued.isLeft()
              ? l10n.f47P6bAudioRequestFailed
              : l10n.f47P6bAudioQueued,
        ),
      ),
    );
}

/// Pide el audio de [creation] sin esperar: lo que llama un botón.
void requestPodcastAudioLater(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) => unawaited(requestPodcastAudio(context, ref, creation));
