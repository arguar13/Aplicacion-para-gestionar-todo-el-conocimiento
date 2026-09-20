import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El censo de lecturas (F11): todo archivo de `lib` que lee `item` nombra lo
/// que hace con lo que está en la papelera.
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
    'lib/core/database/search_index.dart':
        'el índice de texto contiene TODOS los elementos, borrados o no: lo '
        'que se deja afuera es la consulta que lo usa (library_query_sql)',
    'lib/core/database/migrations/mirror_unmirrored_items.dart':
        'migración: opera sobre toda la base',
    'lib/core/database/migrations/backfill_chunks_v16.dart':
        'migración: opera sobre toda la base',
    'lib/core/database/migrations/repoint_item_references_v18.dart':
        'migración: opera sobre toda la base',
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
    expect(readsItem('await _db.select(_db.flashcards).get();'), isFalse);
    expect(readsItem('SELECT * FROM item_search WHERE x'), isFalse);
    expect(readsItem('SELECT * FROM item_property_values'), isFalse);
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

/// Si [source] lee `item`: la tabla por su nombre en drift, o SQL crudo
/// (`FROM item`, `JOIN item`) —no `item_search` ni `item_property_values`—.
bool readsItem(String source) {
  final code = _withoutComments(source);
  return _tableGetter.hasMatch(code) || _rawSql.hasMatch(code);
}

final _tableGetter = RegExp(r'\bknowledgeEntries\b');

final _rawSql = RegExp(r'\b(?:FROM|JOIN)\s+item(?![\w])', caseSensitive: false);

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
