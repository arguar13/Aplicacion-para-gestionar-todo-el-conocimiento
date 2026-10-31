import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_generator.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';

/// Cuántas propuestas de «¿De qué trata?» se ofrecen.
const kPodcastProposals = 3;

/// El podcast de fábrica (F47, punto 5 del plan), con el color [accent]: la
/// hoja con el idioma, las fuentes con «+ Sumar otro documento», «¿De qué
/// trata?» con tres propuestas del material y un enfoque propio, el formato y
/// la duración. Lo que dibuja la app —las voces, el visor— lo suma
/// `podcastKindSpec`.
CreationKindSpec podcastKindSpecBase(CreationAccent accent) => CreationKindSpec(
  kind: StudyCreationKind.podcast,
  accent: accent,
  sheetTitle: (l) => l.f47P6SheetTitle,
  fields: const {
    CreationField.language,
    CreationField.sources,
    CreationField.moreSources,
    CreationField.topic,
  },
  topic: CreationTopicField(
    label: (l) => l.f47P6About,
    hint: (l) => l.f47P6AboutHint,
    suggestionsLabel: (l) => l.f47P6Proposals,
    suggestions: kPodcastProposals,
  ),
  options: [
    CreationChoiceOption(
      key: PodcastOptionKeys.format,
      label: (l) => l.f43StudioOptFormat,
      initial: PodcastFormat.conversation.storageKey,
      choices: [
        CreationChoice(
          PodcastFormat.brief.storageKey,
          (l) => l.f47P6FormatBrief,
        ),
        CreationChoice(
          PodcastFormat.lesson.storageKey,
          (l) => l.f47P6FormatLesson,
        ),
        CreationChoice(
          PodcastFormat.story.storageKey,
          (l) => l.f47P6FormatStory,
        ),
        CreationChoice(
          PodcastFormat.conversation.storageKey,
          (l) => l.f47P6FormatConversation,
        ),
      ],
    ),
    CreationChoiceOption(
      key: PodcastOptionKeys.length,
      label: (l) => l.f43StudioOptDuration,
      initial: PodcastLength.medium.storageKey,
      choices: [
        CreationChoice(
          PodcastLength.short.storageKey,
          (l) => l.f47P6LengthShort,
        ),
        CreationChoice(
          PodcastLength.medium.storageKey,
          (l) => l.f47P6LengthMedium,
        ),
        CreationChoice(PodcastLength.long.storageKey, (l) => l.f47P6LengthLong),
      ],
    ),
  ],
  // Lo que escribe la IA: las palabras de la duración, cada una con su cita y
  // su JSON.
  expectedOutputTokens: (o) =>
      (PodcastLength.of(o).targetWords * kPodcastTokensPerWord).round(),
);
