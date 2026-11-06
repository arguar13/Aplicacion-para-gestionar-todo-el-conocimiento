import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';

import '../../../../support/fake_index_repository.dart';
import '../../../../support/time_growth.dart';
import 'index_screen_harness.dart';

/// La escala de la pantalla del Índice (F46, paso 3), medida por crecimiento
/// y no en milisegundos: con ocho veces más documentos o más capítulos, lo
/// que se ve cuesta casi lo mismo, porque la pantalla lee y dibuja de a lo que
/// entra.
void main() {
  /// Un Índice con [topics] temas de [perTopic] documentos cada uno, y el
  /// primero con un libro de [chapters] capítulos.
  FakeIndexRepository vault({
    required int perTopic,
    int topics = 8,
    int chapters = 40,
  }) {
    final repo = FakeIndexRepository();
    for (var t = 0; t < topics; t++) {
      final id = 'tema$t';
      repo.spaces[id] = 'Tema $t';
      for (var d = 0; d < perTopic; d++) {
        repo.documents.add(
          indexDocument(
            '$id-$d',
            'Documento ${d.toString().padLeft(5, '0')} del tema $t',
            spaces: [id],
            chapters: 3,
          ),
        );
      }
    }
    repo.entries['tema0-0'] = indexChapters('tema0-0', [
      for (var i = 0; i < chapters; i++) (1 + i % 3, 'Capítulo $i'),
    ]);
    return repo;
  }

  /// Lo que tarda en abrirse el Índice sobre [repo] hasta quedar quieto, en
  /// microsegundos. Después lo saca, para que la vuelta siguiente arme todo
  /// de nuevo.
  Future<int> open(
    WidgetTester tester,
    FakeIndexRepository repo, {
    Future<void> Function(IndexScreenHarness harness)? then,
  }) async {
    final harness = IndexScreenHarness(repo);
    final watch = Stopwatch()..start();
    await harness.pump(tester);
    await then?.call(harness);
    final took = watch.elapsedMicroseconds;
    await tester.pumpWidget(const SizedBox());
    return took;
  }

  testWidgets('abrir el Índice: ocho veces más documentos cuestan casi lo '
      'mismo, no ocho veces más', (tester) async {
    final small = vault(perTopic: 50);
    final big = vault(perTopic: 400);
    addTearDown(small.dispose);
    addTearDown(big.dispose);

    final growth = await timeGrowth(
      () => open(tester, small),
      () => open(tester, big),
    );

    expect(growth, lessThan(3));
    // Y de los ocho temas se leyeron solo los que llegaron a la pantalla.
    expect(
      big.calls.where((c) => c.startsWith('documentsOf:')).toSet().length,
      lessThan(8),
    );
  });

  testWidgets('desplegar un libro: ocho veces más capítulos cuestan mucho '
      'menos que ocho veces más', (tester) async {
    final small = vault(perTopic: 20, chapters: 1000);
    final big = vault(perTopic: 20, chapters: 8000);
    addTearDown(small.dispose);
    addTearDown(big.dispose);

    Future<void> unfold(IndexScreenHarness harness) async {
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IndexDocumentRow && w.document.id == 'tema0-0',
        ),
      );
      await tester.pumpAndSettle();
      expect(indexEntry('Capítulo 0'), findsOneWidget);
    }

    final growth = await timeGrowth(
      () => open(tester, small, then: unfold),
      () => open(tester, big, then: unfold),
    );

    expect(growth, lessThan(4));
  });

  testWidgets('un cambio en vivo vuelve a dibujar solo lo suyo: con ocho '
      'veces más documentos cuesta casi lo mismo', (tester) async {
    Future<int> change(int perTopic) async {
      final repo = vault(perTopic: perTopic);
      final harness = IndexScreenHarness(repo);
      await harness.pump(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IndexDocumentRow && w.document.id == 'tema0-0',
        ),
      );
      await tester.pumpAndSettle();

      repo.entries['tema0-0'] = [
        ...indexChapters('tema0-0', [(1, 'Recién llegado')], firstKey: 0),
        ...repo.entries['tema0-0']!,
      ];
      final watch = Stopwatch()..start();
      repo.changed();
      await tester.pumpAndSettle();
      final took = watch.elapsedMicroseconds;
      expect(indexEntry('Recién llegado'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await repo.dispose();
      return took;
    }

    final growth = await timeGrowth(() => change(50), () => change(400));

    expect(growth, lessThan(3));
  });
}
