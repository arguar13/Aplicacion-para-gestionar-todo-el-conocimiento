import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/features/health/domain/entities/grown_note.dart';
import 'package:sinapsis/features/health/domain/entities/health_thresholds.dart';
import 'package:sinapsis/features/health/domain/entities/note_composition.dart';

NoteComposition _composition({int atomic = 0, int living = 0, int map = 0}) =>
    NoteComposition(
      byKind: {
        NoteKind.atomic: atomic,
        NoteKind.living: living,
        NoteKind.map: map,
      },
      byMaturity: const {},
    );

void main() {
  group('NoteComposition', () {
    test('suma las notas de todos los subtipos', () {
      expect(_composition(atomic: 5, living: 3, map: 1).total, 9);
    });

    test('un subtipo o una madurez que falta cuenta cero, no rompe', () {
      const composition = NoteComposition.empty;

      expect(composition.total, 0);
      expect(composition.kindCount(NoteKind.atomic), 0);
      expect(composition.maturityCount(NoteMaturity.mature), 0);
    });

    group('fragmentsOutweighSynthesis', () {
      test('cientos de atómicas y un puñado de vivas: avisa', () {
        expect(
          _composition(atomic: 300, living: 8).fragmentsOutweighSynthesis,
          isTrue,
        );
      });

      test('muchas atómicas y ninguna viva: avisa', () {
        expect(
          _composition(
            atomic: kFragmentWarningMinAtomic,
          ).fragmentsOutweighSynthesis,
          isTrue,
        );
      });

      test('una bóveda joven, con pocas atómicas, no es una señal', () {
        expect(
          _composition(
            atomic: kFragmentWarningMinAtomic - 1,
          ).fragmentsOutweighSynthesis,
          isFalse,
        );
      });

      test('en la proporción tolerada, no avisa; un poco más allá, sí', () {
        const living = 4;
        const atLimit = kFragmentWarningRatio * living;

        expect(
          _composition(
            atomic: atLimit,
            living: living,
          ).fragmentsOutweighSynthesis,
          isFalse,
        );
        expect(
          _composition(
            atomic: atLimit + 1,
            living: living,
          ).fragmentsOutweighSynthesis,
          isTrue,
        );
      });

      test('las notas mapa no cuentan en la proporción', () {
        expect(
          _composition(
            atomic: 30,
            living: 10,
            map: 100,
          ).fragmentsOutweighSynthesis,
          isFalse,
        );
      });
    });
  });

  test('GrownNote.growth suma bloques y relaciones nuevas', () {
    const note = GrownNote(
      itemId: 'a',
      title: 'A',
      maturity: NoteMaturity.seed,
      newBlocks: 3,
      newRelations: 2,
    );

    expect(note.growth, 5);
  });

  test('la ventana de crecimiento es de una semana', () {
    expect(kGrowthWindow, const Duration(days: 7));
  });
}
