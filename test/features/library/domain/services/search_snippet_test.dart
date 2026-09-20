import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/library/domain/entities/search_citation.dart';
import 'package:sinapsis/features/library/domain/services/search_snippet.dart';

/// El fragmento de un resultado de búsqueda coincide como el índice: sin
/// distinguir mayúsculas ni acentos, y cada palabra buscada como prefijo.
void main() {
  /// Los tramos resaltados del fragmento, para no escribir los caracteres de
  /// marca en cada expectativa.
  List<String> highlighted(String snippet) => SearchCitation(
    itemId: 'i',
    chunkId: 'c',
    snippet: snippet,
    charStart: 0,
    charEnd: 0,
  ).parts.where((p) => p.highlighted).map((p) => p.text).toList();

  String plain(String snippet) =>
      snippet.replaceAll(kSnippetOpen, '').replaceAll(kSnippetClose, '');

  test('marca la palabra buscada', () {
    final snippet = buildSnippet('Hablamos del paradigma de Kuhn.', [
      'paradigma',
    ]);

    expect(highlighted(snippet), ['paradigma']);
    expect(plain(snippet), 'Hablamos del paradigma de Kuhn.');
  });

  test('no distingue mayúsculas ni acentos', () {
    expect(highlighted(buildSnippet('La REPÚBLICA romana', ['republica'])), [
      'REPÚBLICA',
    ]);
    expect(highlighted(buildSnippet('la republica romana', ['REPÚBLICA'])), [
      'republica',
    ]);
  });

  test('la ñ y la ç se pliegan, como en el tokenizador del índice', () {
    expect(highlighted(buildSnippet('Un año difícil', ['ano'])), ['año']);
    expect(highlighted(buildSnippet('La canción', ['cancion'])), ['canción']);
  });

  test('una palabra buscada es un PREFIJO: marca la palabra entera', () {
    expect(highlighted(buildSnippet('Los paradigmas cambian', ['paradig'])), [
      'paradigmas',
    ]);
  });

  test('no marca una palabra que solo la contiene por dentro', () {
    expect(highlighted(buildSnippet('Un paradigma', ['grama'])), isEmpty);
  });

  test('marca todas las coincidencias de todas las palabras', () {
    final snippet = buildSnippet('Kuhn habló del paradigma; Kuhn insistió.', [
      'kuhn',
      'paradigma',
    ]);

    expect(highlighted(snippet), ['Kuhn', 'paradigma', 'Kuhn']);
    expect(plain(snippet), 'Kuhn habló del paradigma; Kuhn insistió.');
  });

  test('en un texto largo recorta alrededor de la primera coincidencia, con '
      'puntos suspensivos a los lados', () {
    final text =
        '${List.filled(60, 'relleno').join(' ')} paradigma '
        '${List.filled(60, 'relleno').join(' ')}';

    final snippet = buildSnippet(text, ['paradigma']);

    expect(highlighted(snippet), ['paradigma']);
    expect(snippet.startsWith('…'), isTrue);
    expect(snippet.endsWith('…'), isTrue);
    expect(plain(snippet).length, lessThan(text.length ~/ 2));
    // Cortó en límites de palabra: no dejó "relle" ni "leno".
    expect(plain(snippet), isNot(contains('relle ')));
  });

  test('si la coincidencia está al principio, no pone puntos antes', () {
    final snippet = buildSnippet(
      'Paradigma. ${List.filled(60, 'relleno').join(' ')}',
      ['paradigma'],
    );

    expect(snippet.startsWith('…'), isFalse);
    expect(snippet.endsWith('…'), isTrue);
  });

  test(
    'sin ninguna coincidencia devuelve el comienzo del texto, sin marcas',
    () {
      final snippet = buildSnippet('Un texto que no menciona nada.', ['kuhn']);

      expect(highlighted(snippet), isEmpty);
      expect(plain(snippet), 'Un texto que no menciona nada.');
    },
  );

  test('ignora palabras vacías y un texto vacío no falla', () {
    expect(buildSnippet('', ['algo']), '');
    expect(highlighted(buildSnippet('hola mundo', ['', '  ', 'mundo'])), [
      'mundo',
    ]);
  });
}
