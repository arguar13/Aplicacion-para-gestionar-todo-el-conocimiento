import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';

import '../../../../support/test_vault.dart';

/// La vista previa de unir bóvedas cuenta también lo estudiado (F36) y los
/// hechos fechados (F40), con la regla de la unión —la misma que usa al
/// escribir—. Lo que la vista previa dice y lo que la fusión hace no pueden
/// discrepar: cada caso compara la cifra con lo que la fusión después escribe.
void main() {
  late TestVault tel;
  late TestVault pc;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
    // Las dos bóvedas tienen las mismas fuentes «a» y «b», con el mismo texto.
    for (final vault in [tel, pc]) {
      await vault.saveSource('a');
      await vault.saveSource('b');
    }
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  /// La vista previa de la copia de [pc] y, después, lo que la fusión escribe:
  /// las dos cifras de lo estudiado y de los hechos tienen que coincidir.
  Future<({int marks, int events})> previewThenMerge() async {
    final preview = await tel.previewFrom(pc);
    final result = await tel.mergeFrom(pc);
    expect(
      preview.newStudyMarks,
      result.studyMarksAdded,
      reason: 'las marcas que la vista previa promete y las que entran',
    );
    expect(
      preview.newDatedEvents,
      result.datedEventsAdded,
      reason: 'los hechos que la vista previa promete y los que entran',
    );
    return (marks: preview.newStudyMarks, events: preview.newDatedEvents);
  }

  group('los hechos fechados', () {
    test(
      'el mismo id es el mismo hecho aunque se haya editado en un lado',
      () async {
        await tel.addDatedEvent('editado', 'a', title: 'De acá');
        await pc.addDatedEvent('editado', 'a', year: 1900, title: 'De allá');

        expect((await previewThenMerge()).events, 0);
      },
    );

    test(
      'la misma cita con otro mes, otro día u otra precisión es otro hecho',
      () async {
        await tel.addDatedEvent('base', 'a', year: 1831, excerpt: 'zarpó');
        await pc.addDatedEvent('otro-mes', 'a', year: 1831, excerpt: 'zarpó');
        await pc.addDatedEvent('otro-dia', 'a', year: 1831, excerpt: 'zarpó');
        await pc.addDatedEvent(
          'otra-precision',
          'a',
          year: 1831,
          excerpt: 'zarpó',
        );
        await pc.addDatedEvent('igual', 'a', year: 1831, excerpt: 'zarpó');
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

        expect((await previewThenMerge()).events, 3);
      },
    );

    test('sin cita en los dos lados, otro título es otro hecho', () async {
      await tel.addDatedEvent('tel', 'a', year: 1831, title: 'Zarpa');
      await pc.addDatedEvent('pc-otro', 'a', year: 1831, title: 'Naufraga');
      await pc.addDatedEvent('pc-igual', 'a', year: 1831, title: 'ZARPA');

      expect((await previewThenMerge()).events, 1);
    });

    test('se cuentan por su id, y el mismo id no es nuevo', () async {
      await tel.addDatedEvent('mismo', 'a');
      await pc.addDatedEvent('mismo', 'a');
      await pc.addDatedEvent('solo-pc', 'b', year: 1900);

      final preview = await tel.previewFrom(pc);

      expect(preview.newDatedEvents, 1);
    });

    test('el mismo hecho leído por cada dispositivo no es nuevo: misma fecha '
        'y misma cita, o sin cita el mismo título', () async {
      await tel.addDatedEvent('tel-1', 'a', year: 1831, excerpt: 'zarpó');
      await tel.addDatedEvent('tel-2', 'a', year: 1831, title: 'Sin cita');
      await pc.addDatedEvent('pc-1', 'a', year: 1831, excerpt: 'zarpó');
      await pc.addDatedEvent('pc-2', 'a', year: 1831, title: 'sin CITA');
      // Otra fecha, otra cita u otro elemento: son otros.
      await pc.addDatedEvent('pc-3', 'a', year: 1832, excerpt: 'zarpó');
      await pc.addDatedEvent('pc-4', 'a', year: 1831, excerpt: 'volvió');
      await pc.addDatedEvent('pc-5', 'b', year: 1831, excerpt: 'zarpó');

      expect((await previewThenMerge()).events, 3);
    });

    test(
      'el de un elemento que acá no está también cuenta: entra con él',
      () async {
        await pc.saveSource('c');
        await pc.addDatedEvent('del-nuevo', 'c', year: 1700);

        final preview = await tel.previewFrom(pc);

        expect(preview.newItems, 1);
        expect(preview.newDatedEvents, 1);
        expect((await previewThenMerge()).events, 1);
      },
    );

    test(
      'uno de la IA que acá la persona dijo que «no era» no cuenta',
      () async {
        await tel.db.customStatement(
          'INSERT INTO ai_rejections (id, kind, item_id, fingerprint, '
          'subject_id, created_at) VALUES '
          "('rej', 'datedEvent', 'a', 'huella', 'de-la-ia', 1790000000)",
        );
        await pc.addDatedEvent('de-la-ia', 'a', origin: ContentOrigin.ai);
        await pc.addDatedEvent('de-la-persona', 'a', year: 1900);

        expect((await previewThenMerge()).events, 1);
      },
    );

    test(
      'lo único nuevo puede ser un hecho: la copia no es «nada nuevo»',
      () async {
        await pc.addDatedEvent('solo', 'a');

        final preview = await tel.previewFrom(pc);

        expect(preview.hasNothingNew, isFalse);
      },
    );

    test('la copia de la misma bóveda no trae hechos nuevos', () async {
      await tel.addDatedEvent('e', 'a', excerpt: 'cita');

      final preview = await tel.previewFrom(tel);

      expect(preview.newDatedEvents, 0);
      expect(preview.hasNothingNew, isTrue);
    });
  });

  group('lo estudiado', () {
    test('el mismo id es la misma marca aunque marque otra cosa', () async {
      await tel.addStudyMark('mismo', 'a');
      await pc.addStudyMark(
        'mismo',
        'a',
        kind: StudyMarkKind.synthesis,
        start: 3,
        end: 9,
      );

      expect((await previewThenMerge()).marks, 0);
    });

    test(
      'las mismas posiciones: tienen que coincidir el comienzo y el final',
      () async {
        await tel.addStudyMark('tel', 'a', start: 2);
        await pc.addStudyMark('pc-igual', 'a', start: 2);
        await pc.addStudyMark('pc-otro-final', 'a', start: 2, end: 6);
        await pc.addStudyMark('pc-otro-comienzo', 'a', start: 1);

        expect((await previewThenMerge()).marks, 2);
      },
    );

    test(
      'se cuenta por su id, y la misma marca con otro id no es nueva',
      () async {
        await tel.addStudyMark('mismo', 'a');
        await tel.addStudyMark(
          'clave-tel',
          'a',
          kind: StudyMarkKind.keyword,
          origin: ContentOrigin.user,
          start: 2,
          end: 4,
        );
        await pc.addStudyMark('mismo', 'a');
        // Marca lo mismo que «clave-tel» con otro id: no entra dos veces.
        await pc.addStudyMark(
          'clave-pc',
          'a',
          kind: StudyMarkKind.keyword,
          origin: ContentOrigin.user,
          start: 2,
          end: 4,
        );
        // Otro tipo en las mismas posiciones, y otras posiciones: son nuevas.
        await pc.addStudyMark('sintesis', 'a', kind: StudyMarkKind.synthesis);
        await pc.addStudyMark('resumen-2', 'a', start: 6, end: 9);

        expect((await previewThenMerge()).marks, 2);
      },
    );

    test(
      'si acá el texto ya se analizó, las de la IA no cuentan; las elegidas a '
      'mano, sí',
      () async {
        await tel.addStudyMark('resumen-tel', 'a');
        await tel.addStudyAnalysis('a', until: 20);
        await pc.addStudyMark('resumen-pc', 'a', start: 6, end: 9);
        await pc.addStudyMark(
          'clave-pc',
          'a',
          kind: StudyMarkKind.keyword,
          origin: ContentOrigin.user,
          start: 6,
          end: 8,
        );
        // En «b» acá no se analizó nada: la de la IA entra.
        await pc.addStudyMark('resumen-b', 'b');

        expect((await previewThenMerge()).marks, 2);
      },
    );

    test(
      'las del texto de un elemento nuevo cuentan: la forma entra con él',
      () async {
        await pc.saveSource('c');
        await pc.addStudyMark('del-nuevo', 'c');
        await pc.addStudyMark('del-nuevo-2', 'c', start: 7, end: 9);

        expect((await previewThenMerge()).marks, 2);
      },
    );

    test('si el mismo texto está acá con otro id de forma, se cuenta contra '
        'las marcas de esa', () async {
      await tel.addRendition('a', 'r-tel', 'Un texto igual.');
      await pc.addRendition('a', 'r-pc', 'Un texto igual.');
      await tel.addStudyMark('m-tel', 'a', renditionId: 'r-tel');
      // Lo mismo que «m-tel», sobre la forma equivalente de la copia.
      await pc.addStudyMark('m-pc', 'a', renditionId: 'r-pc');
      await pc.addStudyMark(
        'm-pc-2',
        'a',
        renditionId: 'r-pc',
        start: 6,
        end: 9,
      );

      expect((await previewThenMerge()).marks, 1);
    });

    test('si el texto distinto de la copia entra como otra forma, sus marcas '
        'entran en esa', () async {
      // Mismo identificador de forma, texto distinto: la de la copia entra
      // como otra forma, y sus marcas con ella, aunque marquen lo mismo que
      // acá.
      await tel.saveSource('d', text: 'Texto de acá.');
      await pc.saveSource('d', text: 'Texto de allá.');
      await tel.addStudyMark('m-tel', 'd');
      await pc.addStudyMark('m-pc', 'd');

      final preview = await tel.previewFrom(pc);

      expect(preview.conflicts, 1);
      expect((await previewThenMerge()).marks, 1);
    });

    test(
      'lo único nuevo puede ser una marca: la copia no es «nada nuevo»',
      () async {
        await pc.addStudyMark('sola', 'a');

        final preview = await tel.previewFrom(pc);

        expect(preview.hasNothingNew, isFalse);
      },
    );
  });

  test(
    'fusionada la copia, una segunda vista previa ya no trae nada',
    () async {
      await pc.addDatedEvent('hecho', 'a', excerpt: 'cita');
      await pc.addStudyMark('marca', 'a');
      await previewThenMerge();

      final again = await tel.previewFrom(pc);

      expect(again.newDatedEvents, 0);
      expect(again.newStudyMarks, 0);
      expect(again.hasNothingNew, isTrue);
    },
  );
}
