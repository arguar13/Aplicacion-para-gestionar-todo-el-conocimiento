import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_applier.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart'
    show kIncomingSchema;
import 'package:sinapsis/features/vault/data/merge/merge_fields.dart';

import '../../../../support/test_vault.dart';

/// La fusión de la copia de otra bóveda con esta (F11), en lo que toca a los
/// elementos y sus campos: qué elementos llegan, qué versión de cada campo
/// queda, y qué se guarda como conflicto.
///
/// Son dos bóvedas de verdad —«tel» y «pc»—, cada una con su base, su reloj y
/// su identificador de dispositivo, llenadas por el camino de la app: las
/// versiones por campo que hay son las que escribe `KnowledgeEntryWriter`, no
/// unas armadas a mano. La hora se mueve con `at(minutos)`.
void main() {
  late TestVault tel;
  late TestVault pc;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  /// Las versiones por campo de un elemento, como texto y ordenadas: para
  /// comparar dos bóvedas de un vistazo.
  Future<List<String>> versionsOf(TestVault vault, String id) async {
    final rows = await (vault.db.select(
      vault.db.fieldVersions,
    )..where((f) => f.itemId.equals(id))).get();
    return [
      for (final r in rows)
        [
          r.fieldName,
          r.deviceId,
          r.updatedAt.millisecondsSinceEpoch,
          r.baseDeviceId,
          r.baseUpdatedAt?.millisecondsSinceEpoch,
        ].join(' '),
    ]..sort();
  }

  /// Que una fusión no dejó la copia adjuntada ni su tabla de trabajo.
  Future<void> expectNothingLeftOver(TestVault vault) async {
    final attached = await vault.db.customSelect('PRAGMA database_list').get();
    expect(
      attached.map((r) => r.read<String>('name')),
      isNot(contains(kIncomingSchema)),
    );
    final work = await vault.db
        .customSelect(
          "SELECT name FROM sqlite_temp_master WHERE name = 'merge_new_items'",
        )
        .get();
    expect(work, isEmpty);
  }

  /// «a» nace en tel a las 12:01 y pc la recibe a las 12:02: las dos bóvedas la
  /// tienen, con las mismas versiones.
  Future<void> shareItem() async {
    tel.at(1);
    await tel.saveSource('a', title: 'Original');
    pc.at(2);
    await pc.mergeFrom(tel);
  }

  group('los elementos que esta bóveda no tiene', () {
    test('llegan con su fuente, su nota y sus versiones por campo', () async {
      pc.at(3);
      await pc.saveSource(
        'a',
        title: 'Fuente A',
        subtitle: 'Sub',
        notes: 'Mis notas',
        originalName: 'x.pdf',
        author: 'Ana',
      );
      await pc.saveNote('n', title: 'Nota N', kind: NoteKind.atomic);

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.itemsAdded, 2);
      expect(result.itemsUpdated, 0);
      expect(result.conflictsRecorded, 0);
      expect(await tel.count('item'), 2);
      expect(await tel.count('source'), 1);
      expect(await tel.count('note'), 1);

      final a = await tel.entry('a');
      final original = await pc.entry('a');
      expect(a.title, 'Fuente A');
      expect(a.subtitle, 'Sub');
      expect(a.notes, 'Mis notas');
      expect(a.kind, original.kind);
      expect(a.state, original.state);
      expect(a.createdAt, original.createdAt);
      expect(a.updatedAt, original.updatedAt);
      // Es la versión de allá: se copia tal cual, con su autor y su `rev`.
      expect(a.deviceId, 'pc');
      expect(a.rev, original.rev);

      final source = await (tel.db.select(
        tel.db.knowledgeSources,
      )..where((s) => s.itemId.equals('a'))).getSingle();
      expect(source.authorName, 'Ana');
      expect(source.originalBlobPath, 'originales/a/x.pdf');

      final note = await (tel.db.select(
        tel.db.knowledgeNotes,
      )..where((n) => n.itemId.equals('n'))).getSingle();
      expect(note.noteKind, NoteKind.atomic);

      // Las versiones vienen con el linaje que tenían.
      expect(await versionsOf(tel, 'a'), await versionsOf(pc, 'a'));
      expect(await versionsOf(tel, 'n'), await versionsOf(pc, 'n'));
      expect(await versionsOf(tel, 'a'), isNotEmpty);
      expect(await tel.conflicts(), isEmpty);
    });

    test(
      'uno que está en la papelera de la copia llega en la papelera',
      () async {
        pc.at(3);
        await pc.saveSource('a');
        pc.at(4);
        await pc.library.delete('a');

        await tel.mergeFrom(pc);

        final a = await tel.entry('a');
        expect(a.deletedAt, (await pc.entry('a')).deletedAt);
        expect(a.deletedAt, isNotNull);
      },
    );

    test('lo que esta bóveda ya tenía no se toca', () async {
      tel.at(1);
      await tel.saveSource('mio', title: 'Mío');
      final before = await tel.entry('mio');
      pc.at(3);
      await pc.saveSource('a');

      final result = await tel.mergeFrom(pc);

      expect(result.itemsAdded, 1);
      expect(await tel.entry('mio'), before);
    });

    test('una copia sin nada no cambia nada', () async {
      await tel.saveSource('a');
      final before = await tel.counts();

      final result = await tel.mergeFrom(pc);

      expect(result.changedNothing, isTrue);
      expect(await tel.counts(), before);
    });

    test('una copia de una versión vieja también se fusiona', () async {
      final result = await tel.mergeZip(await vaultCopyAtV19());

      expect(result.itemsAdded, 1);
      expect((await tel.entry('legacy-src')).title, 'Fuente vieja');
      // Lo escrito antes de F11 no tiene versiones.
      expect(await versionsOf(tel, 'legacy-src'), isEmpty);
    });

    test('no deja nada adjunto ni la tabla de trabajo', () async {
      await pc.saveSource('a');

      await tel.mergeFrom(pc);

      await expectNothingLeftOver(tel);
    });
  });

  group('los espacios', () {
    test('uno con el mismo nombre es el mismo: los elementos quedan en el de '
        'acá', () async {
      await tel.addSpace('sp-tel', 'Historia');
      await pc.addSpace('sp-pc', 'historia'); // mismo nombre, otro id y letras
      await pc.addSpace('sp-fis', 'Física'); // uno que acá no hay
      pc.at(3);
      await pc.saveSource('a', spaceId: 'sp-pc');
      await pc.saveSource('b', spaceId: 'sp-fis');

      final result = await tel.mergeFrom(pc);

      expect(result.spacesAdded, 1);
      final spaces = await tel.db.customSelect('SELECT id FROM spaces').get();
      expect(spaces.map((r) => r.read<String>('id')).toSet(), {
        'sp-tel',
        'sp-fis',
      });
      expect((await tel.entry('a')).spaceId, 'sp-tel');
      expect((await tel.entry('b')).spaceId, 'sp-fis');
    });

    test(
      'un elemento común en el mismo espacio de las dos no cambia',
      () async {
        await tel.addSpace('sp-tel', 'Historia');
        await pc.addSpace('sp-pc', 'Historia');
        tel.at(1);
        await tel.saveSource('a', spaceId: 'sp-tel');
        pc.at(2);
        await pc.mergeFrom(tel);
        expect((await pc.entry('a')).spaceId, 'sp-pc');

        tel.at(3);
        final result = await tel.mergeFrom(pc);

        expect(result.changedNothing, isTrue);
        expect((await tel.entry('a')).spaceId, 'sp-tel');
      },
    );

    test(
      'dos espacios de la copia con el mismo nombre entran como uno',
      () async {
        await pc.addSpace('s1', 'Física');
        await pc.addSpace('s2', 'FÍSICA');

        final result = await tel.mergeFrom(pc);

        expect(result.spacesAdded, 1);
        expect(await tel.count('spaces'), 1);
      },
    );
  });

  group('un elemento que las dos bóvedas tienen', () {
    test('la copia lo editó partiendo de la versión de acá: gana, sin '
        'conflicto', () async {
      await shareItem();
      final before = await tel.entry('a');
      pc.at(5);
      await pc.saveSource('a', title: 'Editado en pc');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.fieldsUpdated, 1);
      expect(result.itemsUpdated, 1);
      expect(result.conflictsRecorded, 0);
      final a = await tel.entry('a');
      expect(a.title, 'Editado en pc');
      // El elemento cambió aquí: sube el `rev`, y su fecha es la más reciente.
      expect(a.rev, before.rev + 1);
      expect(a.deviceId, 'tel');
      expect(a.updatedAt, (await pc.entry('a')).updatedAt);
      // La versión es la de pc, con el linaje que traía: partió de la de tel.
      final version = await tel.version('a', EntryField.title);
      expect(version!.deviceId, 'pc');
      expect(version.baseDeviceId, 'tel');
      expect(await tel.conflicts(), isEmpty);
    });

    test('editada acá sobre la de la copia, se queda la de acá', () async {
      await shareItem();
      pc.at(5);
      await pc.saveSource('a', title: 'Editado en pc');
      tel.at(7);
      await tel.mergeFrom(pc);
      tel.at(9);
      await tel.saveSource('a', title: 'Editado en tel sobre lo de pc');

      pc.at(11);
      final result = await pc.mergeFrom(tel);

      // La de tel partió de la de pc: pc la recibe, sin conflicto.
      expect(result.conflictsRecorded, 0);
      expect((await pc.entry('a')).title, 'Editado en tel sobre lo de pc');
      expect(await pc.conflicts(), isEmpty);
    });

    test('teléfono→compu→teléfono: ninguna vuelta es un conflicto', () async {
      await shareItem();
      for (var round = 0; round < 3; round++) {
        pc.at(10 + round * 10);
        await pc.saveSource('a', title: 'pc ronda $round');
        tel.at(15 + round * 10);
        expect((await tel.mergeFrom(pc)).conflictsRecorded, 0);
        await tel.saveSource('a', title: 'tel ronda $round');
        pc.at(18 + round * 10);
        expect((await pc.mergeFrom(tel)).conflictsRecorded, 0);
      }

      expect((await tel.entry('a')).title, 'tel ronda 2');
      expect((await pc.entry('a')).title, 'tel ronda 2');
      expect(await tel.conflicts(), isEmpty);
      expect(await pc.conflicts(), isEmpty);
    });

    test('editado en las dos a la vez: gana la más reciente y se guarda la '
        'otra', () async {
      await shareItem();
      tel.at(5);
      await tel.saveSource('a', title: 'De tel');
      pc.at(7);
      await pc.saveSource('a', title: 'De pc');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.conflictsRecorded, 1);
      expect((await tel.entry('a')).title, 'De pc');
      final conflict = (await tel.conflicts()).single;
      expect(conflict.itemId, 'a');
      expect(conflict.fieldName, EntryField.title);
      expect(conflict.localValue, 'De tel');
      expect(conflict.incomingValue, 'De pc');
      expect(conflict.localDeviceId, 'tel');
      expect(conflict.incomingDeviceId, 'pc');
      expect(
        conflict.localUpdatedAt,
        tel.now.subtract(const Duration(minutes: 4)),
      );
      expect(
        conflict.incomingUpdatedAt,
        tel.now.subtract(const Duration(minutes: 2)),
      );
      expect(conflict.detectedAt, tel.now);
      expect(conflict.resolvedAt, isNull);
      expect(conflict.resolution, isNull);
    });

    test(
      'fusionando en el otro sentido gana la misma: las dos coinciden',
      () async {
        await shareItem();
        tel.at(5);
        await tel.saveSource('a', title: 'De tel');
        pc.at(7);
        await pc.saveSource('a', title: 'De pc');

        // Primero pc recibe la de tel: lo suyo es más reciente y se queda, y la
        // de tel se guarda como conflicto.
        pc.at(9);
        final inPc = await pc.mergeFrom(tel);
        expect(inPc.fieldsUpdated, 0);
        expect(inPc.conflictsRecorded, 1);
        final kept = (await pc.conflicts()).single;
        expect(kept.localValue, 'De pc');
        expect(kept.incomingValue, 'De tel');

        // Después tel recibe la de pc: la toma, y guarda la suya.
        tel.at(9);
        final inTel = await tel.mergeFrom(pc);
        expect(inTel.fieldsUpdated, 1);
        expect(inTel.conflictsRecorded, 1);
        final replaced = (await tel.conflicts()).single;
        expect(replaced.localValue, 'De tel');
        expect(replaced.incomingValue, 'De pc');

        expect((await tel.entry('a')).title, 'De pc');
        expect((await pc.entry('a')).title, 'De pc');
      },
    );

    test(
      'fusionar dos veces la misma copia no cambia nada la segunda',
      () async {
        await shareItem();
        tel.at(5);
        await tel.saveSource('a', title: 'De tel');
        pc.at(7);
        await pc.saveSource('a', title: 'De pc');
        tel.at(9);
        await tel.mergeFrom(pc);
        pc.at(9);
        await pc.mergeFrom(tel);
        final counts = await pc.counts();
        final entry = await pc.entry('a');

        pc.at(20);
        final again = await pc.mergeFrom(tel);

        expect(again.changedNothing, isTrue);
        expect(await pc.counts(), counts);
        expect(await pc.entry('a'), entry);
        final preview = await pc.previewFrom(tel);
        expect(preview.hasNothingNew, isTrue);
      },
    );

    test(
      'un conflicto que el usuario ya resolvió no vuelve a aparecer',
      () async {
        await shareItem();
        tel.at(5);
        await tel.saveSource('a', title: 'De tel');
        pc.at(7);
        await pc.saveSource('a', title: 'De pc');
        pc.at(9);
        await pc.mergeFrom(tel);
        await pc.db.customStatement(
          "UPDATE merge_conflict SET resolved_at = 1, resolution = 'keepLocal'",
        );

        pc.at(20);
        final again = await pc.mergeFrom(tel);

        expect(again.conflictsRecorded, 0);
        expect(await pc.conflicts(), hasLength(1));
      },
    );

    test('campos distintos editados a la vez no chocan', () async {
      await shareItem();
      tel.at(5);
      await tel.saveSource('a', title: 'Original', subtitle: 'Sub de tel');
      pc.at(7);
      await pc.saveSource('a', title: 'Original', notes: 'Notas de pc');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.conflictsRecorded, 0);
      final a = await tel.entry('a');
      // Cada uno conservó lo suyo y recibió lo del otro.
      expect(a.subtitle, 'Sub de tel');
      expect(a.notes, 'Notas de pc');
    });

    test('el campo que solo la copia modificó gana, aunque acá no tenga '
        'versión', () async {
      tel.at(1);
      await tel.saveNote('n');
      pc.at(2);
      await pc.mergeFrom(tel);
      pc.at(5);
      await pc.writer.setNoteKind('n', NoteKind.map);
      await pc.writer.setMaturity('n', NoteMaturity.mature);

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.fieldsUpdated, 2);
      expect(result.conflictsRecorded, 0);
      final note = await (tel.db.select(
        tel.db.knowledgeNotes,
      )..where((n) => n.itemId.equals('n'))).getSingle();
      expect(note.noteKind, NoteKind.map);
      expect(note.maturity, NoteMaturity.mature);
    });

    test('los datos de la fuente se fusionan como el resto', () async {
      tel.at(1);
      await tel.saveSource('a');
      pc.at(2);
      await pc.mergeFrom(tel);
      pc.at(5);
      await pc.saveSource('a', author: 'Ana');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.fieldsUpdated, 1);
      final source = await (tel.db.select(
        tel.db.knowledgeSources,
      )..where((s) => s.itemId.equals('a'))).getSingle();
      expect(source.authorName, 'Ana');
    });

    test('sin versiones en ninguna —lo de antes de F11— gana el elemento '
        'modificado más recientemente, sin conflicto', () async {
      tel.at(1);
      await tel.saveSource('a', title: 'De tel');
      pc.at(9);
      await pc.saveSource('a', title: 'De pc');
      for (final vault in [tel, pc]) {
        await vault.db.customStatement('DELETE FROM field_version');
        await vault.db.customStatement("UPDATE item SET device_id = 'legacy'");
      }

      tel.at(20);
      final result = await tel.mergeFrom(pc);

      expect(result.conflictsRecorded, 0);
      expect((await tel.entry('a')).title, 'De pc');
      // Y no inventa una versión que nadie escribió.
      expect(await tel.version('a', EntryField.title), isNull);

      final back = await pc.mergeFrom(tel);
      expect(back.changedNothing, isTrue);
      expect((await pc.entry('a')).title, 'De pc');
    });
  });

  group('borrar y editar', () {
    test('un borrado que llega solo se aplica', () async {
      await shareItem();
      tel.at(5);
      await tel.library.delete('a');

      pc.at(8);
      final result = await pc.mergeFrom(tel);

      expect(result.conflictsRecorded, 0);
      expect((await pc.entry('a')).deletedAt, isNotNull);
      final version = await pc.version('a', EntryField.deletedAt);
      expect(version!.deviceId, 'tel');
    });

    test('un borrado contra una edición: el elemento queda vivo y el borrado '
        'se guarda', () async {
      await shareItem();
      tel.at(5);
      await tel.library.delete('a');
      pc.at(6);
      await pc.saveSource('a', title: 'Editado en pc');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      final a = await tel.entry('a');
      expect(a.deletedAt, isNull, reason: 'quien editó no sabía del borrado');
      expect(a.title, 'Editado en pc', reason: 'y su edición no se pierde');
      expect(result.conflictsRecorded, 1);
      final conflict = (await tel.conflicts()).single;
      expect(conflict.fieldName, EntryField.deletedAt);
      expect(conflict.localValue, isNotNull);
      expect(conflict.incomingValue, isNull);
      expect(conflict.localDeviceId, 'tel');
    });

    test('la otra cara: acá se editó y allá se borró, y queda vivo', () async {
      await shareItem();
      tel.at(5);
      await tel.saveSource('a', title: 'Editado en tel');
      pc.at(6);
      await pc.library.delete('a');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect((await tel.entry('a')).deletedAt, isNull);
      expect((await tel.entry('a')).title, 'Editado en tel');
      expect(result.conflictsRecorded, 1);
      expect((await tel.conflicts()).single.fieldName, EntryField.deletedAt);
    });

    test('restaurar allá lo que se borró acá partiendo del borrado: se '
        'restaura, sin conflicto', () async {
      await shareItem();
      tel.at(5);
      await tel.library.delete('a');
      pc.at(8);
      await pc.mergeFrom(tel);
      pc.at(9);
      await pc.library.restore('a');

      tel.at(12);
      final result = await tel.mergeFrom(pc);

      expect(result.conflictsRecorded, 0);
      expect((await tel.entry('a')).deletedAt, isNull);
    });

    test(
      'los dos lo borraron a horas distintas: sigue en la papelera',
      () async {
        await shareItem();
        tel.at(5);
        await tel.library.delete('a');
        pc.at(7);
        await pc.library.delete('a');

        tel.at(9);
        final result = await tel.mergeFrom(pc);

        expect(result.conflictsRecorded, 0);
        expect((await tel.entry('a')).deletedAt, isNotNull);
      },
    );
  });

  group('la vista previa dice lo que la fusión hace', () {
    test('elementos, campos, conflictos y espacios coinciden', () async {
      await tel.addSpace('sp', 'Historia');
      await pc.addSpace('sp2', 'Física');
      tel.at(1);
      await tel.saveSource('a', title: 'Original');
      await tel.saveSource('b', title: 'B original');
      pc.at(2);
      await pc.mergeFrom(tel);
      tel.at(5);
      await tel.saveSource('a', title: 'De tel');
      pc.at(6);
      await pc.saveSource('a', title: 'De pc'); // conflicto
      await pc.saveSource('b', title: 'B de pc'); // gana pc
      pc.at(7);
      await pc.saveSource('nuevo', spaceId: 'sp2');

      tel.at(9);
      final preview = await tel.previewFrom(pc);
      final result = await tel.mergeFrom(pc);

      expect(preview.newItems, result.itemsAdded);
      expect(preview.itemsToUpdate, result.itemsUpdated);
      expect(preview.fieldsToUpdate, result.fieldsUpdated);
      expect(preview.conflicts, result.conflictsRecorded);
      expect(preview.newSpaces, result.spacesAdded);
      // Y no es una comparación de ceros.
      expect(result.itemsAdded, 1);
      expect(result.itemsUpdated, 2);
      expect(result.conflictsRecorded, 1);
      expect(result.spacesAdded, 1);
      expect(preview.hasNothingNew, isFalse);
    });

    test('una copia que solo cambia campos no está vacía, hasta que se '
        'fusiona', () async {
      await shareItem();
      pc.at(5);
      await pc.saveSource('a', title: 'Editado en pc');

      final before = await tel.previewFrom(pc);
      expect(before.newItems, 0);
      expect(before.fieldsToUpdate, 1);
      expect(before.itemsToUpdate, 1);
      expect(before.hasNothingNew, isFalse);

      await tel.mergeFrom(pc);

      final after = await tel.previewFrom(pc);
      expect(after.hasNothingNew, isTrue);
      expect(after.commonItems, 1);
    });

    test('una copia que solo trae un conflicto tampoco está vacía', () async {
      await shareItem();
      tel.at(7);
      await tel.saveSource('a', title: 'De tel, más reciente');
      pc.at(5);
      await pc.saveSource('a', title: 'De pc');

      // Gana lo de acá, así que no cambia ningún campo: solo se guardaría el
      // conflicto.
      final preview = await tel.previewFrom(pc);

      expect(preview.fieldsToUpdate, 0);
      expect(preview.conflicts, 1);
      expect(preview.hasNothingNew, isFalse);
    });

    test('la vista previa no escribe: ni versiones ni conflictos', () async {
      await shareItem();
      tel.at(5);
      await tel.saveSource('a', title: 'De tel');
      pc.at(7);
      await pc.saveSource('a', title: 'De pc');
      final before = await tel.counts();

      final preview = await tel.previewFrom(pc);

      expect(preview.conflicts, 1);
      expect(await tel.counts(), before);
      expect((await tel.entry('a')).title, 'De tel');
    });
  });

  group('atomicidad', () {
    test('si algo falla a la mitad no queda nada escrito', () async {
      // La copia trae un elemento en un espacio que no existe: una base rota.
      // Y un espacio bueno, que se escribe ANTES de llegar al elemento roto: si
      // no fuera una sola transacción, quedaría.
      await pc.addSpace('sp-nuevo', 'Nuevo');
      await pc.saveSource('bueno');
      await pc.db.customStatement('PRAGMA foreign_keys = OFF');
      await pc.db.customStatement(
        '''
        INSERT INTO item (id, title, kind, state, created_at, updated_at,
                          device_id, space_id)
        VALUES ('huerfano', 'Roto', 'note', 'inbox', 1, 1, 'pc', 'no-existe')''',
      );
      await tel.saveSource('mio');
      final before = await tel.counts();

      await expectLater(tel.mergeFrom(pc), throwsA(isA<Object>()));

      expect(await tel.counts(), before);
      await expectNothingLeftOver(tel);
      // Y la bóveda sigue sirviendo: se puede fusionar otra copia.
      final other = await TestVault.create(deviceId: 'otra');
      addTearDown(other.dispose);
      await other.saveSource('sano');
      expect((await tel.mergeFrom(other)).itemsAdded, 1);
    });
  });

  group('las columnas que se copian', () {
    test('cubren las tablas enteras: una columna nueva no se pierde', () async {
      Future<Set<String>> columnsOf(String table) async => {
        for (final r
            in await tel.db.customSelect('PRAGMA table_info($table)').get())
          r.read<String>('name'),
      };

      expect(kItemColumns.toSet(), await columnsOf('item'));
      expect(kNoteColumns.toSet(), await columnsOf('note'));
      expect(kSourceColumns.toSet(), await columnsOf('source'));
      expect(kFieldVersionColumns.toSet(), await columnsOf('field_version'));
    });

    test('cada campo que se fusiona existe donde dice', () async {
      for (final field in kMergeFields) {
        final columns = {
          for (final r
              in await tel.db
                  .customSelect('PRAGMA table_info(${field.table})')
                  .get())
            r.read<String>('name'),
        };
        expect(columns, contains(field.column), reason: field.name);
        expect(columns, contains(field.keyColumn), reason: field.name);
      }
    });

    test('son todos los campos versionados menos el texto de las formas', () {
      expect(kMergeFields.map((f) => f.name).toSet(), {
        EntryField.title,
        EntryField.subtitle,
        EntryField.notes,
        EntryField.spaceId,
        EntryField.state,
        EntryField.deletedAt,
        EntryField.noteKind,
        EntryField.maturity,
        EntryField.originUrl,
        EntryField.authorName,
        EntryField.authorUrl,
        EntryField.publishedAt,
        EntryField.originalBlobPath,
      });
      expect(mergeFieldNamed(EntryField.rendition('x')), isNull);
      expect(mergeFieldNamed(EntryField.title)!.table, 'item');
    });
  });
}
