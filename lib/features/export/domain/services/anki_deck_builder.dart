import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/flashcard.dart';

/// Una tarjeta, ya con su subdeck resuelto (F17, D1/D2).
///
/// Separado de [Flashcard] a propósito: el builder arma el `.apkg` sin tocar
/// la base ni el árbol de Temas —eso lo resuelve quien llama, con
/// `ankiDeckPathOf`—, así que sigue siendo puro y se puede probar con
/// `flutter test` sin bindings.
class AnkiCardExport {
  const AnkiCardExport({
    required this.card,
    required this.deckPath,
    required this.answer,
    this.provenance,
    this.distractors = const [],
  });

  final Flashcard card;

  /// El subdeck completo, de la raíz a la hoja, separado por `::`
  /// —«Sinapsis::Historia::Roma::República»—.
  final String deckPath;

  /// La respuesta a mostrar (F20): `card.back` para `freeRecall`/
  /// `trueFalse`; para `multipleChoice`, `card.back` queda vacío
  /// (`FlashcardRepositoryImpl.createMultipleChoice`) y esto es el
  /// contenido de la opción marcada correcta. Quien arma [AnkiCardExport]
  /// resuelve cuál usar, así el builder no necesita saber nada de
  /// `flashcard_options`.
  final String answer;

  /// Las opciones incorrectas reales de una tarjeta `multipleChoice`, en el
  /// orden guardado —nunca la correcta, esa ya está en [answer]—. Vacío
  /// para cualquier otra forma.
  final List<String> distractors;

  /// La cita de la fuente, ya armada como texto plano por quien llama —con
  /// `FragmentLocatorResolver`/`citationSourceOf` y el estilo por defecto—,
  /// para el reverso de la tarjeta. `null` sin fuente citable (una nota
  /// manual, una tarjeta escrita a mano sin fuente) o sin nada que decir.
  final String? provenance;
}

/// Arma un mazo de Anki (`.apkg`) a partir de las tarjetas de la bóveda.
///
/// Existe como interfaz por la misma razón que el resto de los servicios de
/// exportación: quien arma el paquete de verdad pasa por un archivo de
/// trabajo temporal (ver `AnkiPackageBuilder`), y una interfaz deja
/// reemplazarlo en las pruebas que no necesitan ese detalle.
// ignore: one_member_abstracts
abstract interface class AnkiDeckBuilder {
  /// El `.apkg` completo, listo para guardar o compartir: un `.zip` con la
  /// base de datos SQLite del mazo adentro, en el formato que Anki importa.
  /// Un subdeck nuevo por cada [AnkiCardExport.deckPath] distinto entre
  /// [cards].
  Future<Uint8List> build(List<AnkiCardExport> cards);
}
