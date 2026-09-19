import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/inline_link_sync.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

import '../../support/fake_id_generator.dart';

/// Los `[[Título]]` de una nota, sincronizados con `inline_link` al guardarla
/// (F9), y los enlaces rotos que se resuelven cuando aparece el título que
/// esperaban. Probado contra SQLite real.
void main() {
  late AppDatabase db;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 19, 10);
  final jan1 = DateTime(2026);
  final jan2 = DateTime(2026, 1, 2);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator(prefix: 'gen');
  });

  tearDown(() => db.close());

  Future<void> seedItem(String id, String title, {DateTime? createdAt}) async {
    final at = createdAt ?? now;
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'src-$id',
            kind: SourceKind.webPage,
            capturedAt: at,
          ),
        );
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            title: title,
            sourceId: 'src-$id',
            processingState: ProcessingState.ready,
            createdAt: at,
            updatedAt: at,
          ),
        );
  }

  Future<void> sync(String itemId, List<String> paragraphs) => syncInlineLinks(
    db,
    itemId: itemId,
    blocks: [for (final text in paragraphs) ContentBlock.paragraph(text: text)],
    ids: ids,
    clock: () => now,
  );

  Future<int> resolveFor(String itemId, String title) =>
      resolveBrokenInlineLinks(
        db,
        itemId: itemId,
        title: title,
        ids: ids,
        clock: () => now,
      );

  /// Los enlaces registrados de [itemId], como (título normalizado, destino).
  Future<Set<(String, String?)>> linksOf(String itemId) async => {
    for (final link in await (db.select(
      db.inlineLinks,
    )..where((l) => l.fromItemId.equals(itemId))).get())
      (link.normalizedTitle, link.toItemId),
  };

  Future<Set<(String, String)>> relatedTo() async => {
    for (final relation in await (db.select(
      db.relations,
    )..where((r) => r.kind.equalsValue(RelationKind.relatedTo))).get())
      (relation.fromItemId, relation.toItemId),
  };

  group('syncInlineLinks', () {
    test('un enlace con destino queda registrado y crea la relación', () async {
      await seedItem('roma', 'Roma');
      await seedItem('n1', 'Viaje');

      await sync('n1', ['Fui a [[Roma]].']);

      expect(await linksOf('n1'), {('roma', 'roma')});
      expect(await relatedTo(), {('n1', 'roma')});
    });

    test(
      'un enlace sin destino queda registrado como roto, sin relación',
      () async {
        await seedItem('n1', 'Viaje');

        await sync('n1', ['Fui a [[Cartago]].']);

        expect(await linksOf('n1'), {('cartago', null)});
        expect(await relatedTo(), isEmpty);
      },
    );

    test('se resuelve sin distinguir mayúsculas ni espacios en los bordes, '
        'también fuera del ASCII', () async {
      // `lower()` de SQLite solo pliega ASCII: "Época" y "época" son el mismo
      // título para quien escribe, y comparar en SQL los separaría.
      await seedItem('epoca', 'Época');
      await seedItem('ñu', 'Ñu');
      await seedItem('n1', 'Viaje');

      await sync('n1', ['[[  época ]] y [[ñU]]']);

      expect(await linksOf('n1'), {('época', 'epoca'), ('ñu', 'ñu')});
    });

    test('con varios elementos del mismo título, gana el más antiguo y se '
        'crea una sola relación', () async {
      // El más antiguo tiene el id MAYOR: no gana por alfabeto ni por orden
      // de inserción.
      await seedItem('z-roma', 'Roma', createdAt: jan1);
      await seedItem('a-roma', 'Roma', createdAt: jan2);
      await seedItem('n1', 'Viaje');

      await sync('n1', ['[[Roma]]']);

      expect(await linksOf('n1'), {('roma', 'z-roma')});
      expect(await relatedTo(), {('n1', 'z-roma')});
    });

    test(
      'una nota que se menciona a sí misma no registra ese enlace',
      () async {
        await seedItem('yo', 'Yo');

        await sync('yo', ['Hablo de [[yo]].']);

        expect(await linksOf('yo'), isEmpty);
        expect(await relatedTo(), isEmpty);
      },
    );

    test('un homónimo de la propia nota sí es un destino', () async {
      await seedItem('n', 'Tema', createdAt: jan1);
      await seedItem('otro', 'Tema', createdAt: jan2);

      await sync('n', ['[[tema]]']);

      expect(await linksOf('n'), {('tema', 'otro')});
    });

    test('si la nota pasa a llamarse como su enlace roto, ese enlace '
        'desaparece', () async {
      await seedItem('n1', 'Viaje');
      await sync('n1', ['[[Roma]]']);
      expect(await linksOf('n1'), {('roma', null)});

      await (db.update(db.items)..where((i) => i.id.equals('n1'))).write(
        const ItemsCompanion(title: Value('Roma')),
      );
      await sync('n1', ['[[Roma]]']);

      expect(await linksOf('n1'), isEmpty);
    });

    test('quitar la mención borra el enlace registrado pero conserva la '
        'relación', () async {
      await seedItem('roma', 'Roma');
      await seedItem('n1', 'Viaje');
      await sync('n1', ['[[Roma]]']);

      await sync('n1', ['Ya no hablo de eso.']);

      expect(await linksOf('n1'), isEmpty);
      // La relación pudo confirmarla el usuario: borrar un texto no es decir
      // que dos notas dejaron de estar vinculadas.
      expect(await relatedTo(), {('n1', 'roma')});
    });

    test('sin bloques —la nota dejó de serlo— se borran todos sus '
        'enlaces', () async {
      await seedItem('roma', 'Roma');
      await seedItem('n1', 'Viaje');
      await sync('n1', ['[[Roma]] y [[Cartago]]']);

      await sync('n1', const []);

      expect(await linksOf('n1'), isEmpty);
    });

    test('guardar dos veces lo mismo no cambia nada', () async {
      await seedItem('roma', 'Roma');
      await seedItem('n1', 'Viaje');
      await sync('n1', ['[[Roma]] y [[Cartago]]']);
      final rowsBefore = {
        for (final l in await db.select(db.inlineLinks).get()) l.id,
      };
      final idsBefore = ids.generated;

      await sync('n1', ['[[Roma]] y [[Cartago]]']);

      expect({
        for (final l in await db.select(db.inlineLinks).get()) l.id,
      }, rowsBefore);
      expect(await db.select(db.relations).get(), hasLength(1));
      // Ni siquiera gasta identificadores: no hay nada por escribir.
      expect(ids.generated, idsBefore);
    });

    test('un enlace que seguía roto se resuelve al guardar si el destino '
        'ya existe', () async {
      await seedItem('n1', 'Viaje');
      await sync('n1', ['[[Roma]]']);
      await seedItem('roma', 'Roma');

      await sync('n1', ['[[Roma]]']);

      expect(await linksOf('n1'), {('roma', 'roma')});
      expect(await relatedTo(), {('n1', 'roma')});
    });

    test('si el destino se borra el enlace queda roto, y al guardar se '
        'resuelve contra otro elemento con ese título', () async {
      await seedItem('roma', 'Roma', createdAt: jan1);
      await seedItem('roma-2', 'Roma', createdAt: jan2);
      await seedItem('n1', 'Viaje');
      await sync('n1', ['[[Roma]]']);
      expect(await linksOf('n1'), {('roma', 'roma')});

      await (db.delete(db.items)..where((i) => i.id.equals('roma'))).go();
      expect(await linksOf('n1'), {('roma', null)});

      await sync('n1', ['[[Roma]]']);

      expect(await linksOf('n1'), {('roma', 'roma-2')});
    });

    test('una relación que el usuario borró a propósito no se resucita al '
        'guardar la nota', () async {
      await seedItem('roma', 'Roma');
      await seedItem('n1', 'Viaje');
      await sync('n1', ['[[Roma]]']);
      await db.delete(db.relations).go();

      await sync('n1', ['[[Roma]] otra vez']);

      expect(await relatedTo(), isEmpty);
      expect(await linksOf('n1'), {('roma', 'roma')});
    });

    test('actualiza la forma escrita del título, que es con la que se crea '
        'la nota que falta', () async {
      await seedItem('n1', 'Viaje');
      await sync('n1', ['[[roma]]']);

      await sync('n1', ['[[Roma]]']);

      final link = await db.select(db.inlineLinks).getSingle();
      expect(link.targetTitle, 'Roma');
      expect(link.normalizedTitle, 'roma');
    });

    test('un mismo enlace escrito dos veces es uno solo', () async {
      await seedItem('n1', 'Viaje');

      await sync('n1', ['[[Roma]]', 'De nuevo [[roma]]']);

      expect(await db.select(db.inlineLinks).get(), hasLength(1));
    });
  });

  group('resolveBrokenInlineLinks', () {
    test('resuelve los enlaces rotos que esperaban ese título y crea la '
        'relación de cada uno', () async {
      await seedItem('n1', 'Uno');
      await seedItem('n2', 'Dos');
      await sync('n1', ['[[Roma]]']);
      await sync('n2', ['[[roma]]']);
      await seedItem('roma', 'Roma');

      final resolved = await resolveFor('roma', 'Roma');

      expect(resolved, 2);
      expect(await linksOf('n1'), {('roma', 'roma')});
      expect(await linksOf('n2'), {('roma', 'roma')});
      expect(await relatedTo(), {('n1', 'roma'), ('n2', 'roma')});
    });

    test(
      'renombrar un elemento resuelve los enlaces al título nuevo',
      () async {
        await seedItem('n1', 'Uno');
        await seedItem('x', 'Algo');
        await sync('n1', ['[[Roma Antigua]]']);

        await (db.update(db.items)..where((i) => i.id.equals('x'))).write(
          const ItemsCompanion(title: Value('Roma Antigua')),
        );
        final resolved = await resolveFor('x', 'Roma Antigua');

        expect(resolved, 1);
        expect(await linksOf('n1'), {('roma antigua', 'x')});
      },
    );

    test('resuelve también fuera del ASCII', () async {
      await seedItem('n1', 'Uno');
      await sync('n1', ['[[época]]']);
      await seedItem('epoca', 'Época');

      expect(await resolveFor('epoca', 'Época'), 1);
    });

    test('no toca los enlaces que ya tenían destino ni los de otros '
        'títulos', () async {
      await seedItem('roma', 'Roma');
      await seedItem('n1', 'Uno');
      await sync('n1', ['[[Roma]] y [[Cartago]]']);
      await seedItem('atenas', 'Atenas');

      final resolved = await resolveFor('atenas', 'Atenas');

      expect(resolved, 0);
      expect(await linksOf('n1'), {('roma', 'roma'), ('cartago', null)});
    });

    test('no resuelve los enlaces que escribe el propio elemento', () async {
      await seedItem('n1', 'Uno');
      await sync('n1', ['[[Roma]]']);
      // La nota pasa a llamarse "Roma": su propio enlace no apunta a sí misma.
      await (db.update(db.items)..where((i) => i.id.equals('n1'))).write(
        const ItemsCompanion(title: Value('Roma')),
      );

      final resolved = await resolveFor('n1', 'Roma');

      expect(resolved, 0);
      expect(await linksOf('n1'), {('roma', null)});
    });

    test('un título vacío no resuelve nada', () async {
      await seedItem('n1', 'Uno');
      await sync('n1', ['[[Roma]]']);

      expect(await resolveFor('n1', '   '), 0);
    });

    test('resolver dos veces no repite relaciones', () async {
      await seedItem('n1', 'Uno');
      await sync('n1', ['[[Roma]]']);
      await seedItem('roma', 'Roma');

      await resolveFor('roma', 'Roma');
      final second = await resolveFor('roma', 'Roma');

      expect(second, 0);
      expect(await db.select(db.relations).get(), hasLength(1));
    });
  });
}
