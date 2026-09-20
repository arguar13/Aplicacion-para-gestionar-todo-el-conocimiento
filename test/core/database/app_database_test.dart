import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

import '../../support/item_rows.dart';

/// Estas pruebas corren contra SQLite de verdad, en memoria — no contra un
/// doble.
///
/// Es deliberado: lo que se está verificando acá no es código Dart sino el
/// esquema mismo (cascadas, restricciones CHECK, triggers de FTS5). Un mock
/// de la base respondería lo que uno le pida y no probaría nada de eso; lo
/// único que puede confirmar que una cascada realmente borra es un motor que
/// realmente la ejecute.
void main() {
  late AppDatabase db;

  final now = DateTime(2026, 9, 11, 10);

  // Un contador y no `DateTime.now().microsecondsSinceEpoch`: en Windows la
  // resolución real del reloj del sistema es más gruesa que un microsegundo,
  // así que dos inserciones seguidas dentro del mismo test podían recibir el
  // mismo id y romper con una violación de UNIQUE que nada tiene que ver con
  // lo que el test intenta verificar.
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    counter = 0;
  });

  tearDown(() => db.close());

  Future<String> insertItem({String title = 'Un artículo cualquiera'}) async {
    final id = 'item-${counter++}';
    await insertItemRows(db, id: id, title: title, createdAt: now);
    return id;
  }

  Future<String> insertTextRendition({
    required String itemId,
    required String content,
  }) async {
    final id = 'rend-${counter++}';
    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: id,
            itemId: itemId,
            kind: RenditionKind.plainText,
            isPrimary: true,
            createdAt: now,
            content: Value(content),
          ),
        );
    return id;
  }

  group('integridad referencial', () {
    test('las claves foráneas están activas: sin el pragma, todas las '
        'cascadas del esquema serían decoración', () async {
      final pragma = await db.customSelect('PRAGMA foreign_keys').getSingle();

      expect(pragma.data.values.first, 1);
    });

    test('borrar un elemento borra sus formas', () async {
      final itemId = await insertItem();
      await insertTextRendition(itemId: itemId, content: 'texto');

      await (db.delete(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(itemId))).go();

      expect(await db.select(db.renditions).get(), isEmpty);
    });

    test('borrar un elemento borra también su fuente: nada puede quedar sin '
        'decir de quién es', () async {
      final itemId = await insertItem();

      await (db.delete(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(itemId))).go();

      expect(await db.select(db.knowledgeSources).get(), isEmpty);
    });

    test('no se puede agregar una forma a un elemento que no existe', () {
      expect(
        () => insertTextRendition(itemId: 'no-existe', content: 'texto'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('borrar una forma borra sus subrayados', () async {
      final itemId = await insertItem();
      final renditionId = await insertTextRendition(
        itemId: itemId,
        content: 'una frase importante acá',
      );
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              id: 'hl-1',
              renditionId: renditionId,
              startOffset: 4,
              endOffset: 9,
              excerpt: 'frase',
              createdAt: now,
            ),
          );

      await (db.delete(
        db.renditions,
      )..where((r) => r.id.equals(renditionId))).go();

      expect(await db.select(db.highlights).get(), isEmpty);
    });
  });

  group('restricciones del esquema', () {
    test('una forma no puede tener texto Y archivo a la vez', () async {
      final itemId = await insertItem();

      expect(
        () => db
            .into(db.renditions)
            .insert(
              RenditionsCompanion.insert(
                id: 'r1',
                itemId: itemId,
                kind: RenditionKind.plainText,
                isPrimary: true,
                createdAt: now,
                content: const Value('texto'),
                relativePath: const Value('archivos/a.txt'),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('ni tampoco quedarse sin ninguno de los dos', () async {
      final itemId = await insertItem();

      expect(
        () => db
            .into(db.renditions)
            .insert(
              RenditionsCompanion.insert(
                id: 'r1',
                itemId: itemId,
                kind: RenditionKind.plainText,
                isPrimary: true,
                createdAt: now,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('nada puede relacionarse consigo mismo', () async {
      final itemId = await insertItem();

      expect(
        () => db
            .into(db.relations)
            .insert(
              RelationsCompanion.insert(
                id: 'rel-1',
                fromItemId: itemId,
                toItemId: itemId,
                kind: RelationKind.relatedTo,
                createdAt: now,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('el mismo vínculo del mismo tipo no se puede duplicar', () async {
      final a = await insertItem(title: 'A');
      final b = await insertItem(title: 'B');

      Future<void> relate(String id) => db
          .into(db.relations)
          .insert(
            RelationsCompanion.insert(
              id: id,
              fromItemId: a,
              toItemId: b,
              kind: RelationKind.cites,
              createdAt: now,
            ),
          );

      await relate('rel-1');
      expect(() => relate('rel-2'), throwsA(isA<SqliteException>()));
    });

    test('pero sí se pueden relacionar dos elementos de dos maneras '
        'distintas', () async {
      final a = await insertItem(title: 'A');
      final b = await insertItem(title: 'B');

      Future<void> relate(String id, RelationKind kind) => db
          .into(db.relations)
          .insert(
            RelationsCompanion.insert(
              id: id,
              fromItemId: a,
              toItemId: b,
              kind: kind,
              createdAt: now,
            ),
          );

      await relate('rel-1', RelationKind.cites);
      await relate('rel-2', RelationKind.contradicts);

      expect(await db.select(db.relations).get(), hasLength(2));
    });

    test('un subrayado no puede terminar antes de donde empieza', () async {
      final itemId = await insertItem();
      final renditionId = await insertTextRendition(
        itemId: itemId,
        content: 'texto',
      );

      expect(
        () => db
            .into(db.highlights)
            .insert(
              HighlightsCompanion.insert(
                id: 'hl-1',
                renditionId: renditionId,
                startOffset: 10,
                endOffset: 5,
                excerpt: 'x',
                createdAt: now,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
