import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/study_day_watcher.dart';

/// El aviso de que empieza otro día de estudio (F31): a las 4:00, sin que nada
/// se escriba en la base.
void main() {
  Widget app(DateTime Function() clock) => ProviderScope(
    overrides: [clockProvider.overrideWithValue(clock)],
    child: MaterialApp(
      home: StudyDayWatcher(
        child: Consumer(
          builder: (context, ref, _) =>
              Text('${ref.watch(studyDayStartProvider)}'),
        ),
      ),
    ),
  );

  testWidgets('al llegar las 4:00 cambia el día de estudio, y vuelve a '
      'esperar al siguiente', (tester) async {
    // Diez minutos antes de las 4:00 del 9 de octubre.
    var now = DateTime(2026, 10, 9, 3, 50);
    await tester.pumpWidget(app(() => now));
    expect(find.text('${DateTime(2026, 10, 8, 4)}'), findsOneWidget);

    // Pasa el tiempo: el reloj y el temporizador avanzan juntos.
    now = DateTime(2026, 10, 9, 4, 0, 1);
    await tester.pump(const Duration(minutes: 10, seconds: 2));

    expect(find.text('${DateTime(2026, 10, 9, 4)}'), findsOneWidget);

    // Y sigue vigilando: al día siguiente cambia otra vez.
    now = DateTime(2026, 10, 10, 4, 0, 1);
    await tester.pump(const Duration(hours: 24));

    expect(find.text('${DateTime(2026, 10, 10, 4)}'), findsOneWidget);
  });

  testWidgets('antes de las 4:00 no cambia nada', (tester) async {
    final now = DateTime(2026, 10, 9, 3, 50);
    await tester.pumpWidget(app(() => now));

    await tester.pump(const Duration(minutes: 5));

    expect(find.text('${DateTime(2026, 10, 8, 4)}'), findsOneWidget);
  });

  testWidgets('al cerrar la pantalla no deja ningún temporizador', (
    tester,
  ) async {
    await tester.pumpWidget(app(() => DateTime(2026, 10, 9, 3, 50)));

    await tester.pumpWidget(const SizedBox());

    // El propio test falla si queda un temporizador pendiente.
    expect(tester.hasRunningAnimations, isFalse);
  });
}
