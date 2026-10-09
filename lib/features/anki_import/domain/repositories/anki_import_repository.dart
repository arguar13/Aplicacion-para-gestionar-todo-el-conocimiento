import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';

/// Lo que la importación de Anki necesita saber de la base y escribir en ella
/// (F31, decisión 73). Solo tarjetas: los elementos que las reciben se guardan
/// con `LibraryRepository`, como cualquier otro.
abstract interface class AnkiImportRepository {
  /// De [cards], cuáles ya están en la bóveda, como los `ankiCardId` de Anki.
  ///
  /// Una tarjeta ya está si existe la que tiene su `id` determinista
  /// (`ankiImportedCardId`: una importación anterior del mismo paquete), o si
  /// es una tarjeta que Sinapsis mismo exportó y sigue en la bóveda (el `guid`
  /// que escribe la exportación es el `id` de la tarjeta; en las de huecos,
  /// el de la primera del grupo).
  Future<Set<int>> alreadyImported(List<AnkiImportedCard> cards);

  /// De [itemIds], los que existen, y si cada uno está en la papelera.
  Future<Map<String, bool>> existingItems(List<String> itemIds);

  /// Escribe [cards] con su calendario. Una que ya existe (mismo `id`) se deja
  /// como está: nunca se pisa lo que la persona ya repasó. Devuelve cuántas se
  /// escribieron. Los elementos de [AnkiPlannedCard.itemId] tienen que existir.
  ///
  /// Se llama dentro de la transacción de la importación: si algo falla más
  /// adelante, esto se deshace con el resto.
  Future<int> insertCards(List<AnkiPlannedCard> cards);
}
