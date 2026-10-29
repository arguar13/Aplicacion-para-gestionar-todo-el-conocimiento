import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_dock.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/fake_text_to_speech_service.dart';

/// Lo que el lector en voz alta suma para los visores de extraer de Repasar
/// (F43, paso 7): ir a una oración, a la anterior y a la siguiente, saltar a
/// un punto de la barra de avance, y su propio reproductor en la pantalla,
/// que el lector flotante no repite.
void main() {
  // "Uno dos tres." son 13 caracteres, "Cuatro cinco." 13 y "Seis." 5: 31
  // de lo que se dice en total.
  const text = 'Uno dos tres.\nCuatro cinco.\nSeis.';
  final document = ReadableDocument(
    id: 'extract:1',
    title: 'Extracción',
    segments: buildReadableSegments(text, sourceKey: 'procesado:1'),
  );

  late FakeTextToSpeechService tts;
  late ProviderContainer container;

  Future<void> start() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tts = FakeTextToSpeechService();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(tts),
        narrationClockProvider.overrideWithValue(() => Duration.zero),
      ],
    );
    addTearDown(container.dispose);
  }

  ReadAloudController controller() =>
      container.read(readAloudControllerProvider.notifier);
  ReadAloudState state() => container.read(readAloudControllerProvider);

  group('ir a una oración', () {
    setUp(start);

    test('la siguiente y la anterior leen desde su comienzo', () async {
      await controller().open(document);
      await controller().nextSegment();
      expect(state().segmentIndex, 1);
      expect(state().charInSegment, 0);
      expect(tts.spoken.last, 'Cuatro cinco.');

      await controller().nextSegment();
      expect(tts.spoken.last, 'Seis.');

      await controller().previousSegment();
      expect(state().segmentIndex, 1);
      expect(tts.spoken.last, 'Cuatro cinco.');
    });

    test('antes de la primera, el comienzo de la primera; después de la '
        'última, terminado', () async {
      await controller().open(document);
      tts.emitProgress(4);
      await pumpEventQueue();
      expect(state().charInSegment, 4);

      await controller().previousSegment();
      expect(state().segmentIndex, 0);
      expect(state().charInSegment, 0);
      expect(tts.spoken.last, 'Uno dos tres.');

      await controller().seekToSegment(2);
      await controller().nextSegment();
      expect(state().playing, isFalse);
      expect(state().segmentIndex, 2);
      expect(state().progress, 1);
    });

    test('en pausa, se mueve y sigue en pausa, sin hablar', () async {
      await controller().open(document);
      await controller().pause();
      final spoken = tts.spoken.length;

      await controller().nextSegment();

      expect(state().segmentIndex, 1);
      expect(state().playing, isFalse);
      expect(tts.spoken, hasLength(spoken));
      await controller().play();
      expect(tts.spoken.last, 'Cuatro cinco.');
    });

    test('sin nada abierto no hace nada', () async {
      await controller().nextSegment();
      await controller().seekToFraction(0.5);
      expect(state().document, isNull);
      expect(tts.spoken, isEmpty);
    });
  });

  group('la barra de avance', () {
    setUp(start);

    test('soltarla lleva la lectura al comienzo de la palabra de ese punto, '
        'cruzando oraciones', () async {
      await controller().open(document);

      // 15 de 31: dentro de "Cuatro", la segunda oración.
      await controller().seekToFraction(15 / 31);

      expect(state().segmentIndex, 1);
      expect(state().charInSegment, 0);
      expect(tts.spoken.last, 'Cuatro cinco.');

      // 22 de 31: dentro de "cinco".
      await controller().seekToFraction(22 / 31);
      expect(state().segmentIndex, 1);
      expect(state().charInSegment, 7);
      expect(tts.spoken.last, 'cinco.');
    });

    test('al principio y al final', () async {
      await controller().open(document);
      await controller().nextSegment();

      await controller().seekToFraction(0);
      expect(state().segmentIndex, 0);
      expect(state().charInSegment, 0);

      await controller().seekToFraction(1);
      expect(state().playing, isFalse);
      expect(state().progress, 1);
    });
  });

  group('un reproductor propio en la pantalla', () {
    final player = find.byKey(const Key('read-aloud-player'));
    final button = find.byKey(const Key('read-aloud-button'));

    Future<void> pump(WidgetTester tester, {required bool docked}) async {
      await start();
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: docked
                  ? ReadAloudDock(
                      documentId: document.id,
                      child: const Text('Visor'),
                    )
                  : const Text('Otra'),
            ),
          ),
          GoRoute(
            path: '/arriba',
            builder: (_, _) => const Scaffold(body: Text('Arriba')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                ReadAloudOverlay(router: router, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await controller().open(document);
      await tester.pumpAndSettle();
    }

    testWidgets('mientras se lee lo de esa pantalla, el lector flotante no '
        'aparece: ni el reproductor ni el botón', (tester) async {
      await pump(tester, docked: true);

      expect(container.read(readAloudDockProvider), {document.id});
      expect(player, findsNothing);
      controller().minimize();
      await tester.pumpAndSettle();
      expect(button, findsNothing);
    });

    testWidgets('en otra pantalla, el de siempre', (tester) async {
      await pump(tester, docked: false);

      expect(container.read(readAloudDockProvider), isEmpty);
      expect(player, findsOneWidget);
    });

    testWidgets('si otra pantalla la tapa, vuelve el de siempre con la '
        'lectura donde iba', (tester) async {
      await pump(tester, docked: true);
      expect(player, findsNothing);

      final router =
          tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
              as GoRouter;
      unawaited(router.push<void>('/arriba'));
      await tester.pumpAndSettle();

      expect(container.read(readAloudDockProvider), isEmpty);
      expect(player, findsOneWidget);
      expect(state().document?.id, document.id);
    });
  });
}
