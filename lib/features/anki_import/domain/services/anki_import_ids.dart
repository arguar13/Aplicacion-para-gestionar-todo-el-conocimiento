import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:uuid/uuid.dart';

/// Los identificadores de lo que se trae de Anki (F31, decisión 73).
///
/// **Son deterministas** (UUID v5 sobre el `guid` de la nota de Anki): traer
/// dos veces el mismo `.apkg` da los mismos `id`, y la base —que ya exige `id`
/// únicos— reconoce lo que ya está. Así la procedencia de lo importado no
/// necesita una columna aparte (el esquema v39 está cerrado): *es* el
/// identificador. Dos dispositivos que traen el mismo paquete también producen
/// las mismas filas, que la fusión de bóvedas junta en vez de duplicar.
///
/// El espacio de nombres propio evita que un `guid` de Anki choque con otra
/// cosa que alguna vez se identifique igual.
const Uuid _uuid = Uuid();
const String _namespace = '6f4a5c1e-2b7d-4e0a-9d3c-1a8b7e5f4c20';

/// El `id` de la tarjeta de Sinapsis para la tarjeta [card] de Anki: la nota
/// (`guid`) y cuál de sus plantillas es (`ord`: la ida y la vuelta, o el número
/// de hueco menos uno).
String ankiImportedCardId(AnkiImportedCard card) =>
    ankiImportedCardIdOf(card.guid, card.ord);

String ankiImportedCardIdOf(String guid, int ord) =>
    _uuid.v5(_namespace, 'card|$guid|$ord');

/// El `group_id` de las hermanas de una nota (las dos direcciones, los huecos
/// de un mismo texto).
String ankiImportedGroupId(String guid) => _uuid.v5(_namespace, 'group|$guid');

/// El `id` del elemento que recibe las tarjetas del mazo [deckKey] (`''` para
/// el elemento único).
String ankiImportedItemId(String deckKey) =>
    _uuid.v5(_namespace, 'item|$deckKey');
