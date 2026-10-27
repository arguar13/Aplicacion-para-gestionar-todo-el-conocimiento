import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/content_trash/data/repositories/content_trash_repository_impl.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../../../support/test_vault.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// Los hechos fechados dentro de un documento viajan en la fusión de bóvedas
/// (F40): se unen por su identificador, no se repiten aunque dos dispositivos
/// los hayan leído cada uno por su cuenta, conservan su cita si el texto llegó,
/// y lo que la persona dijo que «no era» no vuelve.
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

  /// Dos fuentes, «a» y «b», que las dos bóvedas tienen.
  Future<void> shareItems() async {
    tel.at(1);
    await tel.saveSource('a');
    await tel.saveSource('b');
    pc.at(2);
    await pc.mergeFrom(tel);
  }

  Future<void> addRun(TestVault vault, String id, String itemId) =>
      vault.db.customStatement(
        'INSERT INTO ai_runs (id, item_id, started_at) '
        "VALUES ('$id', '$itemId', 1790000000)",
      );

  Future<void> reject(TestVault vault, String id, String subjectId) =>
      vault.db.customStatement(
        'INSERT INTO ai_rejections (id, kind, item_id, fingerprint, '
        'subject_id, created_at) VALUES '
        "('$id', 'datedEvent', 'a', 'huella', '$subjectId', 1790000000)",
      );

  Future<Map<String, Map<String, Object?>>> eventsOf(TestVault vault) async => {
    for (final r
        in await vault.db
            .customSelect('SELECT * FROM dated_events ORDER BY id')
            .get())
      r.read<String>('id'): r.data,
  };

  test('entra el que acá no hay, con su fecha, su fin y su cita', () async {
    await shareItems();
    pc.at(5);
    await pc.addDatedEvent(
      'guerra',
      'a',
      title: 'La Gran Guerra',
      year: 1914,
      excerpt: 'extracto',
      start: 2,
      end: 8,
      renditionId: 'rend-a',
    );
    await pc.db.customStatement(
      'UPDATE dated_events SET date_end_year = 1918, date_end_month = 1, '
      "date_end_day = 1, date_end_precision = 'year', date_is_circa = 1",
    );

    tel.at(9);
    await tel.mergeFrom(pc);

    final row = (await eventsOf(tel))['guerra']!;
    expect(row['title'], 'La Gran Guerra');
    expect(row['item_id'], 'a');
    expect(row['date_from_year'], 1914);
    expect(row['date_end_year'], 1918);
    expect(row['date_is_circa'], 1);
    expect(row['rendition_id'], 'rend-a');
    expect((row['start_offset'], row['end_offset']), (2, 8));
    expect(row['excerpt'], 'extracto');
    expect(row['origin'], 'user');
  });

  test('lo que se unió se cuenta en el resultado: una fusión que solo trajo '
      'hechos y marcas no es «no cambió nada»', () async {
    await shareItems();
    pc.at(5);
    await pc.addDatedEvent('hecho', 'a');
    await pc.addStudyMark('marca', 'a');

    tel.at(9);
    final result = await tel.mergeFrom(pc);

    expect(result.datedEventsAdded, 1);
    expect(result.studyMarksAdded, 1);
    expect(result.changedNothing, isFalse);
    tel.at(10);
    expect((await tel.mergeFrom(pc)).changedNothing, isTrue);
  });

  test('el mismo id no entra dos veces, y fusionar dos veces no duplica '
      'nada', () async {
    await shareItems();
    tel.at(4);
    await tel.addDatedEvent('mismo', 'a', title: 'De acá');
    pc.at(5);
    await pc.addDatedEvent('mismo', 'a', title: 'De la copia');
    await pc.addDatedEvent('solo-pc', 'b', year: 1900);

    tel.at(9);
    await tel.mergeFrom(pc);
    tel.at(10);
    await tel.mergeFrom(pc);

    final events = await eventsOf(tel);
    expect(events.keys, {'mismo', 'solo-pc'});
    expect(events['mismo']!['title'], 'De acá');
  });

  test('el mismo hecho leído por cada dispositivo no se repite: misma fecha '
      'y misma cita en el mismo elemento', () async {
    await shareItems();
    tel.at(4);
    await tel.addDatedEvent('tel-1', 'a', year: 1831, excerpt: 'zarpó');
    await tel.addDatedEvent('tel-2', 'a', year: 1831, title: 'Sin cita');
    pc.at(5);
    await pc.addDatedEvent('pc-1', 'a', year: 1831, excerpt: 'zarpó');
    // Sin cita: el mismo título es el mismo hecho.
    await pc.addDatedEvent('pc-2', 'a', year: 1831, title: 'sin CITA');
    // Otra fecha, u otra cita, u otro elemento: son otros.
    await pc.addDatedEvent('pc-3', 'a', year: 1832, excerpt: 'zarpó');
    await pc.addDatedEvent('pc-4', 'a', year: 1831, excerpt: 'volvió');
    await pc.addDatedEvent('pc-5', 'b', year: 1831, excerpt: 'zarpó');

    tel.at(9);
    await tel.mergeFrom(pc);

    expect((await eventsOf(tel)).keys, {
      'tel-1',
      'tel-2',
      'pc-3',
      'pc-4',
      'pc-5',
    });
  });

  test('uno con cita no es el mismo que uno sin cita, aunque se llamen '
      'igual', () async {
    await shareItems();
    tel.at(4);
    await tel.addDatedEvent('sin-cita', 'a', title: 'Zarpa', year: 1831);
    pc.at(5);
    await pc.addDatedEvent(
      'con-cita',
      'a',
      title: 'Zarpa',
      year: 1831,
      excerpt: 'zarpó',
    );

    tel.at(9);
    await tel.mergeFrom(pc);

    expect((await eventsOf(tel)).keys, {'sin-cita', 'con-cita'});
  });

  test('la misma cita con otro mes, otro día u otra precisión es otro '
      'hecho', () async {
    await shareItems();
    tel.at(4);
    await tel.addDatedEvent('base', 'a', year: 1831, excerpt: 'zarpó');
    pc.at(5);
    await pc.addDatedEvent('otro-mes', 'a', year: 1831, excerpt: 'zarpó');
    await pc.addDatedEvent('otro-dia', 'a', year: 1831, excerpt: 'zarpó');
    await pc.addDatedEvent('otra-precision', 'a', year: 1831, excerpt: 'zarpó');
    await pc.db.customStatement(
      "UPDATE dated_events SET date_from_month = 12 WHERE id = 'otro-mes'",
    );
    await pc.db.customStatement(
      "UPDATE dated_events SET date_from_day = 27 WHERE id = 'otro-dia'",
    );
    await pc.db.customStatement(
      "UPDATE dated_events SET date_precision = 'decade' "
      "WHERE id = 'otra-precision'",
    );

    tel.at(9);
    await tel.mergeFrom(pc);

    expect((await eventsOf(tel)).keys, {
      'base',
      'otro-mes',
      'otro-dia',
      'otra-precision',
    });
  });

  test('uno de un elemento que acá no existe no entra; con un elemento '
      'nuevo, sí', () async {
    await shareItems();
    pc.at(5);
    await pc.saveSource('c');
    await pc.addDatedEvent('del-nuevo', 'c', year: 1700);

    tel.at(9);
    final result = await tel.mergeFrom(pc);

    expect(result.itemsAdded, 1);
    expect((await eventsOf(tel))['del-nuevo']!['item_id'], 'c');
  });

  group('la IA', () {
    test('conserva su pasada si la pasada llegó', () async {
      await shareItems();
      pc.at(5);
      await addRun(pc, 'pasada', 'a');
      await pc.addDatedEvent(
        'ia',
        'a',
        origin: ContentOrigin.ai,
        aiRunId: 'pasada',
        excerpt: 'cita',
      );

      tel.at(9);
      await tel.mergeFrom(pc);

      final row = (await eventsOf(tel))['ia']!;
      expect(row['origin'], 'ai');
      expect(row['ai_run_id'], 'pasada');
    });

    test('uno de la IA que acá se quitó («no era») no vuelve', () async {
      await shareItems();
      pc.at(5);
      await addRun(pc, 'pasada', 'a');
      await pc.addDatedEvent(
        'quitado',
        'a',
        origin: ContentOrigin.ai,
        aiRunId: 'pasada',
        excerpt: 'cita',
      );
      await pc.addDatedEvent(
        'otro',
        'a',
        year: 1900,
        origin: ContentOrigin.ai,
        aiRunId: 'pasada',
        excerpt: 'otra cita',
      );
      tel.at(6);
      await reject(tel, 'no-era', 'quitado');

      tel.at(9);
      await tel.mergeFrom(pc);

      expect((await eventsOf(tel)).keys, {'otro'});
    });

    test('lo que «no era» en la copia también cuenta, aunque acá no se '
        'sepa', () async {
      await shareItems();
      pc.at(5);
      await addRun(pc, 'pasada', 'a');
      await pc.addDatedEvent(
        'quitado-en-pc',
        'a',
        origin: ContentOrigin.ai,
        aiRunId: 'pasada',
      );
      await reject(pc, 'no-era-pc', 'quitado-en-pc');

      tel.at(9);
      await tel.mergeFrom(pc);

      expect(await eventsOf(tel), isEmpty);
    });

    test('un hecho de la persona con el mismo id que un «no era» sí entra '
        '(la lápida es solo para lo de la IA)', () async {
      await shareItems();
      pc.at(5);
      await pc.addDatedEvent('mio', 'a');
      tel.at(6);
      await reject(tel, 'no-era', 'mio');

      tel.at(9);
      await tel.mergeFrom(pc);

      expect((await eventsOf(tel)).keys, {'mio'});
    });

    test('uno de la IA que en la copia la persona adoptó es suyo también '
        'acá', () async {
      await shareItems();
      tel.at(4);
      await addRun(tel, 'pasada', 'a');
      await tel.addDatedEvent(
        'ia',
        'a',
        title: 'Como lo leyó la IA',
        origin: ContentOrigin.ai,
        aiRunId: 'pasada',
        excerpt: 'cita',
      );
      pc.at(5);
      await pc.mergeFrom(tel);
      await pc.db.customStatement(
        "UPDATE dated_events SET origin = 'user', ai_run_id = NULL, "
        "title = 'Editado en pc'",
      );

      tel.at(9);
      await tel.mergeFrom(pc);

      final row = (await eventsOf(tel))['ia']!;
      expect(row['origin'], 'user');
      expect(row['ai_run_id'], isNull);
      // Su título no se toca: la unión no pisa nada.
      expect(row['title'], 'Como lo leyó la IA');
    });
  });

  group('la cita', () {
    test('si la copia leyó otro texto del elemento, la cita va a la forma que '
        'guardó ese texto', () async {
      await shareItems();
      pc.at(5);
      await pc.saveSource('a', text: 'Otro texto, editado en pc.');
      await pc.addDatedEvent(
        'citado',
        'a',
        excerpt: 'Otro',
        start: 0,
        end: 4,
        renditionId: 'rend-a',
      );

      tel.at(9);
      await tel.mergeFrom(pc);

      final extra = (await tel.renditionsOf(
        'a',
      )).singleWhere((r) => r.id != 'rend-a');
      expect(extra.content, 'Otro texto, editado en pc.');
      final row = (await eventsOf(tel))['citado']!;
      expect(row['rendition_id'], extra.id);
      expect((row['start_offset'], row['end_offset']), (0, 4));
    });

    test('si el texto de la copia acá se soltó, el hecho entra sin la '
        'posición pero con su fecha, su título y su fragmento', () async {
      tel.at(1);
      await tel.saveSource('libro', text: 'Roma.', originalName: 'roma.pdf');
      pc.at(2);
      await pc.mergeFrom(tel);
      pc.at(5);
      await pc.addDatedEvent(
        'citado',
        'libro',
        title: 'Cae Roma',
        year: 476,
        excerpt: 'Roma',
        start: 0,
        end: 4,
        renditionId: 'rend-libro',
      );
      // Acá se soltó el texto: queda en la papelera del contenido.
      tel.at(6);
      await ContentTrashRepositoryImpl(
        database: tel.db,
        files: InMemoryFileStore(),
        telemetry: _MockTelemetry(),
        clock: () => tel.now,
      ).keepOnlyFile('libro');

      tel.at(9);
      await tel.mergeFrom(pc);

      final row = (await eventsOf(tel))['citado']!;
      expect(row['title'], 'Cae Roma');
      expect(row['date_from_year'], 476);
      expect(row['excerpt'], 'Roma');
      expect(row['rendition_id'], isNull);
      expect(row['start_offset'], isNull);
      expect(row['end_offset'], isNull);
    });
  });

  test('una fusión solo suma: lo de acá se queda', () async {
    await shareItems();
    tel.at(4);
    await tel.addDatedEvent('mio', 'a', title: 'Mío');
    pc.at(5);
    await pc.addDatedEvent('suyo', 'a', year: 1900, excerpt: 'cita');

    tel.at(9);
    await tel.mergeFrom(pc);

    expect((await eventsOf(tel)).keys, {'mio', 'suyo'});
    expect(await tel.count('dated_events'), 2);
  });
}
