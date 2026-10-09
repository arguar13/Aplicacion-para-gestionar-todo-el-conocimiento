import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Las formas nuevas de tarjeta tal como se ven en la sesión (F31, ola 2):
/// huecos para completar y «escribí la respuesta».
void main() {
  final es = AppLocalizationsEs();
  final start = DateTime(2026, 9, 11, 10);
  late LibraryHarness harness;
  late String itemId;

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [clockProvider.overrideWithValue(() => start)],
    );
    await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
    itemId =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!
            .single
            .id;
  });

  Future<void> addCloze(String text, int index, {String back = ''}) async {
    await harness.container
        .read(flashcardRepositoryProvider)
        .create(
          itemId: itemId,
          front: text,
          back: back,
          kind: FlashcardKind.cloze,
          clozeIndex: index,
        );
  }

  Future<void> addTyped(String front, String back) async {
    await harness.container
        .read(flashcardRepositoryProvider)
        .create(
          itemId: itemId,
          front: front,
          back: back,
          kind: FlashcardKind.typedAnswer,
        );
  }

  Future<void> pumpSession(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const ReviewScreen()));
    await tester.pumpAndSettle();
  }

  Future<Flashcard> stored(String front) async =>
      (await harness.container.read(flashcardRepositoryProvider).getAll())
          .getRight()
          .toNullable()!
          .firstWhere((c) => c.front == front);

  /// Los trozos del texto con huecos: (texto, negrita).
  List<(String, bool)> spansOf(WidgetTester tester, String key) {
    final text = tester.widget<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    );
    final spans = <(String, bool)>[];
    text.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        spans.add((span.text!, span.style?.fontWeight == FontWeight.w700));
      }
      return true;
    });
    return spans;
  }

  group('huecos para completar', () {
    const text = 'El {{c1::Imperio romano}} cayó en {{c2::476}}';

    testWidgets('el hueco que se pregunta es una marca; los demás se ven', (
      tester,
    ) async {
      await addCloze(text, 2);
      await pumpSession(tester);

      expect(spansOf(tester, 'review-cloze-question'), [
        ('El Imperio romano cayó en ', false),
        ('[...]', true),
      ]);
      expect(find.text(es.reviewSessionClozeBadge(2, 2)), findsOneWidget);
      // No hay respuesta a la vista, ni el texto crudo con sus llaves.
      expect(find.textContaining('{{'), findsNothing);
      expect(find.byKey(const Key('review-show-answer')), findsOneWidget);
    });

    testWidgets('al dar vuelta, la respuesta queda resaltada en su lugar', (
      tester,
    ) async {
      await addCloze(text, 1);
      await pumpSession(tester);

      await tester.tap(find.byKey(const Key('review-show-answer')));
      await tester.pumpAndSettle();

      expect(spansOf(tester, 'review-cloze-answer'), [
        ('El ', false),
        ('Imperio romano', true),
        (' cayó en 476', false),
      ]);
      expect(find.byKey(const Key('grade-good')), findsOneWidget);
    });

    testWidgets('con pista, la marca la lleva', (tester) async {
      await addCloze('La capital es {{c1::Roma::una ciudad}}.', 1);
      await pumpSession(tester);

      expect(spansOf(tester, 'review-cloze-question'), [
        ('La capital es ', false),
        ('[una ciudad]', true),
        ('.', false),
      ]);
    });

    testWidgets('un solo hueco no lleva el contador de huecos', (tester) async {
      await addCloze('La capital es {{c1::Roma}}.', 1);
      await pumpSession(tester);

      expect(find.textContaining('Hueco'), findsNothing);
    });

    testWidgets('el complemento se ve junto a la respuesta', (tester) async {
      await addCloze(text, 2, back: 'Fin del Imperio de Occidente.');
      await pumpSession(tester);
      expect(find.text('Fin del Imperio de Occidente.'), findsNothing);

      await tester.tap(find.byKey(const Key('review-show-answer')));
      await tester.pumpAndSettle();

      expect(find.text('Fin del Imperio de Occidente.'), findsOneWidget);
    });

    testWidgets('tocar la tarjeta la da vuelta, y se califica como cualquier '
        'otra', (tester) async {
      await addCloze(text, 2);
      await pumpSession(tester);

      await tester.tap(find.byKey(const Key('review-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('grade-easy')));
      await tester.pumpAndSettle();

      final saved = await stored(text);
      expect(saved.dueAt.difference(start), const Duration(days: 4));
    });

    testWidgets('si el texto ya no tiene el hueco, se muestra tal cual en '
        'vez de romperse', (tester) async {
      // Un texto editado desde otro lado: la tarjeta pide el hueco 3.
      await addCloze(text, 3);
      await pumpSession(tester);

      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text(text), findsOneWidget);
    });
  });

  group('«escribí la respuesta»', () {
    Future<void> typeAndCheck(WidgetTester tester, String typed) async {
      await tester.enterText(
        find.byKey(const Key('review-typed-field')),
        typed,
      );
      await tester.tap(find.byKey(const Key('review-typed-check')));
      await tester.pumpAndSettle();
    }

    String plain(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(Key(key))).textSpan!.toPlainText();

    testWidgets('pide escribir: hay un campo y «Comprobar», y la tarjeta no '
        'se da vuelta sola', (tester) async {
      await addTyped('¿Cuál es el orgánulo de la energía?', 'mitocondria');
      await pumpSession(tester);

      expect(find.byKey(const Key('review-typed-field')), findsOneWidget);
      expect(find.byKey(const Key('review-typed-check')), findsOneWidget);
      expect(find.byKey(const Key('review-show-answer')), findsNothing);

      await tester.tap(find.byKey(const Key('review-card')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('grade-good')), findsNothing);
    });

    testWidgets('lo correcto dice «Coincide» (aunque cambien mayúsculas y '
        'acentos) y deja calificar', (tester) async {
      await addTyped('¿Orgánulo de la energía?', 'Mitocondria');
      await pumpSession(tester);

      await typeAndCheck(tester, 'mitocondria');

      expect(
        tester.widget<Text>(find.byKey(const Key('review-typed-verdict'))).data,
        es.reviewSessionTypedMatch,
      );
      expect(find.byKey(const Key('grade-good')), findsOneWidget);
      expect(find.byKey(const Key('review-typed-field')), findsNothing);
    });

    testWidgets(
      'una respuesta alternativa (en `back`, una por renglón) también '
      'coincide',
      (tester) async {
        await addTyped(
          '¿Cómo se llamaba la capital del Imperio?',
          'Roma\nRoma antigua',
        );
        await pumpSession(tester);

        await typeAndCheck(tester, 'roma antigua');

        expect(
          tester
              .widget<Text>(find.byKey(const Key('review-typed-verdict')))
              .data,
          es.reviewSessionTypedMatch,
        );
      },
    );

    testWidgets('la respuesta principal sigue coincidiendo cuando hay '
        'alternativas, y se muestra sin ellas', (tester) async {
      await addTyped(
        '¿Cómo se llamaba la capital del Imperio?',
        'Roma\nRoma antigua',
      );
      await pumpSession(tester);

      await typeAndCheck(tester, 'Roma');

      expect(
        tester.widget<Text>(find.byKey(const Key('review-typed-verdict'))).data,
        es.reviewSessionTypedMatch,
      );
      expect(
        plain(tester, 'review-typed-expected'),
        isNot(contains('antigua')),
      );
    });

    testWidgets('un descuido de tipeo es «casi»: muestra la diferencia, y '
        'califica la persona', (tester) async {
      await addTyped('¿Orgánulo de la energía?', 'mitocondria');
      await pumpSession(tester);

      await typeAndCheck(tester, 'mitocondira');

      expect(
        tester.widget<Text>(find.byKey(const Key('review-typed-verdict'))).data,
        es.reviewSessionTypedClose,
      );
      // Lo que se escribió y lo correcto, cada uno con su marca.
      expect(plain(tester, 'review-typed-yours'), contains('mitocond'));
      expect(plain(tester, 'review-typed-expected'), contains('mitocond'));
      final typedSpans =
          (tester
                      .widget<Text>(find.byKey(const Key('review-typed-yours')))
                      .textSpan!
                  as TextSpan)
              .children!
              .cast<TextSpan>();
      final expectedSpans =
          (tester
                      .widget<Text>(
                        find.byKey(const Key('review-typed-expected')),
                      )
                      .textSpan!
                  as TextSpan)
              .children!
              .cast<TextSpan>();
      // Lo que sobra se tacha; lo que falta se subraya.
      expect(
        typedSpans.any(
          (s) => s.style?.decoration == TextDecoration.lineThrough,
        ),
        isTrue,
      );
      expect(
        expectedSpans.any(
          (s) => s.style?.decoration == TextDecoration.underline,
        ),
        isTrue,
      );
      // Y no califica solo: los cuatro botones están.
      for (final grade in ReviewGrade.values) {
        expect(find.byKey(Key('grade-${grade.name}')), findsOneWidget);
      }
      expect((await stored('¿Orgánulo de la energía?')).lastReviewedAt, isNull);
    });

    testWidgets('otra cosa es «No coincide», con la respuesta a la vista', (
      tester,
    ) async {
      await addTyped('¿Orgánulo de la energía?', 'mitocondria');
      await pumpSession(tester);

      await typeAndCheck(tester, 'ribosoma');

      expect(
        tester.widget<Text>(find.byKey(const Key('review-typed-verdict'))).data,
        es.reviewSessionTypedMismatch,
      );
      expect(plain(tester, 'review-typed-expected'), 'mitocondria');
    });

    testWidgets('comprobar sin escribir lo dice y muestra la respuesta', (
      tester,
    ) async {
      await addTyped('¿Orgánulo de la energía?', 'mitocondria');
      await pumpSession(tester);

      await tester.tap(find.byKey(const Key('review-typed-check')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('review-typed-verdict'))).data,
        es.reviewSessionTypedBlank,
      );
      expect(find.byKey(const Key('review-typed-yours')), findsNothing);
      expect(plain(tester, 'review-typed-expected'), 'mitocondria');
    });

    testWidgets('«Enter» en el campo también comprueba', (tester) async {
      await addTyped('¿Orgánulo de la energía?', 'mitocondria');
      await pumpSession(tester);

      await tester.enterText(
        find.byKey(const Key('review-typed-field')),
        'mitocondria',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review-typed-verdict')), findsOneWidget);
    });

    testWidgets('después de comprobar se califica con el teclado', (
      tester,
    ) async {
      await addTyped('¿Orgánulo de la energía?', 'mitocondria');
      await pumpSession(tester);
      await typeAndCheck(tester, 'mitocondria');

      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();

      final saved = await stored('¿Orgánulo de la energía?');
      expect(saved.dueAt.difference(start), const Duration(days: 4));
    });

    testWidgets('mientras se escribe, las teclas de la sesión son letras: una '
        'Z no deshace', (tester) async {
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: itemId, front: '¿Uno?', back: 'R');
      await addTyped('¿Un animal con rayas?', 'zebra');
      await pumpSession(tester);
      // Se contesta la primera, y la segunda es de escribir.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-typed-field')), findsOneWidget);

      await tester.showKeyboard(find.byKey(const Key('review-typed-field')));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();

      // La primera sigue contestada: la Z no la deshizo.
      expect((await stored('¿Uno?')).lastReviewedAt, isNotNull);
      expect(find.byKey(const Key('review-typed-field')), findsOneWidget);
    });
  });
}
