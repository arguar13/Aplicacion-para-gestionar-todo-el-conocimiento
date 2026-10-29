import 'dart:async';
import 'dart:math' as math;

import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_json.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_schema_prompt.dart';
import 'package:sinapsis/features/creations/presentation_kind/data/creation_illustration_files.dart';
import 'package:sinapsis/features/creations/presentation_kind/data/deck_illustrator.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_prompts.dart';

/// Lo que devolvió la IA, ya leído: el mazo y la plantilla que sugirió.
typedef WrittenDeck = ({SlideDeck deck, DeckTemplateId? template});

/// Quien genera una Presentación (F43, paso 11).
///
/// 1. **Escribe el mazo** con el modelo elegido, por `writeStructured` y el
///    esquema de `slideDeckJsonSchemaPrompt`: la IA elige el diseño de cada
///    diapositiva; «Del presentador» suma lo que hay que decir; la duración
///    pone cuántas; la descripción, el enfoque. Lo largo va por partes: cada
///    parte da sus diapositivas y el último paso arma el relato, de la
///    portada al cierre.
/// 2. **Dibuja las ilustraciones**, si se pidieron (`DeckIllustrator`): con
///    la cuenta elegida en «Con tu IA actual» y la pista de estilo de la
///    plantilla, como mucho las que se avisaron. Una que no sale no tumba la
///    presentación: queda su lugar dibujado y su porqué.
///
/// El avance va de la escritura (hasta 0,7 con ilustraciones) a cada
/// ilustración; cancelar corta en cualquiera de los dos.
class PresentationGenerator extends CreationGenerator {
  PresentationGenerator({
    required DeckIllustrator Function() illustrator,
    required CreationIllustrationFiles Function() files,
  }) : _illustrator = illustrator,
       _files = files;

  final DeckIllustrator Function() _illustrator;
  final CreationIllustrationFiles Function() _files;

  /// Hasta dónde llega el avance al terminar de escribir, si después se
  /// dibuja.
  static const writingShare = 0.7;

  /// Lo que ocupan la instrucción, el esquema de doce diseños con sus íconos
  /// y lo que eligió la persona: bastante más que lo común.
  static const instructionTokens = 1800;

  /// El tope de lo que escribe cada parte, por partes.
  static const partOutputTokens = 1800;

  @override
  StudyCreationKind get kind => StudyCreationKind.presentation;

  @override
  int maxOutputTokens(CreationJob job) {
    final expected = PresentationOptions.of(job.options).expectedOutputTokens;
    return math.min(8192, math.max(2400, (expected * 1.5).round()));
  }

  @override
  CreationBudget budgetFor(CreationJob job, int contextTokens) =>
      CreationBudget(
        contextTokens: contextTokens,
        reservedOutputTokens: maxOutputTokens(job),
        instructionTokens: instructionTokens,
      );

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) async {
    final options = PresentationOptions.of(job.options);
    final illustrate = options.illustrations;
    final share = illustrate ? writingShare : 1.0;

    final written = await writer.writeStructured(
      StructuredRequest<WrittenDeck>(
        task: PresentationPrompts.task(options),
        schema: slideDeckJsonSchemaPrompt,
        material: material,
        budget: budgetFor(job, writer.contextTokens),
        maxOutputTokens: maxOutputTokens(job),
        parse: (json) => readWrittenDeck(json, minSlides: 3),
        parsePartial: (json) => readWrittenDeck(json, minSlides: 1),
        partTask: PresentationPrompts.partTask(options),
        mergeTask: PresentationPrompts.mergeTask(options),
        partMaxOutputTokens: math.min(maxOutputTokens(job), partOutputTokens),
        languageCode: job.languageCode,
        guidance: options.description.isEmpty ? null : options.description,
        cancellation: job.cancellation,
        onProgress: (value, step) => progress(value * share, step),
      ),
    );
    _throwIfCancelled(job);

    final deck = finishDeck(written.deck, format: options.format);
    var content = PresentationContent(
      deck: deck,
      templateHint: written.template,
    );

    if (illustrate) {
      final wanted = illustrationOrder(deck).take(options.maxIllustrations);
      final template = options.template ?? written.template;
      final run = await _illustrator().illustrate(
        creationId: job.creation.id,
        content: content,
        slides: wanted.toList(),
        styleHint: options.illustrationStyle.hintFor(
          template ?? DeckTemplateId.editorial,
        ),
        accountId: options.imageAccountId,
        cancellation: job.cancellation,
        onProgress: (done, total) => progress(
          share + (1 - share) * (total == 0 ? 1 : done / total),
          CreationStep.illustrating,
        ),
      );
      content = run.content;
    }
    _throwIfCancelled(job);

    // Lo de una generación anterior que ya no se usa («Volver a generar»):
    // sus ilustraciones se van con ella.
    final previous = PresentationContent.decode(job.creation.content).files;
    final files = _files();
    for (final path in previous.difference(content.files)) {
      unawaited(files.delete(job.creation.id, path));
    }

    return CreationOutput(title: deck.title, content: content.encode());
  }

  void _throwIfCancelled(CreationJob job) {
    if (job.cancellation.isCancelled) throw const CreationCancelledException();
  }

  /// El mazo de [json] y la plantilla sugerida, o [FormatException] —lo que
  /// se le dice a la IA al pedirle que lo corrija— si no hay al menos
  /// [minSlides] diapositivas legibles.
  static WrittenDeck readWrittenDeck(Object? json, {required int minSlides}) {
    final deck = SlideDeckJson.tryDecode(json);
    if (deck == null) {
      throw const FormatException(
        'no hay ninguna diapositiva legible: falta "slides", una lista de '
        'diapositivas con su "layout"',
      );
    }
    if (deck.slides.length < minSlides) {
      throw FormatException(
        'el mazo tiene ${deck.slides.length} diapositivas legibles y hacen '
        'falta al menos $minSlides',
      );
    }
    DeckTemplateId? template;
    if (json is Map) {
      for (final key in const ['template', 'plantilla', 'theme']) {
        final raw = json[key];
        template = PresentationOptions.templateOf(
          raw is String ? raw.trim().toLowerCase().replaceAll('-', '_') : raw,
        );
        if (template != null) break;
      }
    }
    return (deck: deck, template: template);
  }

  /// El mazo como se guarda: con el formato elegido —la IA a veces dice otro—
  /// y con portada, que es lo que se ve en la miniatura, en «Lo creado» y en
  /// la galería de plantillas. Una portada que faltó se arma con el título.
  static SlideDeck finishDeck(SlideDeck deck, {required DeckFormat format}) {
    final slides = [...deck.slides];
    if (slides.isEmpty || slides.first is! CoverSlide) {
      slides.insert(0, Slide.cover(title: deck.title, subtitle: deck.subtitle));
    }
    return deck.copyWith(
      format: format,
      slides: slides.take(SlideLimits.slides).toList(),
    );
  }

  /// En qué orden se dibujan las que quieren ilustración: la portada
  /// primero —es la que más se ve—, después las de «imagen con texto», que
  /// se arman alrededor de la suya, y las demás en el orden del mazo. Así,
  /// con el tope, quedan las que más lucen.
  static List<int> illustrationOrder(SlideDeck deck) {
    int rank(Slide slide) => switch (slide.layout) {
      SlideLayout.cover => 0,
      SlideLayout.imageText => 1,
      _ => 2,
    };
    final wanted = [
      for (final (i, slide) in deck.slides.indexed)
        if (slide.needsIllustration) i,
    ];
    final ordered = [...wanted]
      ..sort((a, b) {
        final byRank = rank(deck.slides[a]).compareTo(rank(deck.slides[b]));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    return ordered;
  }
}
