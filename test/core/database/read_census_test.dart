import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El censo de lecturas (F11): todo archivo de `lib` que lee `item` nombra lo
/// que hace con lo que está en la papelera. Desde F15 vale también para quien
/// lee `source_reference` o `source_contributor`: una lista de «las obras de
/// este autor» que no pasa por `item` mostraría las que están en la papelera.
///
/// Un elemento borrado sigue en la base con `deleted_at`. Si una lectura nueva
/// se olvida de dejarlo afuera, el borrado deja de cumplirse en esa pantalla,
/// en silencio: el elemento se ve, se busca, se propone como duplicado. Esta
/// prueba recorre `lib` y falla si un archivo lee la tabla y no usa ninguno de
/// los ayudantes de `active_entries.dart` —o no está en la lista, con el
/// motivo—.
///
/// Es un censo por ARCHIVO, no por consulta: dice que hay una decisión tomada,
/// no que sea la correcta. Lo que cada pantalla hace de verdad lo prueba el
/// grupo «la papelera (F11)» de las pruebas de cada repositorio.
void main() {
  /// Los archivos que leen `item` sin dejar afuera lo borrado, con el motivo.
  const allowed = <String, String>{
    'lib/core/database/app_database.dart':
        'declara las tablas de la base: no lee nada',
    'lib/core/database/reference_reader.dart':
        'lee por identificador: quien lo llama ya decidió qué elementos son '
        'visibles —la Biblioteca y la consulta de la bibliografía dejan '
        'afuera la papelera— y este lector no lista nada por su cuenta',
    'lib/core/database/reference_triggers.dart':
        'los triggers miran el tipo de UN elemento, por su clave, antes de '
        'colgarle una referencia o una persona: vivo o en la papelera —una '
        'fusión escribe también lo de lo borrado—; no listan ni muestran nada',
    'lib/core/database/search_index.dart':
        'el índice de texto contiene TODOS los elementos, borrados o no: lo '
        'que se deja afuera es la consulta que lo usa (library_query_sql)',
    'lib/core/database/migrations/mirror_unmirrored_items.dart':
        'migración: opera sobre toda la base',
    'lib/core/database/migrations/backfill_chunks_v16.dart':
        'migración: opera sobre toda la base',
    'lib/core/database/migrations/repoint_item_references_v18.dart':
        'migración: opera sobre toda la base',
    'lib/features/vault/data/merge/derived_rebuild.dart':
        'rehace los chunks y los enlaces de lo que la fusión marcó, esté vivo '
        'o en la papelera: lo derivado de un elemento borrado se conserva '
        'coherente con su texto para cuando se restaure',
    'lib/features/vault/data/merge/merge_gates.dart':
        'las guardas miran `item` solo para saber si una forma de texto es de '
        'una fuente; no leen ningún elemento para mostrarlo',
    'lib/features/vault/data/merge/reference_merge.dart':
        'decide sobre la referencia de TODAS las fuentes que las dos bóvedas '
        'tienen, también las de la papelera: un elemento borrado conserva '
        'sus datos bibliográficos y lo que le llega de la copia',
    'lib/features/vault/data/merge/rendition_merge.dart':
        'la fusión decide sobre las formas de TODOS los elementos, también los '
        'de la papelera: un elemento borrado conserva su texto y lo que le '
        'llega de la copia',
    'lib/features/vault/data/merge/set_union_merge.dart':
        'solo comprueba que el elemento exista —vivo o en la papelera— antes '
        'de colgarle un vínculo, una tarjeta o una procedencia: no hay '
        'pantalla que lo muestre',
    'lib/features/vault/data/merge/vocabulary_merge.dart':
        'solo comprueba que el elemento exista —vivo o en la papelera— antes '
        'de asignarle un valor: la asignación de un elemento borrado se '
        'conserva para cuando se restaure',
    'lib/features/vault/data/merge/vault_merger.dart':
        'nombra la tabla solo para avisar que cambió: no lee ninguna fila',
    'lib/features/vault/data/merge/vault_merge_reader.dart':
        'la vista previa de una fusión cuenta TODOS los elementos de la copia, '
        'también los que están en su papelera: un elemento borrado viaja con '
        'su borrado, y no es una pantalla que se le muestre al usuario',
  };

  /// Lo que cuenta como «decidí qué hacer con lo borrado».
  final decisions = RegExp(
    r'\b(?:isActive|itemIsActive|trashedItemIds|kActiveItemSql|'
    r'activeItemSql|deletedAt|deleted_at)\b',
  );

  test('el detector reconoce una lectura de item y una decisión', () {
    expect(readsItem('await _db.select(_db.knowledgeEntries).get();'), isTrue);
    expect(readsItem('SELECT id FROM item WHERE x = 1'), isTrue);
    expect(readsItem('... JOIN item ON item.id = c.item_id'), isTrue);
    // Nombrando la base: la fusión lee `main.item` con otra adjuntada.
    expect(readsItem('SELECT 1 FROM main.item m WHERE m.id = 1'), isTrue);
    expect(readsItem('SELECT 1 FROM incoming.item i'), isFalse);
    expect(readsItem('await _db.select(_db.flashcards).get();'), isFalse);
    expect(readsItem('SELECT * FROM item_search WHERE x'), isFalse);
    expect(readsItem('SELECT * FROM item_property_values'), isFalse);
    // Las referencias y las personas de una obra (F15) cuelgan de un elemento:
    // leerlas sin pasar por él también deja la papelera sin decidir.
    expect(readsItem('await _db.select(_db.sourceReferences).get();'), isTrue);
    expect(readsItem('_db.select(_db.sourceContributors).join([j])'), isTrue);
    expect(readsItem('SELECT * FROM source_reference WHERE 1'), isTrue);
    expect(
      readsItem('SELECT 1 FROM x JOIN main.source_contributor c ON 1'),
      isTrue,
    );
    expect(readsItem('INSERT INTO source_reference_x VALUES (1)'), isFalse);
    expect(readsItem('// se lee _db.knowledgeEntries acá'), isFalse);
    expect(decisions.hasMatch('..where((e) => e.isActive)'), isTrue);
    expect(decisions.hasMatch('..where((e) => e.id.equals(id))'), isFalse);
  });

  test('todo archivo que lee item decide qué hace con lo que está en la '
      'papelera', () {
    final files = _dartFilesUnder('lib');
    expect(files.length, greaterThan(200));

    final readers = <String, String>{
      for (final file in files)
        if (readsItem(file.readAsStringSync()))
          _relative(file): _withoutComments(file.readAsStringSync()),
    };
    // El recorrido ve algo: hay lectores, y son varios.
    expect(readers.length, greaterThan(10));

    final undecided = {
      for (final entry in readers.entries)
        if (!decisions.hasMatch(entry.value)) entry.key,
    };

    expect(
      undecided.difference(allowed.keys.toSet()),
      isEmpty,
      reason:
          'Estos archivos leen item sin dejar afuera lo que está en la '
          'papelera (deleted_at): usar isActive / itemIsActive / '
          'kActiveItemSql de active_entries.dart, o agregarlos a la lista '
          'con el motivo.',
    );
    expect(
      allowed.keys.toSet().difference(readers.keys.toSet()),
      isEmpty,
      reason:
          'Estos archivos están en la lista de permitidos pero ya no leen '
          'item: quitarlos de la lista.',
    );
    // Y un permitido que sí decide tampoco tiene por qué estar en la lista.
    expect(
      allowed.keys.toSet().difference(undecided),
      isEmpty,
      reason:
          'Estos archivos están en la lista pero ya dejan afuera lo que está '
          'en la papelera: quitarlos de la lista.',
    );
  });
}

/// Si [source] lee `item` —o una tabla que cuelga de un elemento, como las
/// referencias y sus personas—: la tabla por su nombre en drift, o SQL crudo
/// (`FROM item`, `JOIN item`) —no `item_search` ni `item_property_values`—.
bool readsItem(String source) {
  final code = _withoutComments(source);
  return _tableGetter.hasMatch(code) || _rawSql.hasMatch(code);
}

final _tableGetter = RegExp(
  r'\b(?:knowledgeEntries|sourceReferences|sourceContributors)\b',
);

final _rawSql = RegExp(
  r'\b(?:FROM|JOIN)\s+(?:main\.)?'
  r'(?:item|source_reference|source_contributor)(?![\w])',
  caseSensitive: false,
);

/// Sin los comentarios: leer algo «en teoría» no es leerlo.
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?:^|\s)//[^\n]*'), '');

List<File> _dartFilesUnder(String directory) => [
  for (final entity in Directory(directory).listSync(recursive: true))
    if (entity is File &&
        entity.path.endsWith('.dart') &&
        !entity.path.endsWith('.g.dart') &&
        !entity.path.endsWith('.freezed.dart'))
      entity,
];

/// La ruta relativa a la raíz del proyecto, con `/` aunque sea Windows.
String _relative(File file) => file.path.replaceAll(r'\', '/');
