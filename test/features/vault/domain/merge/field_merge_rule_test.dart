import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/domain/merge/field_merge_rule.dart';

/// La regla que decide, campo a campo, qué versión queda al fusionar (F11).
///
/// Es una función pura: cada rama se prueba con las dos versiones a mano. Las
/// horas van en minutos desde un mismo punto para que se lea quién es más
/// reciente sin hacer cuentas.
void main() {
  DateTime at(int minutes) => DateTime.utc(2026, 9, 20, 12, minutes);

  FieldStamp stamp(
    String device,
    int minutes, {
    String? baseDevice,
    int? baseMinutes,
  }) => FieldStamp(
    updatedAt: at(minutes),
    deviceId: device,
    baseDeviceId: baseDevice,
    baseUpdatedAt: baseMinutes == null ? null : at(baseMinutes),
  );

  // El elemento entero, para cuando ningún lado tiene versión del campo.
  final itemA = stamp('tel', 1);
  final itemB = stamp('pc', 2);

  FieldDecision decide(
    FieldStamp? local,
    FieldStamp? incoming, {
    bool differ = true,
    FieldStamp? localItem,
    FieldStamp? incomingItem,
  }) => FieldMergeRule.decide(
    valuesDiffer: differ,
    local: local,
    incoming: incoming,
    localItem: localItem ?? itemA,
    incomingItem: incomingItem ?? itemB,
  );

  group('valores iguales', () {
    test('no hay nada que hacer, sean cuales sean las versiones', () {
      for (final (local, incoming) in [
        (null, null),
        (stamp('tel', 5), null),
        (null, stamp('pc', 5)),
        (stamp('tel', 5), stamp('pc', 9)),
        (stamp('tel', 5), stamp('tel', 9)),
      ]) {
        expect(decide(local, incoming, differ: false), FieldDecision.same);
      }
    });
  });

  group('sin versión: el valor de partida', () {
    test('si solo la copia tiene versión, la modificó ella y gana', () {
      expect(decide(null, stamp('pc', 5)), FieldDecision.takeIncoming);
    });

    test('si solo esta bóveda tiene versión, la modificó ella y se queda', () {
      expect(decide(stamp('tel', 5), null), FieldDecision.keepLocal);
    });

    test('ni siquiera una versión vieja pierde contra un elemento nuevo', () {
      // El elemento de la copia es más reciente, pero eso es de OTRO campo: la
      // fecha del elemento solo desempata cuando ningún lado tiene versión.
      expect(
        decide(
          stamp('tel', 1),
          null,
          localItem: stamp('tel', 1),
          incomingItem: stamp('pc', 50),
        ),
        FieldDecision.keepLocal,
      );
    });

    test('si ninguna tiene, gana el elemento modificado más reciente', () {
      expect(
        decide(
          null,
          null,
          localItem: stamp('legacy', 1),
          incomingItem: stamp('legacy', 2),
        ),
        FieldDecision.takeIncoming,
      );
      expect(
        decide(
          null,
          null,
          localItem: stamp('legacy', 9),
          incomingItem: stamp('legacy', 2),
        ),
        FieldDecision.keepLocal,
      );
    });

    test('ninguna tiene y los elementos empatan: desempata el dispositivo', () {
      expect(
        decide(
          null,
          null,
          localItem: stamp('aaa', 5),
          incomingItem: stamp('zzz', 5),
        ),
        FieldDecision.takeIncoming,
      );
      expect(
        decide(
          null,
          null,
          localItem: stamp('zzz', 5),
          incomingItem: stamp('aaa', 5),
        ),
        FieldDecision.keepLocal,
      );
    });

    test('ninguna tiene y empatan del todo: se queda la de acá', () {
      expect(
        decide(
          null,
          null,
          localItem: stamp('legacy', 5),
          incomingItem: stamp('legacy', 5),
        ),
        FieldDecision.keepLocal,
      );
    });

    test('y nunca es un conflicto: no se sabe quién es', () {
      for (final decision in [
        decide(null, null),
        decide(null, stamp('pc', 5)),
        decide(stamp('tel', 5), null),
      ]) {
        expect(decision.isConflict, isFalse);
      }
    });
  });

  group('dispositivo desconocido (legacy)', () {
    test('gana la más reciente, sin conflicto', () {
      expect(
        decide(stamp('legacy', 3), stamp('pc', 7)),
        FieldDecision.takeIncoming,
      );
      expect(
        decide(stamp('tel', 7), stamp('legacy', 3)),
        FieldDecision.keepLocal,
      );
      expect(
        decide(stamp('legacy', 7), stamp('legacy', 3)),
        FieldDecision.keepLocal,
      );
    });

    test('el marcador del espejo de F3 cuenta como desconocido', () {
      expect(
        decide(stamp('f3-espejo-sin-sync', 3), stamp('pc', 7)),
        FieldDecision.takeIncoming,
      );
    });

    test('aunque las dos versiones parezcan concurrentes', () {
      // Sin la excepción sería conflicto: dispositivos distintos, sin base.
      expect(decide(stamp('legacy', 9), stamp('pc', 2)).isConflict, isFalse);
    });
  });

  group('el mismo dispositivo', () {
    test('una edición sigue a la otra: gana la más reciente', () {
      expect(
        decide(stamp('tel', 3), stamp('tel', 7)),
        FieldDecision.takeIncoming,
      );
      expect(decide(stamp('tel', 7), stamp('tel', 3)), FieldDecision.keepLocal);
    });

    test('con la misma hora se queda la de acá', () {
      expect(decide(stamp('tel', 5), stamp('tel', 5)), FieldDecision.keepLocal);
    });

    test('no es un conflicto aunque las bases no coincidan', () {
      expect(
        decide(
          stamp('tel', 3, baseDevice: 'pc', baseMinutes: 1),
          stamp('tel', 7, baseDevice: 'tab', baseMinutes: 2),
        ).isConflict,
        isFalse,
      );
    });
  });

  group('linaje', () {
    test('la copia se escribió sobre la de acá: gana, sin conflicto', () {
      // tel escribió a los 3; pc la recibió y la cambió a los 7.
      expect(
        decide(
          stamp('tel', 3),
          stamp('pc', 7, baseDevice: 'tel', baseMinutes: 3),
        ),
        FieldDecision.takeIncoming,
      );
    });

    test(
      'la de acá se escribió sobre la de la copia: se queda, sin conflicto',
      () {
        expect(
          decide(
            stamp('tel', 7, baseDevice: 'pc', baseMinutes: 3),
            stamp('pc', 3),
          ),
          FieldDecision.keepLocal,
        );
      },
    );

    test(
      'el linaje manda sobre el reloj: el que sigue gana aunque marque menos',
      () {
        // El reloj de pc está atrasado: su edición dice las 2, pero se hizo
        // sobre la de tel de las 5.
        expect(
          decide(
            stamp('tel', 5),
            stamp('pc', 2, baseDevice: 'tel', baseMinutes: 5),
          ),
          FieldDecision.takeIncoming,
        );
        expect(
          decide(
            stamp('tel', 2, baseDevice: 'pc', baseMinutes: 5),
            stamp('pc', 5),
          ),
          FieldDecision.keepLocal,
        );
      },
    );

    test('teléfono→compu→teléfono no es un conflicto, en ningún sentido', () {
      // tel escribe (t=1) → pc la edita (t=4, base tel@1) → tel la edita otra
      // vez (t=8, base pc@4).
      final firstTel = stamp('tel', 1);
      final pcEdit = stamp('pc', 4, baseDevice: 'tel', baseMinutes: 1);
      final secondTel = stamp('tel', 8, baseDevice: 'pc', baseMinutes: 4);

      expect(decide(firstTel, pcEdit), FieldDecision.takeIncoming);
      expect(decide(pcEdit, secondTel), FieldDecision.takeIncoming);
      expect(decide(secondTel, pcEdit), FieldDecision.keepLocal);
      expect(decide(pcEdit, firstTel), FieldDecision.keepLocal);
    });

    test(
      'las ediciones seguidas de un mismo dispositivo conservan la base',
      () {
        // pc edita dos veces sobre la de tel: su base sigue siendo tel@1.
        final firstTel = stamp('tel', 1);
        final pcSecondEdit = stamp('pc', 9, baseDevice: 'tel', baseMinutes: 1);

        expect(decide(firstTel, pcSecondEdit), FieldDecision.takeIncoming);
      },
    );
  });

  group('conflicto real', () {
    test('dos dispositivos, sin que ninguno parta del otro: gana la más '
        'reciente y se guarda la otra', () {
      expect(
        decide(stamp('tel', 3), stamp('pc', 7)),
        FieldDecision.conflictTakeIncoming,
      );
      expect(
        decide(stamp('tel', 7), stamp('pc', 3)),
        FieldDecision.conflictKeepLocal,
      );
    });

    test('con la misma hora desempata el dispositivo, igual en los dos '
        'sentidos', () {
      // «tel» > «pc»: gana tel, se la fusione desde donde se la fusione.
      expect(
        decide(stamp('tel', 5), stamp('pc', 5)),
        FieldDecision.conflictKeepLocal,
      );
      expect(
        decide(stamp('pc', 5), stamp('tel', 5)),
        FieldDecision.conflictTakeIncoming,
      );
    });

    test(
      'las dos bóvedas eligen el mismo valor al fusionarse una con la otra',
      () {
        final tel = stamp('tel', 3);
        final pc = stamp('pc', 7);

        final inTel = decide(tel, pc); // copia de pc en tel
        final inPc = decide(pc, tel); // copia de tel en pc

        // En tel gana el de pc (lo toma) y en pc gana el de pc (se lo queda).
        expect(inTel.takesIncoming, isTrue);
        expect(inPc.keepsLocal, isTrue);
      },
    );

    test('la misma base en las dos no las une: son hermanas, no una hija de '
        'la otra', () {
      // Las dos se escribieron sobre tel@1, cada una por su lado.
      expect(
        decide(
          stamp('pc', 4, baseDevice: 'tel', baseMinutes: 1),
          stamp('tab', 6, baseDevice: 'tel', baseMinutes: 1),
        ),
        FieldDecision.conflictTakeIncoming,
      );
    });

    test('una base que coincide solo en la hora, o solo en el dispositivo, '
        'no es linaje', () {
      // Misma hora, otro dispositivo.
      expect(
        decide(
          stamp('tel', 3),
          stamp('pc', 7, baseDevice: 'tab', baseMinutes: 3),
        ).isConflict,
        isTrue,
      );
      // Mismo dispositivo, otra hora.
      expect(
        decide(
          stamp('tel', 3),
          stamp('pc', 7, baseDevice: 'tel', baseMinutes: 2),
        ).isConflict,
        isTrue,
      );
    });

    test('una edición que pasó por un tercer dispositivo se trata como '
        'concurrente: un conflicto de más y no una edición pisada', () {
      // tel@1 → pc@4 (base tel@1) → tab@6 (base pc@4). Vista desde tel, que
      // sigue en tel@1, la cadena no se puede reconstruir.
      expect(
        decide(
          stamp('tel', 1),
          stamp('tab', 6, baseDevice: 'pc', baseMinutes: 4),
        ),
        FieldDecision.conflictTakeIncoming,
      );
    });
  });

  group('FieldDecision', () {
    test('cada decisión dice qué hace', () {
      expect(FieldDecision.same.takesIncoming, isFalse);
      expect(FieldDecision.same.keepsLocal, isFalse);
      expect(FieldDecision.same.isConflict, isFalse);

      expect(FieldDecision.keepLocal.keepsLocal, isTrue);
      expect(FieldDecision.keepLocal.isConflict, isFalse);

      expect(FieldDecision.takeIncoming.takesIncoming, isTrue);
      expect(FieldDecision.takeIncoming.isConflict, isFalse);

      expect(FieldDecision.conflictKeepLocal.keepsLocal, isTrue);
      expect(FieldDecision.conflictKeepLocal.isConflict, isTrue);

      expect(FieldDecision.conflictTakeIncoming.takesIncoming, isTrue);
      expect(FieldDecision.conflictTakeIncoming.isConflict, isTrue);
    });
  });

  group('FieldStamp', () {
    test('la más reciente lo es por la hora y, si empatan, por el '
        'dispositivo', () {
      expect(stamp('a', 5).isNewerThan(stamp('b', 4)), isTrue);
      expect(stamp('a', 4).isNewerThan(stamp('b', 5)), isFalse);
      expect(stamp('b', 5).isNewerThan(stamp('a', 5)), isTrue);
      expect(stamp('a', 5).isNewerThan(stamp('b', 5)), isFalse);
      expect(stamp('a', 5).isNewerThan(stamp('a', 5)), isFalse);
    });

    test('una versión sin base no parte de nada', () {
      expect(stamp('pc', 7).isBasedOn(stamp('tel', 3)), isFalse);
      expect(stamp('pc', 7).isBasedOn(stamp('pc', 7)), isFalse);
    });

    test('es de dispositivo desconocido el legacy y el espejo de F3', () {
      expect(stamp('legacy', 1).isLegacy, isTrue);
      expect(stamp('f3-espejo-sin-sync', 1).isLegacy, isTrue);
      expect(stamp('tel', 1).isLegacy, isFalse);
    });

    test('dos versiones con lo mismo son iguales', () {
      expect(
        stamp('pc', 4, baseDevice: 'tel', baseMinutes: 1),
        stamp('pc', 4, baseDevice: 'tel', baseMinutes: 1),
      );
      expect(stamp('pc', 4), isNot(stamp('pc', 5)));
      expect(stamp('pc', 4).hashCode, stamp('pc', 4).hashCode);
    });
  });
}
