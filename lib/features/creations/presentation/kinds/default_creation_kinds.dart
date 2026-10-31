import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_kind_base.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_labels.dart';

/// Las claves y los valores de las opciones de fábrica (F43, punto 4 del
/// plan): lo que guarda la hoja y leen los generadores de la ola 3. Son
/// estables —se guardan—, nunca el texto traducido.
abstract final class CreationOptionValues {
  // Claves.
  static const format = 'format';
  static const template = 'template';
  static const length = 'length';
  static const illustrations = 'illustrations';
  static const customTemplate = 'customTemplate';
  static const count = 'count';
  static const difficulty = 'difficulty';
  static const images = 'images';
  static const questionTypes = 'questionTypes';
  static const orientation = 'orientation';
  static const detail = 'detail';

  // Valores.
  static const detailed = 'detailed';
  static const presenter = 'presenter';
  static const auto = 'auto';
  static const short = 'short';
  static const standard = 'standard';
  static const interactive = 'interactive';
  static const document = 'document';
  static const learningSummary = 'learning_summary';
  static const studyGuide = 'study_guide';
  static const briefing = 'briefing';
  static const glossary = 'glossary';
  static const custom = 'custom';
  static const fewer = 'fewer';
  static const more = 'more';
  static const easy = 'easy';
  static const medium = 'medium';
  static const hard = 'hard';
  static const single = 'single';
  static const multiple = 'multiple';
  static const fillBlank = 'fill_blank';
  static const shortAnswer = 'short_answer';
  static const landscape = 'landscape';
  static const portrait = 'portrait';
  static const square = 'square';
  static const concise = 'concise';
}

/// El de fábrica de [kind]: con él la pantalla funciona de punta a punta
/// antes de que llegue el tipo de verdad (la ola 3 le suma su visor, o lo
/// cambia entero).
CreationKindSpec defaultCreationKindSpec(StudyCreationKind kind) =>
    switch (kind) {
      StudyCreationKind.fullText => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetFullText,
        fields: const {CreationField.sources},
      ),
      StudyCreationKind.summary => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetSummary,
        fields: const {CreationField.sources},
      ),
      StudyCreationKind.synthesis => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetSynthesis,
        fields: const {CreationField.sources},
      ),
      StudyCreationKind.presentation => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetPresentation,
        fields: const {
          CreationField.language,
          CreationField.sources,
          CreationField.description,
        },
        descriptionHint: (l) => l.f43StudioDescribeHint,
        options: [
          CreationChoiceOption(
            key: CreationOptionValues.format,
            label: (l) => l.f43StudioOptFormat,
            initial: CreationOptionValues.detailed,
            choices: [
              CreationChoice(
                CreationOptionValues.detailed,
                (l) => l.f43StudioOptDetailed,
              ),
              CreationChoice(
                CreationOptionValues.presenter,
                (l) => l.f43StudioOptPresenter,
              ),
            ],
          ),
          CreationChoiceOption(
            key: CreationOptionValues.template,
            label: (l) => l.f43StudioOptTemplate,
            initial: CreationOptionValues.auto,
            asMenu: true,
            choices: [
              CreationChoice(
                CreationOptionValues.auto,
                (l) => l.f43StudioOptTemplateAuto,
              ),
              for (final id in DeckTemplateId.values)
                CreationChoice(id.name, (l) => l.deckTemplate(id)),
            ],
          ),
          CreationChoiceOption(
            key: CreationOptionValues.length,
            label: (l) => l.f43StudioOptDuration,
            initial: CreationOptionValues.standard,
            choices: [
              CreationChoice(
                CreationOptionValues.short,
                (l) => l.f43StudioOptShort,
              ),
              CreationChoice(
                CreationOptionValues.standard,
                (l) => l.f43StudioOptStandardF,
              ),
            ],
          ),
          CreationToggleOption(
            key: CreationOptionValues.illustrations,
            label: (l) => l.f43StudioOptIllustrations,
            hint: (l) => l.f43StudioOptIllustrationsHint,
            illustrations: true,
          ),
        ],
        // Una corta son unas ocho diapositivas y una estándar unas catorce;
        // las notas del presentador escriben casi otro tanto.
        expectedOutputTokens: (o) =>
            (o[CreationOptionValues.length] == CreationOptionValues.short
                ? 1800
                : 3500) +
            (o[CreationOptionValues.format] == CreationOptionValues.presenter
                ? 1200
                : 0),
        // Una por diapositiva que la pide: más o menos la mitad.
        illustrations: (o) =>
            o[CreationOptionValues.length] == CreationOptionValues.short
            ? 4
            : 7,
      ),
      StudyCreationKind.mindMap => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetMindMap,
        fields: const {
          CreationField.language,
          CreationField.sources,
          CreationField.topic,
        },
        expectedOutputTokens: (_) => 1500,
      ),
      StudyCreationKind.report => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetReport,
        tileLabel: (l) => l.f43StudioTileReports,
        options: [
          CreationChoiceOption(
            key: CreationOptionValues.format,
            label: (l) => l.f43StudioOptFormat,
            initial: CreationOptionValues.interactive,
            choices: [
              CreationChoice(
                CreationOptionValues.interactive,
                (l) => l.f43StudioOptInteractive,
              ),
              CreationChoice(
                CreationOptionValues.document,
                (l) => l.f43StudioOptDocument,
              ),
            ],
          ),
          CreationChoiceOption(
            key: CreationOptionValues.template,
            label: (l) => l.f43StudioOptTemplate,
            initial: CreationOptionValues.learningSummary,
            choices: [
              CreationChoice(
                CreationOptionValues.learningSummary,
                (l) => l.f43StudioOptLearningSummary,
              ),
              CreationChoice(
                CreationOptionValues.studyGuide,
                (l) => l.f43StudioOptStudyGuide,
              ),
              CreationChoice(
                CreationOptionValues.briefing,
                (l) => l.f43StudioOptBriefing,
              ),
              CreationChoice(
                CreationOptionValues.glossary,
                (l) => l.f43StudioOptGlossary,
              ),
              CreationChoice(
                CreationOptionValues.custom,
                (l) => '✎ ${l.f43StudioOptOwnTemplate}',
              ),
            ],
          ),
          CreationTextOption(
            key: CreationOptionValues.customTemplate,
            label: (l) => l.f43StudioOptOwnTemplate,
            hint: (l) => l.f43StudioOptOwnTemplateHint,
            visibleWhen: (o) =>
                o[CreationOptionValues.template] == CreationOptionValues.custom,
          ),
        ],
        expectedOutputTokens: (o) =>
            o[CreationOptionValues.format] == CreationOptionValues.interactive
            ? 4000
            : 3000,
      ),
      StudyCreationKind.flashcards => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetFlashcards,
        fields: const {
          CreationField.language,
          CreationField.sources,
          CreationField.topic,
        },
        options: [
          _count(),
          _difficulty(),
          CreationToggleOption(
            key: CreationOptionValues.images,
            label: (l) => l.f43StudioOptImages,
            hint: (l) => l.f43StudioOptImagesHint,
          ),
        ],
        expectedOutputTokens: (o) => _byCount(o, 1200, 2400, 4000),
      ),
      StudyCreationKind.quiz => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetQuiz,
        fields: const {
          CreationField.language,
          CreationField.sources,
          CreationField.topic,
        },
        options: [
          _count(),
          _difficulty(),
          CreationToggleOption(
            key: CreationOptionValues.images,
            label: (l) => l.f43StudioOptImages,
            hint: (l) => l.f43StudioOptImagesHint,
          ),
          CreationMultiChoiceOption(
            key: CreationOptionValues.questionTypes,
            label: (l) => l.f43StudioOptQuestionTypes,
            initial: const [CreationOptionValues.single],
            choices: [
              CreationChoice(
                CreationOptionValues.single,
                (l) => l.f43StudioOptSingle,
              ),
              CreationChoice(
                CreationOptionValues.multiple,
                (l) => l.f43StudioOptMultiple,
              ),
              CreationChoice(
                CreationOptionValues.fillBlank,
                (l) => l.f43StudioOptFillBlank,
              ),
              CreationChoice(
                CreationOptionValues.shortAnswer,
                (l) => l.f43StudioOptShortAnswer,
              ),
            ],
          ),
        ],
        // Cada pregunta trae la explicación de cada opción: escribe más que
        // una tarjeta.
        expectedOutputTokens: (o) => _byCount(o, 1500, 3000, 5000),
      ),
      StudyCreationKind.infographic => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetInfographic,
        fields: const {
          CreationField.language,
          CreationField.sources,
          CreationField.description,
        },
        descriptionHint: (l) => l.f43StudioDescribeHintInfographic,
        options: [
          CreationChoiceOption(
            key: CreationOptionValues.orientation,
            label: (l) => l.f43StudioOptOrientation,
            initial: CreationOptionValues.portrait,
            choices: [
              CreationChoice(
                CreationOptionValues.landscape,
                (l) => l.f43StudioOptLandscape,
              ),
              CreationChoice(
                CreationOptionValues.portrait,
                (l) => l.f43StudioOptPortrait,
              ),
              CreationChoice(
                CreationOptionValues.square,
                (l) => l.f43StudioOptSquare,
              ),
            ],
          ),
          CreationChoiceOption(
            key: CreationOptionValues.detail,
            label: (l) => l.f43StudioOptDetail,
            initial: CreationOptionValues.standard,
            choices: [
              CreationChoice(
                CreationOptionValues.concise,
                (l) => l.f43StudioOptConcise,
              ),
              CreationChoice(
                CreationOptionValues.standard,
                (l) => l.f43StudioOptStandardF,
              ),
              CreationChoice(
                CreationOptionValues.detailed,
                (l) => l.f43StudioOptDetailedM,
              ),
            ],
          ),
          CreationToggleOption(
            key: CreationOptionValues.illustrations,
            label: (l) => l.f43StudioOptIllustrations,
            hint: (l) => l.f43StudioOptIllustrationsHint,
            illustrations: true,
          ),
        ],
        expectedOutputTokens: (o) => _byDetail(o, 1000, 1600, 2400),
        // Una ilustración por bloque.
        illustrations: (o) => _byDetail(o, 3, 5, 7),
      ),
      StudyCreationKind.dataTable => CreationKindSpec(
        kind: kind,
        accent: _accents[kind]!,
        sheetTitle: (l) => l.f43StudioSheetDataTable,
        fields: const {
          CreationField.language,
          CreationField.sources,
          CreationField.description,
        },
        descriptionHint: (l) => l.f43StudioDescribeHintTable,
        expectedOutputTokens: (_) => 2500,
      ),
      StudyCreationKind.podcast => podcastKindSpecBase(_accents[kind]!),
    };

/// Un color vivo por tipo, como los íconos del Studio de NotebookLM: el tono
/// para los temas claros y su par luminoso para los oscuros.
const _accents = <StudyCreationKind, CreationAccent>{
  StudyCreationKind.fullText: CreationAccent(
    light: Color(0xFF1A73E8),
    dark: Color(0xFF8AB4F8),
  ),
  StudyCreationKind.summary: CreationAccent(
    light: Color(0xFF00897B),
    dark: Color(0xFF6FD8C8),
  ),
  StudyCreationKind.synthesis: CreationAccent(
    light: Color(0xFF5E35B1),
    dark: Color(0xFFB9A2F0),
  ),
  StudyCreationKind.presentation: CreationAccent(
    light: Color(0xFFD95F00),
    dark: Color(0xFFFFB06B),
  ),
  StudyCreationKind.mindMap: CreationAccent(
    light: Color(0xFFD81B60),
    dark: Color(0xFFF48FB1),
  ),
  StudyCreationKind.report: CreationAccent(
    light: Color(0xFFA15C00),
    dark: Color(0xFFFDD663),
  ),
  StudyCreationKind.flashcards: CreationAccent(
    light: Color(0xFFD93025),
    dark: Color(0xFFF28B82),
  ),
  StudyCreationKind.quiz: CreationAccent(
    light: Color(0xFF188038),
    dark: Color(0xFF81C995),
  ),
  StudyCreationKind.infographic: CreationAccent(
    light: Color(0xFF9334E6),
    dark: Color(0xFFD7AEFB),
  ),
  StudyCreationKind.dataTable: CreationAccent(
    light: Color(0xFF0B7285),
    dark: Color(0xFF78D9EC),
  ),
  StudyCreationKind.podcast: CreationAccent(
    light: Color(0xFF3949AB),
    dark: Color(0xFFA4B0FF),
  ),
};

CreationChoiceOption _count() => CreationChoiceOption(
  key: CreationOptionValues.count,
  label: (l) => l.f43StudioOptCount,
  initial: CreationOptionValues.standard,
  choices: [
    CreationChoice(CreationOptionValues.fewer, (l) => l.f43StudioOptFewer),
    CreationChoice(
      CreationOptionValues.standard,
      (l) => l.f43StudioOptStandardF,
    ),
    CreationChoice(CreationOptionValues.more, (l) => l.f43StudioOptMore),
  ],
);

CreationChoiceOption _difficulty() => CreationChoiceOption(
  key: CreationOptionValues.difficulty,
  label: (l) => l.f43StudioOptDifficulty,
  initial: CreationOptionValues.medium,
  choices: [
    CreationChoice(CreationOptionValues.easy, (l) => l.f43StudioOptEasy),
    CreationChoice(CreationOptionValues.medium, (l) => l.f43StudioOptMedium),
    CreationChoice(CreationOptionValues.hard, (l) => l.f43StudioOptHard),
  ],
);

int _byCount(Map<String, Object?> o, int fewer, int standard, int more) =>
    switch (o[CreationOptionValues.count]) {
      CreationOptionValues.fewer => fewer,
      CreationOptionValues.more => more,
      _ => standard,
    };

int _byDetail(Map<String, Object?> o, int concise, int standard, int more) =>
    switch (o[CreationOptionValues.detail]) {
      CreationOptionValues.concise => concise,
      CreationOptionValues.detailed => more,
      _ => standard,
    };
