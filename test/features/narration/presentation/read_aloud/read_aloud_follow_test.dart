import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_follow.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/read_aloud_test_support.dart';

/// Seguir lo que se lee en voz alta dentro de un visor: qué parte de lo que
/// suena cae en un tramo, la franja cómoda de la vista, cuándo se sigue y
/// cuándo se ofrece «Volver a la lectura».
void main() {
  final es = AppLocalizationsEs();

  const text = ReadableSegment(
    sourceKey: 'r1',
    start: 100,
    end: 140,
    spoken: 'Una línea que suena.',
  );
  const document = ReadableDocument(
    id: 'libro',
    title: 'Un libro',
    segments: [
      text,
      ReadableSegment(sourceKey: 'otro', start: 0, end: 10, spoken: 'Otro.'),
    ],
  );

  group('readAloudSpanProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
        ],
      );
      addTearDown(container.dispose);
    });

    (int, int)? span(int from, int to, {String key = 'r1'}) => container.read(
      readAloudSpanProvider((sourceKey: key, from: from, to: to)),
    );

    void readAt(int segment) =>
        (container.read(readAloudControllerProvider.notifier)
                as FakeReadAloudController)
            .readAt(document, segment);

    test('lo que suena dentro del tramo, contado desde su comienzo', () {
      readAt(0);

      expect(span(0, 1000), (100, 140));
      expect(span(90, 200), (10, 50));
    });

    test('cortado en los bordes del tramo', () {
      readAt(0);

      expect(span(120, 200), (0, 20));
      expect(span(0, 120), (100, 120));
    });

    test('fuera del tramo, o de otro texto, nada', () {
      readAt(0);

      expect(span(0, 100), isNull);
      expect(span(140, 200), isNull);
      expect(span(0, 1000, key: 'otro'), isNull);
    });

    test('sin nada que suene, nada', () {
      expect(span(0, 1000), isNull);
    });
  });

  group('ReadAloudBand', () {
    const view = Rect.fromLTWH(0, 1000, 400, 800);

    test('la línea se lee cómoda entre arriba de todo y un poco más abajo '
        'de la mitad', () {
      expect(
        ReadAloudBand.contains(view, const Rect.fromLTWH(10, 1100, 300, 20)),
        isTrue,
      );
      // Arriba del 5 %.
      expect(
        ReadAloudBand.contains(view, const Rect.fromLTWH(10, 1030, 300, 20)),
        isFalse,
      );
      // Pasando el 70 %: la tapa el reproductor.
      expect(
        ReadAloudBand.contains(view, const Rect.fromLTWH(10, 1550, 300, 20)),
        isFalse,
      );
      expect(
        ReadAloudBand.contains(view, const Rect.fromLTWH(10, 1540, 300, 20)),
        isTrue,
      );
      // Fuera de lado.
      expect(
        ReadAloudBand.contains(view, const Rect.fromLTWH(390, 1100, 30, 20)),
        isFalse,
      );
      expect(
        ReadAloudBand.contains(view, const Rect.fromLTWH(-5, 1100, 30, 20)),
        isFalse,
      );
    });

    test('al salir, la línea va al quinto de arriba; de lado solo se mueve '
        'si no entra', () {
      const line = Rect.fromLTWH(10, 3000, 300, 20);
      final center = ReadAloudBand.centerFor(view, line);

      expect(center.dx, view.center.dx);
      expect(center.dy - view.height / 2, 3000 - view.height * 0.2);

      const wide = Rect.fromLTWH(350, 3000, 300, 20);
      expect(ReadAloudBand.centerFor(view, wide).dx, wide.center.dx);
    });
  });

  group('ReadAloudFollow', () {
    test('sigue de entrada; soltar y retomar avisan una vez cada uno', () {
      final follow = ReadAloudFollow();
      addTearDown(follow.dispose);
      var notified = 0;
      follow.addListener(() => notified++);

      expect(follow.following, isTrue);
      follow.resume();
      expect(notified, 0);

      follow
        ..release()
        ..release();
      expect(follow.following, isFalse);
      expect(notified, 1);

      follow
        ..resume()
        ..resume();
      expect(follow.following, isTrue);
      expect(notified, 2);
    });

    test('siguiendo, se mueve solo si la línea salió de la franja', () {
      final follow = ReadAloudFollow();
      addTearDown(follow.dispose);

      expect(follow.shouldMoveTo(comfortable: true), isFalse);
      expect(follow.shouldMoveTo(comfortable: false), isTrue);
      expect(follow.following, isTrue);
    });

    test('sin seguir no se mueve nunca; si la línea llegó sola a la franja, '
        'vuelve a seguir', () {
      final follow = ReadAloudFollow()..release();
      addTearDown(follow.dispose);

      expect(follow.shouldMoveTo(comfortable: false), isFalse);
      expect(follow.following, isFalse);

      expect(follow.shouldMoveTo(comfortable: true), isFalse);
      expect(follow.following, isTrue);
    });
  });

  group('«Volver a la lectura»', () {
    late ProviderContainer container;
    late ReadAloudFollow follow;
    late int pressed;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
        ],
      );
      addTearDown(container.dispose);
      follow = ReadAloudFollow();
      addTearDown(follow.dispose);
      pressed = 0;
    });

    FakeReadAloudController reader() =>
        container.read(readAloudControllerProvider.notifier)
            as FakeReadAloudController;

    Future<void> pump(WidgetTester tester, {bool still = false}) =>
        tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('es'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: still),
                child: Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) {
                      follow.resumeOnNewReadings(ref);
                      return Center(
                        child: ReadAloudBackToReading(
                          sourceKey: 'r1',
                          follow: follow,
                          onPressed: () => pressed++,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );

    double opacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.text(es.readAloudBackToReading),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    testWidgets('aparece solo si suena algo de su texto y la persona se '
        'alejó', (tester) async {
      await pump(tester);
      expect(opacity(tester), 0);

      follow.release();
      await tester.pumpAndSettle();
      expect(opacity(tester), 0, reason: 'no suena nada');

      reader().readAt(document, 1);
      await tester.pumpAndSettle();
      expect(opacity(tester), 0, reason: 'suena otro texto');

      reader().readAt(
        const ReadableDocument(
          id: 'libro',
          title: 'Un libro',
          segments: [text],
        ),
        0,
      );
      await tester.pumpAndSettle();
      expect(opacity(tester), 0, reason: 'otra lectura: vuelve a seguir');

      follow.release();
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);

      follow.resume();
      await tester.pumpAndSettle();
      expect(opacity(tester), 0);
    });

    testWidgets('tocarla avisa; escondida, no recibe toques', (tester) async {
      reader().readAt(document, 0);
      await pump(tester);

      // Escondida, un toque en su lugar no la alcanza: sigue a lo de abajo.
      // Su lugar es el de la pastilla visible —un poco más abajo de donde se
      // esconde, deslizada hacia arriba—, donde las dos se superponen.
      Offset place() {
        final rect = tester.getRect(find.byType(AnimatedSlide));
        return rect.topCenter + Offset(0, rect.height * 0.2);
      }

      await tester.tapAt(place());
      expect(pressed, 0);

      follow.release();
      await tester.pumpAndSettle();
      await tester.tapAt(place());
      expect(pressed, 1);
      expect(find.byTooltip(es.readAloudBackToReadingHint), findsOneWidget);
    });

    testWidgets('con las animaciones apagadas, aparece de una', (tester) async {
      reader().readAt(document, 0);
      await pump(tester, still: true);

      follow.release();
      await tester.pump();

      expect(opacity(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
