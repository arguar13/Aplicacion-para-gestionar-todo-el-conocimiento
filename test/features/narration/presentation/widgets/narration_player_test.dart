import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/presentation/widgets/narration_player.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Un texto de tres oraciones, para tener fragmentos de sobra sobre los
/// que probar retroceder, adelantar y reiniciar.
const _threeSentences = 'Primera oración. Segunda oración. Tercera oración.';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpPlayer(
    WidgetTester tester, {
    String text = _threeSentences,
  }) async {
    harness = await LibraryHarness.create();
    await tester.pumpWidget(harness.wrap(NarrationPlayer(text: text)));
    await tester.pumpAndSettle();
  }

  testWidgets('arranca colapsado, con el botón de escuchar', (tester) async {
    await pumpPlayer(tester);

    expect(find.text(es.narrationListenAction), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('un texto vacío no muestra nada', (tester) async {
    await pumpPlayer(tester, text: '   ');

    expect(find.text(es.narrationListenAction), findsNothing);
  });

  testWidgets('tocar "escuchar" lee el primer fragmento', (tester) async {
    await pumpPlayer(tester);

    await tester.tap(find.text(es.narrationListenAction));
    await tester.pumpAndSettle();

    expect(harness.textToSpeechService.spoken, ['Primera oración.']);
    expect(find.text(es.narrationProgress(1, 3)), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('cuando termina un fragmento, sigue solo con el próximo', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await tester.tap(find.text(es.narrationListenAction));
    await tester.pumpAndSettle();

    harness.textToSpeechService.completeCurrent();
    await tester.pumpAndSettle();

    expect(harness.textToSpeechService.spoken, [
      'Primera oración.',
      'Segunda oración.',
    ]);
    expect(find.text(es.narrationProgress(2, 3)), findsOneWidget);
  });

  testWidgets(
    'al terminar el último fragmento, se cierra y vuelve a "escuchar"',
    (tester) async {
      await pumpPlayer(tester, text: 'Única oración.');
      await tester.tap(find.text(es.narrationListenAction));
      await tester.pumpAndSettle();

      harness.textToSpeechService.completeCurrent();
      await tester.pumpAndSettle();

      expect(find.text(es.narrationListenAction), findsOneWidget);
    },
  );

  testWidgets('pausar corta la lectura sin avanzar de fragmento', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await tester.tap(find.text(es.narrationListenAction));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();

    expect(harness.textToSpeechService.stopCount, 1);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text(es.narrationProgress(1, 3)), findsOneWidget);
  });

  testWidgets('retomar desde pausa vuelve a leer el mismo fragmento', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await tester.tap(find.text(es.narrationListenAction));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(harness.textToSpeechService.spoken, [
      'Primera oración.',
      'Primera oración.',
    ]);
  });

  testWidgets('adelantar salta al fragmento siguiente', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.text(es.narrationListenAction));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pumpAndSettle();

    expect(harness.textToSpeechService.spoken, [
      'Primera oración.',
      'Segunda oración.',
    ]);
    expect(find.text(es.narrationProgress(2, 3)), findsOneWidget);
  });

  testWidgets('retroceder vuelve al fragmento anterior', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.text(es.narrationListenAction));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.pumpAndSettle();

    expect(harness.textToSpeechService.spoken, [
      'Primera oración.',
      'Segunda oración.',
      'Primera oración.',
    ]);
    expect(find.text(es.narrationProgress(1, 3)), findsOneWidget);
  });

  testWidgets('reiniciar vuelve al primer fragmento', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.text(es.narrationListenAction));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.replay));
    await tester.pumpAndSettle();

    expect(find.text(es.narrationProgress(1, 3)), findsOneWidget);
  });

  testWidgets('cerrar corta la lectura y colapsa de nuevo', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.text(es.narrationListenAction));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(harness.textToSpeechService.stopCount, greaterThanOrEqualTo(1));
    expect(find.text(es.narrationListenAction), findsOneWidget);
  });

  testWidgets('sin voces adicionales, el panel de ajustes ofrece igual la del '
      'sistema', (tester) async {
    await pumpPlayer(tester);
    await tester.tap(find.text(es.narrationListenAction));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text(es.narrationSystemDefaultVoice), findsOneWidget);
    expect(find.text(es.narrationNoVoicesAvailable), findsOneWidget);
  });
}
