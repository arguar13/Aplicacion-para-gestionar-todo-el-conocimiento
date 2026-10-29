import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/flashcards/domain/study_item_json.dart';
import 'package:sinapsis/features/creations/flashcards/domain/study_items.dart';

/// Los topes de cada campo de una tarjeta: lo que la IA devuelva de más se
/// corta en la última palabra entera.
abstract final class DeckLimits {
  static const int cards = 60;
  static const int title = 120;
  static const int front = 400;
  static const int back = 900;
  static const int hint = 200;
  static const int prompt = 500;
  static const int icon = 40;
}

/// Una tarjeta del mazo de «Tarjetas didácticas» (F43, paso 8): la pregunta
/// y la respuesta de siempre, con su pista, de qué documento sale, su dibujo
/// y —si se sumó al repaso— cuál es su tarjeta en el documento procesado.
@immutable
class DeckCard implements StudyItem<DeckCard> {
  const DeckCard({
    required this.id,
    required this.front,
    required this.back,
    this.hint = '',
    this.sourceHint = '',
    this.documentId,
    this.icon,
    this.illustrationPrompt = '',
    this.illustrationRef,
    this.flashcardId,
  });

  /// Estable dentro del mazo (`c1`, `c2`…): lo que une la tarjeta con su
  /// ilustración y con su tarjeta de repaso aunque se barajen.
  final String id;
  final String front;
  final String back;
  final String hint;

  @override
  final String sourceHint;

  @override
  final String? documentId;

  /// Un nombre de ícono (`CreationIcons`), para el dibujo de la app.
  final String? icon;

  /// Lo que la IA propuso dibujar, en inglés; vacío si no.
  final String illustrationPrompt;

  /// Dónde está guardada su ilustración con IA (`CreationIllustrationStore`),
  /// si se pidió y salió.
  final String? illustrationRef;

  /// La tarjeta de repaso que la representa en su documento, si el mazo la
  /// sumó alguna vez.
  final String? flashcardId;

  @override
  String get fingerprint => flashcardRejectionFingerprint(front);

  @override
  DeckCard withDocument(String documentId) => copyWith(documentId: documentId);

  DeckCard copyWith({
    String? id,
    String? documentId,
    String? illustrationRef,
    String? flashcardId,
  }) => DeckCard(
    id: id ?? this.id,
    front: front,
    back: back,
    hint: hint,
    sourceHint: sourceHint,
    documentId: documentId ?? this.documentId,
    icon: icon,
    illustrationPrompt: illustrationPrompt,
    illustrationRef: illustrationRef ?? this.illustrationRef,
    flashcardId: flashcardId ?? this.flashcardId,
  );

  @override
  bool operator ==(Object other) =>
      other is DeckCard &&
      other.id == id &&
      other.front == front &&
      other.back == back &&
      other.hint == hint &&
      other.documentId == documentId &&
      other.icon == icon &&
      other.illustrationPrompt == illustrationPrompt &&
      other.illustrationRef == illustrationRef &&
      other.flashcardId == flashcardId;

  @override
  int get hashCode => Object.hash(
    id,
    front,
    back,
    hint,
    documentId,
    icon,
    illustrationPrompt,
    illustrationRef,
    flashcardId,
  );

  @override
  String toString() => 'DeckCard($id, $front)';
}

/// Un mazo de «Tarjetas didácticas» (F43, paso 8): lo que se guarda en el
/// contenido de la creación (decisión G: datos, nunca diseño).
@immutable
class FlashcardDeck {
  const FlashcardDeck({
    required this.title,
    required this.cards,
    this.inReview = false,
    this.illustrationFailure,
    this.illustrationAccount,
  });

  final String title;
  final List<DeckCard> cards;

  /// «Sumar a mi repaso»: si sus tarjetas están en «Para hoy».
  final bool inReview;

  /// Por qué no salieron las ilustraciones con IA, si se pidieron y alguna
  /// no salió; con qué cuenta.
  final ImageFailure? illustrationFailure;
  final String? illustrationAccount;

  bool get isEmpty => cards.isEmpty;

  FlashcardDeck copyWith({
    String? title,
    List<DeckCard>? cards,
    bool? inReview,
    ImageFailure? illustrationFailure,
    String? illustrationAccount,
  }) => FlashcardDeck(
    title: title ?? this.title,
    cards: cards ?? this.cards,
    inReview: inReview ?? this.inReview,
    illustrationFailure: illustrationFailure ?? this.illustrationFailure,
    illustrationAccount: illustrationAccount ?? this.illustrationAccount,
  );

  @override
  bool operator ==(Object other) =>
      other is FlashcardDeck &&
      other.title == title &&
      listEquals(other.cards, cards) &&
      other.inReview == inReview &&
      other.illustrationFailure == illustrationFailure &&
      other.illustrationAccount == illustrationAccount;

  @override
  int get hashCode => Object.hash(
    title,
    Object.hashAll(cards),
    inReview,
    illustrationFailure,
    illustrationAccount,
  );
}

/// El JSON de un mazo, en los dos sentidos (F43, decisión G).
///
/// [tryDecode] lee con tolerancia lo que devuelve la IA y lo guardado: las
/// claves en castellano o en inglés, en cualquier caja (`frente`, `front`,
/// `question`, `pregunta`…), las tarjetas sueltas en una lista o dentro de
/// `cards`/`tarjetas`, y una tarjeta como `[pregunta, respuesta]`. Una tarjeta
/// sin pregunta o sin respuesta no cuenta, ni la misma pregunta dos veces.
/// Nunca falla por un campo: devuelve `null` solo si no hay ninguna tarjeta.
abstract final class FlashcardDeckJson {
  static const _titleKeys = ['title', 'titulo', 'name', 'nombre'];
  static const _cardsKeys = ['cards', 'tarjetas', 'flashcards', 'items'];
  static const _frontKeys = [
    'front',
    'frente',
    'question',
    'pregunta',
    'term',
    'termino',
    'concepto',
    'anverso',
  ];
  static const _backKeys = [
    'back',
    'dorso',
    'answer',
    'respuesta',
    'definition',
    'definicion',
    'reverso',
  ];
  static const _hintKeys = ['hint', 'pista'];
  static const _sourceKeys = ['source', 'fuente', 'documento', 'document'];
  static const _iconKeys = ['icon', 'icono'];
  static const _promptKeys = [
    'illustration_prompt',
    'illustration',
    'ilustracion',
    'image_prompt',
    'imagen_descripcion',
  ];

  static FlashcardDeck? tryDecode(Object? source) {
    final json = source is String ? _decodeText(source) : source;
    final Map<String, Object?> deck;
    if (json is List) {
      deck = {'cards': json};
    } else if (studyJsonObject(json) case final map?) {
      deck = map;
    } else {
      return null;
    }
    final cards = <DeckCard>[];
    final seen = <String>{};
    final ids = <String>{};
    for (final raw in studyJsonList(deck, _cardsKeys)) {
      final card = _card(raw, cards.length);
      if (card == null || !seen.add(card.fingerprint)) continue;
      // Un id repetido —de un mazo tocado a mano— se renumera: une la tarjeta
      // con su ilustración y su repaso, no puede ser de dos.
      cards.add(ids.add(card.id) ? card : card.copyWith(id: _freeId(ids)));
      if (cards.length == DeckLimits.cards) break;
    }
    if (cards.isEmpty) return null;
    return FlashcardDeck(
      title: studyJsonText(deck, _titleKeys, max: DeckLimits.title),
      cards: cards,
      inReview: studyJsonBool(deck, const ['in_review', 'en_repaso']) ?? false,
      illustrationFailure: _failure(
        studyJsonText(deck, const ['illustration_failure']),
      ),
      illustrationAccount: _blankToNull(
        studyJsonText(deck, const ['illustration_account'], max: 80),
      ),
    );
  }

  /// Como [tryDecode], pero sin tarjetas devuelve un mazo vacío: para leer lo
  /// guardado, que ya pasó por acá.
  static FlashcardDeck decode(Object? source) =>
      tryDecode(source) ?? const FlashcardDeck(title: '', cards: []);

  /// Lo que pide `StructuredRequest.parse`: el mazo, o [FormatException] con
  /// el motivo que se le dice a la IA al pedirle que lo corrija.
  static FlashcardDeck parse(Object? json) =>
      tryDecode(json) ??
      (throw const FormatException(
        'No trae ninguna tarjeta con "frente" y "dorso".',
      ));

  static Map<String, Object?> encode(FlashcardDeck deck) => {
    'title': deck.title,
    'in_review': deck.inReview,
    if (deck.illustrationFailure case final failure?)
      'illustration_failure': failure.name,
    if (deck.illustrationAccount case final account?)
      'illustration_account': account,
    'cards': [
      for (final card in deck.cards)
        {
          'id': card.id,
          'front': card.front,
          'back': card.back,
          if (card.hint.isNotEmpty) 'hint': card.hint,
          if (card.documentId case final id?) 'document_id': id,
          if (card.icon case final icon?) 'icon': icon,
          if (card.illustrationPrompt.isNotEmpty)
            'illustration_prompt': card.illustrationPrompt,
          if (card.illustrationRef case final ref?) 'illustration_ref': ref,
          if (card.flashcardId case final id?) 'flashcard_id': id,
        },
    ],
  };

  static String encodeString(FlashcardDeck deck) => jsonEncode(encode(deck));

  static DeckCard? _card(Object? raw, int index) {
    final String front;
    final String back;
    var json = const <String, Object?>{};
    if (raw is List && raw.length >= 2) {
      front = clampStudyText('${raw[0] ?? ''}', DeckLimits.front);
      back = clampStudyText('${raw[1] ?? ''}', DeckLimits.back);
    } else if (studyJsonObject(raw) case final map?) {
      json = map;
      front = studyJsonText(json, _frontKeys, max: DeckLimits.front);
      back = studyJsonText(json, _backKeys, max: DeckLimits.back);
    } else {
      return null;
    }
    if (front.isEmpty || back.isEmpty) return null;
    final id = studyJsonText(json, const ['id'], max: 40);
    return DeckCard(
      id: id.isEmpty ? 'c${index + 1}' : id,
      front: front,
      back: back,
      hint: studyJsonText(json, _hintKeys, max: DeckLimits.hint),
      sourceHint: studyJsonText(json, _sourceKeys, max: DeckLimits.title),
      documentId: _blankToNull(
        studyJsonText(json, const ['document_id'], max: 200),
      ),
      icon: _blankToNull(studyJsonText(json, _iconKeys, max: DeckLimits.icon)),
      illustrationPrompt: studyJsonText(
        json,
        _promptKeys,
        max: DeckLimits.prompt,
      ),
      // Un mazo de antes guardaba la imagen adentro (`image`): no se lee,
      // y su lugar lleva el dibujo de la app.
      illustrationRef: _blankToNull(
        studyJsonText(json, const ['illustration_ref'], max: 1024),
      ),
      flashcardId: _blankToNull(
        studyJsonText(json, const ['flashcard_id'], max: 200),
      ),
    );
  }

  static String _freeId(Set<String> ids) {
    var n = ids.length + 1;
    while (!ids.add('c$n')) {
      n++;
    }
    return 'c$n';
  }

  static Object? _decodeText(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}

String? _blankToNull(String text) => text.isEmpty ? null : text;

ImageFailure? _failure(String name) {
  for (final failure in ImageFailure.values) {
    if (failure.name == name) return failure;
  }
  return null;
}

/// El [ImageFailure] guardado con [name], si lo hay: lo comparten el mazo y
/// el cuestionario.
ImageFailure? studyImageFailureNamed(String name) => _failure(name);
