/// Exportar un podcast (F47, paso 5): su audio, el archivo que generó el
/// teléfono, o su guion como texto —quién dice cada cosa, con sus citas—.
/// Es lo que pasan «Compartir» y «Descargar» del menú de la creación.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/study_viewer_parts.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_labels.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_anchored_player.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué se exporta de un podcast.
enum PodcastExportChoice {
  /// El audio, como lo generó el teléfono (M4A).
  audio,

  /// El guion, como texto.
  script,
}

/// El archivo de [creation], un podcast listo: si su audio es el de este
/// guion y está en el teléfono, se pregunta si el audio o el guion; si no,
/// el guion, sin preguntar —un audio viejo no se hace pasar por el de este
/// guion—. `null` si se cerró la pregunta o no hay podcast.
Future<CreationExportFile?> exportPodcast(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final podcast = PodcastJson.decode(creation.decodedContent);
  if (podcast == null) return null;
  final l10n = AppLocalizations.of(context)!;
  final title = studyCreationTitle(l10n, creation);
  final files = ref.read(fileStoreProvider);
  final cast = PodcastCast.of(creation.options, podcast.format);
  final audio = podcast.audio;
  final hasAudio =
      audio != null &&
      podcastAudioStateOf(podcast, cast, creation.languageCode) ==
          PodcastAudioState.ready &&
      await files.exists(audio.reference);
  if (!context.mounted) return null;
  final choice = hasAudio
      ? await showStudyExportChoices<PodcastExportChoice>(
          context,
          title: l10n.f47P5PodcastExportTitle,
          choices: [
            StudyExportChoice(
              value: PodcastExportChoice.audio,
              icon: Icons.graphic_eq_rounded,
              title: l10n.f47P5PodcastExportAudio,
              subtitle: l10n.f47P5PodcastExportAudioHint(
                podcastAudioExtension(audio).toUpperCase(),
                formatReadAloudTime(audio.duration),
              ),
            ),
            StudyExportChoice(
              value: PodcastExportChoice.script,
              icon: Icons.notes_rounded,
              title: l10n.f47P5PodcastExportScript,
              subtitle: l10n.f47P5PodcastExportScriptHint,
            ),
          ],
        )
      : PodcastExportChoice.script;
  if (choice == null) return null;
  final name = sanitizeFileName(title);
  switch (choice) {
    case PodcastExportChoice.audio:
      final bytes = await files.read(audio!.reference);
      if (bytes == null) return null;
      return CreationExportFile(
        fileName: '$name.${podcastAudioExtension(audio)}',
        bytes: bytes,
        mimeType: audio.mimeType,
      );
    case PodcastExportChoice.script:
      final model = creation.modelName?.trim();
      return CreationExportFile(
        fileName: '$name.txt',
        bytes: Uint8List.fromList(
          utf8.encode(
            podcastScriptText(
              podcast,
              title: title,
              madeWith: model == null || model.isEmpty
                  ? l10n.f47P6MadeWithAi
                  : l10n.f47P6MadeWithAiModel(model),
              roleOf: (speaker) =>
                  podcastSpeakerRole(l10n, podcast.format, speaker),
              quote: l10n.f47P5ScriptQuote,
              quoteFrom: l10n.f47P5ScriptQuoteFrom,
            ),
          ),
        ),
        mimeType: 'text/plain',
      );
  }
}

/// La extensión del archivo del audio de un podcast.
String podcastAudioExtension(PodcastAudio audio) =>
    audio.mimeType == 'audio/wav' ? 'wav' : 'm4a';

/// **El guion de [podcast] como texto**: el título y «Hecho con IA»
/// ([madeWith]) arriba; después cada tramo con quién lo dice ([roleOf]) y,
/// debajo, sus citas del material ([quote], o [quoteFrom] con el documento
/// de donde salen). Un tramo por párrafo, con renglones en blanco entre
/// ellos.
String podcastScriptText(
  Podcast podcast, {
  required String title,
  required String madeWith,
  required String Function(PodcastSpeaker speaker) roleOf,
  required String Function(String quote) quote,
  required String Function(String quote, String document) quoteFrom,
}) {
  final out = StringBuffer()
    ..writeln(title)
    ..writeln(madeWith);
  for (final segment in podcast.segments) {
    out
      ..writeln()
      ..writeln('${roleOf(segment.speaker)}: ${segment.text.trim()}');
    for (final citation in segment.citations) {
      final document = citation.documentTitle?.trim();
      final line = document == null || document.isEmpty
          ? quote(citation.quote)
          : quoteFrom(citation.quote, document);
      out.writeln('    $line');
    }
  }
  return out.toString();
}
