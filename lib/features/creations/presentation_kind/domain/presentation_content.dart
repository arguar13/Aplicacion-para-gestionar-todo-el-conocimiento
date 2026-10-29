import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_json.dart';

/// Una ilustración que se pidió y no salió: en qué diapositiva y por qué.
@immutable
class IllustrationMiss {
  const IllustrationMiss({required this.slide, required this.failure});

  /// La posición de la diapositiva, desde 0.
  final int slide;
  final ImageFailure failure;

  @override
  bool operator ==(Object other) =>
      other is IllustrationMiss &&
      other.slide == slide &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(slide, failure);

  @override
  String toString() => 'IllustrationMiss($slide, ${failure.name})';
}

/// Lo que se guarda de una presentación en «Lo creado» (F43, paso 11): el
/// mazo que escribió la IA y lo que pasó con sus ilustraciones. **Nunca el
/// diseño** (decisión G): ese va en las opciones (`presentationDesignOf`),
/// así cambiar la plantilla no toca nada de esto.
///
/// Es el JSON de `SlideDeckJson.encode` —la forma de
/// `slideDeckJsonSchemaPrompt`— con tres claves más:
///
/// - `template_hint`: la plantilla que sugirió la IA para «Automática»;
/// - `illustration_misses`: las ilustraciones que no salieron, con su porqué
///   (`ImageFailure.name`), para que el visor lo diga;
/// - `illustration_account`: el nombre de la cuenta que dibujó o lo intentó,
///   para decir «tu cuenta Personal de Gemini no tiene facturación».
///
/// Las ilustraciones hechas están en `Slide.illustrationRef`: la ruta del
/// archivo en el almacén de la app (`CreationIllustrationFiles`).
@immutable
class PresentationContent {
  const PresentationContent({
    required this.deck,
    this.templateHint,
    this.misses = const [],
    this.illustrationAccount,
  });

  /// Lo guardado en [source] (el texto de la columna), con tolerancia: sin
  /// nada legible, un mazo vacío.
  factory PresentationContent.decode(String? source) {
    Object? json;
    if (source != null && source.trim().isNotEmpty) {
      try {
        json = jsonDecode(source);
      } on FormatException {
        json = source;
      }
    }
    final deck = SlideDeckJson.decode(json);
    final map = json is Map ? json : const <Object?, Object?>{};
    final misses = <IllustrationMiss>[];
    final rawMisses = map['illustration_misses'];
    if (rawMisses is List) {
      for (final raw in rawMisses) {
        if (raw is! Map) continue;
        final slide = raw['slide'];
        final failure = _failureOf(raw['failure']);
        if (slide is! int || slide < 0 || slide >= deck.slides.length) {
          continue;
        }
        // Una que ya tiene la suya no falta: quedó de antes de completarla.
        if (deck.slides[slide].illustrationRef != null) continue;
        misses.add(IllustrationMiss(slide: slide, failure: failure));
      }
    }
    final account = map['illustration_account'];
    return PresentationContent(
      deck: deck,
      templateHint: DeckTemplateId.fromId(map['template_hint']),
      misses: misses,
      illustrationAccount: account is String && account.isNotEmpty
          ? account
          : null,
    );
  }

  /// La versión de este esquema (`StudyCreation.contentVersion`).
  static const int version = 1;

  final SlideDeck deck;
  final DeckTemplateId? templateHint;
  final List<IllustrationMiss> misses;
  final String? illustrationAccount;

  String encode() => jsonEncode({
    ...SlideDeckJson.encode(deck),
    if (templateHint != null) 'template_hint': templateHint!.id,
    if (misses.isNotEmpty)
      'illustration_misses': [
        for (final miss in misses)
          {'slide': miss.slide, 'failure': miss.failure.name},
      ],
    if (illustrationAccount != null)
      'illustration_account': illustrationAccount,
  });

  /// Las diapositivas que quieren una ilustración y no la tienen: las que
  /// fallaron, las que pasaron del tope y las de una presentación hecha sin
  /// ilustraciones. Es lo que ofrece «Completar ilustraciones».
  List<int> get missing => [
    for (final (i, slide) in deck.slides.indexed)
      if (slide.needsIllustration) i,
  ];

  /// Las rutas de las ilustraciones ya hechas.
  Set<String> get files => {
    for (final slide in deck.slides) ?slide.illustrationRef,
  };

  /// La falla de la diapositiva [slide], si la ilustración no salió.
  IllustrationMiss? missOf(int slide) {
    for (final miss in misses) {
      if (miss.slide == slide) return miss;
    }
    return null;
  }

  /// Con la ilustración [reference] en la diapositiva [slide] —ya no falta—.
  PresentationContent withIllustration(int slide, String reference) {
    final slides = [...deck.slides];
    slides[slide] = slides[slide].copyWith(illustrationRef: reference);
    return copyWith(
      deck: deck.copyWith(slides: slides),
      misses: [
        for (final miss in misses)
          if (miss.slide != slide) miss,
      ],
    );
  }

  PresentationContent copyWith({
    SlideDeck? deck,
    List<IllustrationMiss>? misses,
    String? illustrationAccount,
  }) => PresentationContent(
    deck: deck ?? this.deck,
    templateHint: templateHint,
    misses: misses ?? this.misses,
    illustrationAccount: illustrationAccount ?? this.illustrationAccount,
  );

  static ImageFailure _failureOf(Object? raw) {
    for (final failure in ImageFailure.values) {
      if (failure.name == raw) return failure;
    }
    return ImageFailure.unknown;
  }
}

extension SlideIllustrationNeeds on Slide {
  /// Si la IA pidió una ilustración para esta diapositiva y todavía no la
  /// tiene: en su lugar se ve la dibujada por la app.
  bool get needsIllustration =>
      illustrationRef == null && (illustrationPrompt?.isNotEmpty ?? false);
}
