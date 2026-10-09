import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_form.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_form_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// El formulario de una tarjeta (F31, decisión 73): elegir la forma, llenarla,
/// ver cómo queda, y que al editar vuelva a mostrar la forma de la tarjeta.
void main() {
  final es = AppLocalizationsEs();
  final at = DateTime(2026, 10, 8);
  CardFormDialogResult? result;
  var closed = false;

  Flashcard card({
    required FlashcardKind kind,
    String front = 'P',
    String back = 'R',
    int? clozeIndex,
  }) => Flashcard(
    id: 'c',
    itemId: 'i',
    front: front,
    back: back,
    dueAt: at,
    createdAt: at,
    kind: kind,
    clozeIndex: clozeIndex,
  );

  Future<void> open(
    WidgetTester tester, {
    bool aiAvailable = false,
    Flashcard? editing,
    String? initialBack,
    List<int> siblingNumbers = const [],
  }) async {
    result = null;
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('es'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showCardFormDialog(
                  context,
                  aiAvailable: aiAvailable,
                  card: editing,
                  initialBack: initialBack,
                  siblingNumbers: siblingNumbers,
                );
                closed = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Finder field(String hint) => find.widgetWithText(TextField, hint);

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pumpAndSettle();
  }

  group('crear', () {
    testWidgets('arranca en pregunta y respuesta, y devuelve esa forma', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(field(es.flashcardsFrontHint), '¿Capital?');
      await tester.enterText(field(es.flashcardsBackHint), 'Roma');
      await save(tester);

      final form = (result! as CardFormSubmitted).form as QaCardForm;
      expect(form.front, '¿Capital?');
      expect(form.back, 'Roma');
    });

    testWidgets('el fragmento seleccionado llega como respuesta inicial', (
      tester,
    ) async {
      await open(tester, initialBack: 'Un fragmento');
      expect(find.widgetWithText(TextField, 'Un fragmento'), findsOneWidget);
    });

    testWidgets('ofrece las cinco formas, y la IA solo si está disponible', (
      tester,
    ) async {
      await open(tester);
      for (final label in [
        es.cardFormKindQa,
        es.cardFormKindBoth,
        es.cardFormKindCloze,
        es.cardFormKindTyped,
        es.cardFormKindChoice,
      ]) {
        expect(
          find.widgetWithText(ChoiceChip, label),
          findsOneWidget,
          reason: label,
        );
      }
      expect(
        find.widgetWithText(ChoiceChip, es.cardFormKindClozeAi),
        findsNothing,
      );
    });

    testWidgets('con la IA disponible ofrece los huecos con IA, que piden '
        'generar en vez de guardar', (tester) async {
      await open(tester, aiAvailable: true);

      await pick(tester, es.cardFormKindClozeAi);
      expect(find.text(es.cardFormAiHelp), findsOneWidget);
      await tester.tap(find.text(es.cardFormAiGenerate));
      await tester.pumpAndSettle();

      expect(result, isA<CardFormAiRequested>());
    });

    testWidgets(
      'dos direcciones: muestra las dos tarjetas y devuelve la forma',
      (tester) async {
        await open(tester);
        await pick(tester, es.cardFormKindBoth);

        // Sin nada escrito no se puede guardar.
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, es.detailSave),
              )
              .onPressed,
          isNull,
        );

        await tester.enterText(field(es.flashcardsFrontHint), 'Francia');
        await tester.enterText(field(es.flashcardsBackHint), 'París');
        await tester.pumpAndSettle();

        expect(find.text(es.cardFormBothForward), findsOneWidget);
        expect(find.text(es.cardFormBothBackward), findsOneWidget);
        // La vuelta tiene la respuesta de pregunta.
        expect(find.text('París'), findsWidgets);

        await save(tester);
        final form =
            (result! as CardFormSubmitted).form as BothDirectionsCardForm;
        expect(form.front, 'Francia');
        expect(form.back, 'París');
        expect(form.cardCount, 2);
      },
    );

    testWidgets('lo escrito sobrevive a cambiar de forma', (tester) async {
      await open(tester);
      await tester.enterText(field(es.flashcardsFrontHint), 'Francia');
      await pick(tester, es.cardFormKindTyped);
      expect(find.widgetWithText(TextField, 'Francia'), findsOneWidget);
    });

    testWidgets(
      'escribí la respuesta: respuesta y alternativas, una por renglón',
      (tester) async {
        await open(tester);
        await pick(tester, es.cardFormKindTyped);

        await tester.enterText(
          field(es.flashcardsFrontHint),
          '¿Capital de Italia?',
        );
        await tester.enterText(field(es.cardFormTypedAnswerHint), 'Roma');
        await tester.enterText(
          find.byKey(const ValueKey('cardFormAlternatives')),
          'La Urbe\n\n roma \n',
        );
        await save(tester);

        final form = (result! as CardFormSubmitted).form as TypedCardForm;
        expect(form.answer, 'Roma');
        expect(form.alternatives, ['La Urbe', 'roma']);
      },
    );

    testWidgets('opción múltiple pide al menos un distractor', (tester) async {
      await open(tester);
      await pick(tester, es.cardFormKindChoice);

      await tester.enterText(field(es.cardFormChoiceQuestionHint), '¿Capital?');
      await tester.enterText(field(es.cardFormChoiceCorrectHint), 'Roma');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, es.detailSave))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        field(es.cardFormChoiceDistractorHint(2)),
        'Milán',
      );
      await tester.pumpAndSettle();
      await save(tester);

      final form =
          (result! as CardFormSubmitted).form as MultipleChoiceCardForm;
      expect(form.question, '¿Capital?');
      expect(form.correct, 'Roma');
      expect(form.distractors, ['Milán']);
    });

    testWidgets('cancelar no devuelve nada', (tester) async {
      await open(tester);
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });
  });

  group('huecos', () {
    Finder clozeField() => find.byKey(const ValueKey('cardFormClozeText'));

    TextEditingController controller(WidgetTester tester) =>
        tester.widget<TextField>(clozeField()).controller!;

    Future<void> startCloze(WidgetTester tester, String text) async {
      await open(tester);
      await pick(tester, es.cardFormKindCloze);
      await tester.enterText(clozeField(), text);
      await tester.pumpAndSettle();
    }

    // El formulario se desplaza dentro del diálogo: el botón puede quedar
    // fuera de la vista hasta que se lo trae.
    Future<void> cover(WidgetTester tester) async {
      await tester.ensureVisible(find.text(es.cardFormClozeCover));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.cardFormClozeCover));
      await tester.pumpAndSettle();
    }

    Future<void> select(WidgetTester tester, int start, int end) async {
      controller(tester).selection = TextSelection(
        baseOffset: start,
        extentOffset: end,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Tapar selección envuelve el texto elegido en el siguiente '
        'hueco libre', (tester) async {
      await startCloze(tester, 'Roma cayó en 476 y Bizancio en 1453');

      await select(tester, 0, 4);
      await cover(tester);
      await tester.pumpAndSettle();
      expect(
        controller(tester).text,
        '{{c1::Roma}} cayó en 476 y Bizancio en 1453',
      );
      // El cursor queda justo después del hueco recién hecho.
      expect(
        controller(tester).selection,
        const TextSelection.collapsed(offset: 12),
      );

      // El segundo toma el número que sigue.
      final text = controller(tester).text;
      final start = text.indexOf('476');
      await select(tester, start, start + 3);
      await cover(tester);
      await tester.pumpAndSettle();
      expect(
        controller(tester).text,
        '{{c1::Roma}} cayó en {{c2::476}} y Bizancio en 1453',
      );
    });

    testWidgets('sin selección el botón está apagado', (tester) async {
      await startCloze(tester, 'Roma cayó en 476');
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(es.cardFormClozeCover),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('la vista previa muestra una tarjeta por hueco con el hueco '
        'tapado', (tester) async {
      await startCloze(tester, 'El {{c1::Imperio}} cayó en {{c2::476}}');

      expect(find.text(es.cardFormClozeCount(2)), findsOneWidget);
      expect(find.text(es.cardFormClozeCardTitle(1)), findsOneWidget);
      expect(find.text(es.cardFormClozeCardTitle(2)), findsOneWidget);
      // En la tarjeta 1 el hueco 1 está tapado y el 2 revelado.
      expect(
        find.textContaining('[...]', findRichText: true),
        findsNWidgets(2),
      );
    });

    testWidgets('un hueco roto muestra su error y no deja guardar', (
      tester,
    ) async {
      await startCloze(tester, 'Un {{c1::hueco sin cerrar');

      expect(
        find.text(clozeProblemMessage(ClozeProblem.unclosed)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, es.detailSave))
            .onPressed,
        isNull,
      );
    });

    testWidgets('un texto sin huecos avisa que no tiene ninguno', (
      tester,
    ) async {
      await startCloze(tester, 'Un texto común');
      expect(
        find.text(clozeProblemMessage(ClozeProblem.noDeletions)),
        findsOneWidget,
      );
    });

    testWidgets('devuelve el texto entero y el complemento', (tester) async {
      await startCloze(tester, 'El {{c1::Imperio}} cayó en {{c2::476}}');
      await tester.enterText(field(es.cardFormClozeExtraHint), 'Occidente');
      await save(tester);

      final form = (result! as CardFormSubmitted).form as ClozeCardForm;
      expect(form.text, 'El {{c1::Imperio}} cayó en {{c2::476}}');
      expect(form.extra, 'Occidente');
      expect(form.numbers, [1, 2]);
    });
  });

  group('editar vuelve a mostrar la forma', () {
    testWidgets(
      'una de huecos se edita como huecos, sin el selector de forma',
      (tester) async {
        await open(
          tester,
          editing: card(
            kind: FlashcardKind.cloze,
            front: 'El {{c1::Imperio}} cayó en {{c2::476}}',
            back: 'Occidente',
            clozeIndex: 1,
          ),
          siblingNumbers: [1, 2],
        );

        expect(
          find.widgetWithText(ChoiceChip, es.cardFormKindQa),
          findsNothing,
        );
        expect(
          find.widgetWithText(
            TextField,
            'El {{c1::Imperio}} cayó en {{c2::476}}',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextField, 'Occidente'), findsOneWidget);
        expect(find.text(es.cardFormClozeCount(2)), findsOneWidget);
      },
    );

    testWidgets('sacar un hueco avisa cuántas tarjetas se borran', (
      tester,
    ) async {
      await open(
        tester,
        editing: card(
          kind: FlashcardKind.cloze,
          front: 'El {{c1::Imperio}} cayó en {{c2::476}}',
          back: '',
          clozeIndex: 1,
        ),
        siblingNumbers: [1, 2],
      );

      await tester.enterText(
        find.byKey(const ValueKey('cardFormClozeText')),
        'El {{c1::Imperio}} cayó en 476',
      );
      await tester.pumpAndSettle();

      expect(find.text(es.cardFormClozeRemovesCards(1)), findsOneWidget);
    });

    testWidgets('una de escribí la respuesta separa la respuesta de las '
        'alternativas', (tester) async {
      await open(
        tester,
        editing: card(
          kind: FlashcardKind.typedAnswer,
          front: '¿Capital de Italia?',
          back: 'Roma\nLa Urbe',
        ),
      );

      expect(
        find.widgetWithText(TextField, '¿Capital de Italia?'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Roma'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'La Urbe'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('cardFormAlternatives')),
        'La Urbe\nCaput Mundi',
      );
      await save(tester);

      final form = (result! as CardFormSubmitted).form as TypedCardForm;
      expect(form.back, 'Roma\nLa Urbe\nCaput Mundi');
    });

    testWidgets('una común se edita como pregunta y respuesta', (tester) async {
      await open(tester, editing: card(kind: FlashcardKind.freeRecall));
      expect(find.widgetWithText(TextField, 'P'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'R'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'P'), 'Otra');
      await save(tester);
      final form = (result! as CardFormSubmitted).form as QaCardForm;
      expect(form.front, 'Otra');
      expect(form.back, 'R');
    });
  });
}
