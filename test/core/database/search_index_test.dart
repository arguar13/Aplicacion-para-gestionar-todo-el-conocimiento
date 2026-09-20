import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// El índice de búsqueda se mantiene con triggers de SQLite, así que solo
/// SQLite puede confirmar que funciona. Estas pruebas corren contra una base
/// real en memoria.
///
/// Importa especialmente porque el modo de fallar de un índice desincronizado
/// es el peor que hay: la búsqueda no encuentra algo que sí está guardado, sin
/// error, sin aviso, y el usuario concluye que perdió su contenido.
void main() {
  group('sincronización por triggers', () {
    late AppDatabase db;
    final now = DateTime(2026, 9, 11, 10);
    var counter = 0;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      counter = 0;
    });

    tearDown(() => db.close());

    Future<String> newItem({
      required String title,
      String? subtitle,
      SourceKind kind = SourceKind.manualNote,
    }) async {
      final n = counter++;
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(id: 'src-$n', kind: kind, capturedAt: now),
          );
      await db
          .into(db.items)
          .insert(
            ItemsCompanion.insert(
              id: 'item-$n',
              title: title,
              sourceId: 'src-$n',
              processingState: ProcessingState.ready,
              createdAt: now,
              updatedAt: now,
              subtitle: Value(subtitle),
            ),
          );
      return 'item-$n';
    }

    /// Una forma de texto. Los elementos de estas pruebas son NOTAS salvo que
    /// se diga otra cosa: el cuerpo de este índice solo guarda el texto de una
    /// nota desde F10; el de una fuente lo indexa `chunk_search`.
    Future<String> addText(
      String itemId,
      String content, {
      RenditionKind kind = RenditionKind.plainText,
    }) async {
      final id = 'rend-${counter++}';
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: id,
              itemId: itemId,
              kind: kind,
              isPrimary: true,
              createdAt: now,
              content: Value(content),
            ),
          );
      return id;
    }

    Future<List<String>> search(String userInput) async {
      final query = buildSearchQuery(userInput);
      if (query.isEmpty) return [];
      final rows = await db
          .customSelect(
            'SELECT item_id FROM item_search WHERE item_search MATCH ? '
            'ORDER BY rank',
            variables: [Variable.withString(query)],
          )
          .get();
      return rows.map((r) => r.data['item_id']! as String).toList();
    }

    test('un elemento recién guardado ya es buscable por su título', () async {
      final id = await newItem(title: 'La estructura de las revoluciones');

      expect(await search('revoluciones'), [id]);
    });

    test('y por su subtítulo', () async {
      final id = await newItem(
        title: 'Un video',
        subtitle: 'Canal de divulgación científica',
      );

      expect(await search('divulgación'), [id]);
    });

    test(
      'agregar el texto de una nota lo vuelve buscable por su contenido',
      () async {
        final id = await newItem(title: 'Una nota sin título útil');
        expect(await search('paradigma'), isEmpty);

        await addText(id, 'Lo que define un paradigma es su capacidad...');

        expect(await search('paradigma'), [id]);
      },
    );

    test('el texto de una FUENTE no está en este índice: lo cubre el de '
        'chunks, con su minuto o su página', () async {
      final id = await newItem(
        title: 'Charla sin descripción',
        kind: SourceKind.youtube,
      );

      await addText(
        id,
        'Lo que define un paradigma es su capacidad...',
        kind: RenditionKind.markdown,
      );

      expect(await search('paradigma'), isEmpty);
      // El título sigue siendo suyo.
      expect(await search('charla'), [id]);
    });

    test('cambiar el título actualiza el índice', () async {
      final id = await newItem(title: 'Título provisorio');

      await (db.update(db.items)..where((i) => i.id.equals(id))).write(
        const ItemsCompanion(title: Value('Epistemología aplicada')),
      );

      expect(await search('provisorio'), isEmpty);
      expect(await search('epistemología'), [id]);
    });

    test('borrar el elemento lo saca del índice', () async {
      final id = await newItem(title: 'Algo que se va a borrar');
      await addText(id, 'con su transcripción y todo');

      await (db.delete(db.items)..where((i) => i.id.equals(id))).go();

      expect(await search('borrar'), isEmpty);
      expect(await search('transcripción'), isEmpty);
    });

    test('borrar una forma saca su texto del índice, pero el elemento sigue '
        'siendo buscable por su título', () async {
      final id = await newItem(title: 'Una charla grabada');
      final renditionId = await addText(id, 'mencionaba la termodinámica');

      await (db.delete(
        db.renditions,
      )..where((r) => r.id.equals(renditionId))).go();

      expect(await search('termodinámica'), isEmpty);
      expect(await search('charla'), [id]);
    });

    test('varias formas de bloques se buscan todas juntas', () async {
      final id = await newItem(title: 'Una nota en dos partes');
      await addText(id, 'la primera parte menciona enzimas');
      await addText(id, 'la segunda menciona catalizadores');

      expect(await search('enzimas'), [id]);
      expect(await search('catalizadores'), [id]);
    });

    test(
      'una forma que es archivo no aporta texto: una imagen se vuelve '
      'buscable recién cuando el OCR produce su propia transcripción',
      () async {
        final id = await newItem(title: 'Captura de pantalla');
        await db
            .into(db.renditions)
            .insert(
              RenditionsCompanion.insert(
                id: 'rend-img',
                itemId: id,
                kind: RenditionKind.image,
                isPrimary: true,
                createdAt: now,
                relativePath: const Value('imagenes/captura.png'),
              ),
            );

        // El nombre del archivo no es contenido y no debería encontrarse.
        expect(await search('captura.png'), isEmpty);
        // Pero el título sí.
        expect(await search('captura'), [id]);
      },
    );

    test('buscar sin acentos encuentra con acentos: nadie los escribe al '
        'buscar', () async {
      final id = await newItem(title: 'Filosofía de la técnica');

      expect(await search('filosofia'), [id]);
      expect(await search('tecnica'), [id]);
    });

    test(
      'encuentra por prefijo, para poder buscar mientras se escribe',
      () async {
        final id = await newItem(title: 'Neurociencia cognitiva');

        expect(await search('neuro'), [id]);
      },
    );

    test('dos palabras exigen las dos, no cualquiera de ellas', () async {
      final match = await newItem(title: 'Historia de la ciencia moderna');
      await newItem(title: 'Historia del arte');
      await newItem(title: 'Ciencia ficción');

      expect(await search('historia ciencia'), [match]);
    });
  });

  group('buildSearchQuery', () {
    test('envuelve cada término y le agrega prefijo', () {
      expect(buildSearchQuery('filosofia'), '"filosofia"*');
    });

    test('une varios términos', () {
      expect(buildSearchQuery('historia ciencia'), '"historia"* "ciencia"*');
    });

    test('ignora los espacios de más', () {
      expect(
        buildSearchQuery('  historia   ciencia  '),
        '"historia"* "ciencia"*',
      );
    });

    test('una entrada vacía produce una consulta vacía, no una que falle', () {
      expect(buildSearchQuery(''), '');
      expect(buildSearchQuery('    '), '');
    });

    test('los operadores de FTS5 se tratan como texto, no como sintaxis', () {
      // Sin esto, buscar "gatos AND perros" o "NEAR" daría resultados
      // inesperados en vez de buscar esas palabras.
      expect(buildSearchQuery('gatos AND perros'), '"gatos"* "AND"* "perros"*');
    });

    test('los caracteres que romperían la consulta quedan neutralizados', () {
      // Buscar "C++" o "¿qué?" no puede terminar en un error de sintaxis que
      // el usuario no tiene manera de entender: él escribió una pregunta, no
      // una expresión de FTS5.
      expect(buildSearchQuery('C++'), '"C++"*');
      expect(buildSearchQuery('¿qué?'), '"¿qué?"*');
      expect(buildSearchQuery('(paréntesis)'), '"(paréntesis)"*');
    });

    test('las comillas se escapan duplicándolas, como exige FTS5', () {
      // Cada término va entre comillas, y las que el usuario haya escrito se
      // duplican para no cerrar el literal antes de tiempo.
      expect(buildSearchQuery('el "dilema"'), '"el"* """dilema"""*');
    });
  });

  group('las consultas generadas son válidas en FTS5', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'src',
              kind: SourceKind.webPage,
              capturedAt: DateTime(2026, 9, 11),
            ),
          );
      await db
          .into(db.items)
          .insert(
            ItemsCompanion.insert(
              id: 'item',
              title: 'Algo sobre C++ y otras cosas',
              sourceId: 'src',
              processingState: ProcessingState.ready,
              createdAt: DateTime(2026, 9, 11),
              updatedAt: DateTime(2026, 9, 11),
            ),
          );
    });

    tearDown(() => db.close());

    /// Comparar cadenas prueba que el escapado es el que se esperaba; esto
    /// prueba lo que de verdad importa, que es que el motor las acepte.
    /// Cualquiera de estas entradas, mandada cruda a FTS5, produciría un
    /// error de sintaxis — y el usuario vería reventar la búsqueda por haber
    /// escrito su pregunta con normalidad.
    Future<void> expectQueryRuns(String userInput) async {
      final query = buildSearchQuery(userInput);
      if (query.isEmpty) return;

      await expectLater(
        db
            .customSelect(
              'SELECT item_id FROM item_search WHERE item_search MATCH ?',
              variables: [Variable.withString(query)],
            )
            .get(),
        completes,
      );
    }

    for (final input in <String>[
      'C++',
      '¿qué es esto?',
      'gatos AND perros',
      'NEAR',
      'OR',
      'NOT',
      '(paréntesis)',
      'comillas "adentro"',
      'asterisco * suelto',
      'dos puntos: acá',
      'guión - suelto',
      '^ circunflejo',
      'barra invertida',
      'emoji 🧠 incluido',
      "apóstrofo ' suelto",
    ]) {
      test('no falla con: $input', () => expectQueryRuns(input));
    }
  });
}
