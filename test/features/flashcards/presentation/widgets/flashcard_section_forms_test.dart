import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/sibling_card_draft.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze_generator.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_section.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// Las formas nuevas de tarjeta en la sección de tarjetas de un elemento (F31,
/// decisión 73): crearlas con el selector de forma, verlas en la lista, y
/// editarlas sin degradarlas a pregunta y respuesta.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late KnowledgeItem item;
  late _ClozeModel clozeModel;

  setUp(() async {
    clozeModel = _ClozeModel();
    harness = await LibraryHarness.create(
      extraOverrides: [clozeGeneratorProvider.overrideWithValue(clozeModel)],
    );
    await insertItemRows(harness.database, id: 'a', title: 'Roma');
    item =
        (await harness.container.read(libraryRepositoryProvider).findById('a'))
            .getOrElse((f) => fail('$f'))!;
  });

  AppDatabase db() => harness.database;

  Future<void> pumpSection(WidgetTester tester, [KnowledgeItem? shown]) async {
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: SingleChildScrollView(
            child: FlashcardSection(item: shown ?? item),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester, String kindLabel) async {
    await pumpSection(tester);
    await tester.tap(find.byTooltip(es.flashcardsAddAction));
    await tester.pumpAndSettle();
    if (kindLabel != es.cardFormKindQa) {
      await tester.tap(find.widgetWithText(ChoiceChip, kindLabel));
      await tester.pumpAndSettle();
    }
  }

  Future<void> saveForm(WidgetTester tester) async {
    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();
  }

  Future<List<FlashcardRow>> rows() => (db().select(
    db().flashcards,
  )..orderBy([(f) => OrderingTerm(expression: f.clozeIndex)])).get();

  testWidgets('pregunta y respuesta sigue guardando una tarjeta común', (
    tester,
  ) async {
    await openForm(tester, es.cardFormKindQa);
    await tester.enterText(
      find.widgetWithText(TextField, es.flashcardsFrontHint),
      '¿Qué es?',
    );
    await tester.enterText(
      find.widgetWithText(TextField, es.flashcardsBackHint),
      'Algo',
    );
    await saveForm(tester);

    final stored = await rows();
    expect(stored.single.kind, FlashcardKind.freeRecall);
    expect(stored.single.front, '¿Qué es?');
  });

  testWidgets('dos direcciones guarda las dos tarjetas hermanas', (
    tester,
  ) async {
    await openForm(tester, es.cardFormKindBoth);
    await tester.enterText(
      find.widgetWithText(TextField, es.flashcardsFrontHint),
      'Francia',
    );
    await tester.enterText(
      find.widgetWithText(TextField, es.flashcardsBackHint),
      'París',
    );
    await tester.pumpAndSettle();
    await saveForm(tester);

    final stored = await rows();
    expect(stored, hasLength(2));
    expect(
      {for (final r in stored) '${r.front}>${r.back}'},
      {'Francia>París', 'París>Francia'},
    );
    expect(stored[0].groupId, isNotNull);
    expect(stored[0].groupId, stored[1].groupId);
  });

  testWidgets('huecos guarda una tarjeta por hueco y la lista las muestra '
      'con el hueco tapado', (tester) async {
    await openForm(tester, es.cardFormKindCloze);
    await tester.enterText(
      find.byKey(const ValueKey('cardFormClozeText')),
      'El {{c1::Imperio}} cayó en {{c2::476}}',
    );
    await tester.pumpAndSettle();
    await saveForm(tester);

    final stored = await rows();
    expect(stored.map((r) => r.clozeIndex), [1, 2]);
    expect(stored.every((r) => r.kind == FlashcardKind.cloze), isTrue);
    // La lista no muestra las marcas: la pregunta con el hueco tapado, y lo
    // que esconde debajo.
    expect(find.text('El [...] cayó en 476'), findsOneWidget);
    expect(find.text('El Imperio cayó en [...]'), findsOneWidget);
    expect(find.text('Imperio'), findsOneWidget);
    expect(find.textContaining('{{c'), findsNothing);
  });

  testWidgets('escribí la respuesta guarda la respuesta con sus alternativas, '
      'y la lista muestra solo la respuesta', (tester) async {
    await openForm(tester, es.cardFormKindTyped);
    await tester.enterText(
      find.widgetWithText(TextField, es.flashcardsFrontHint),
      '¿Capital?',
    );
    await tester.enterText(
      find.widgetWithText(TextField, es.cardFormTypedAnswerHint),
      'Roma',
    );
    await tester.enterText(
      find.byKey(const ValueKey('cardFormAlternatives')),
      'La Urbe',
    );
    await tester.pumpAndSettle();
    await saveForm(tester);

    final stored = await rows();
    expect(stored.single.kind, FlashcardKind.typedAnswer);
    expect(stored.single.back, 'Roma\nLa Urbe');
    expect(find.text('Roma'), findsOneWidget);
    expect(find.text('La Urbe'), findsNothing);
  });

  testWidgets('opción múltiple a mano guarda la pregunta con sus opciones', (
    tester,
  ) async {
    await openForm(tester, es.cardFormKindChoice);
    await tester.enterText(
      find.widgetWithText(TextField, es.cardFormChoiceQuestionHint),
      '¿Capital?',
    );
    await tester.enterText(
      find.widgetWithText(TextField, es.cardFormChoiceCorrectHint),
      'Roma',
    );
    await tester.enterText(
      find.widgetWithText(TextField, es.cardFormChoiceDistractorHint(1)),
      'Milán',
    );
    await tester.pumpAndSettle();
    await saveForm(tester);

    final stored = await rows();
    expect(stored.single.kind, FlashcardKind.multipleChoice);
    final options = await db().select(db().flashcardOptions).get();
    expect(options.map((o) => o.content).toSet(), {'Roma', 'Milán'});
  });

  group('editar', () {
    Future<void> seedCloze() async {
      final created = await harness.container
          .read(flashcardRepositoryProvider)
          .createSiblings(
            itemId: 'a',
            drafts: SiblingCardDraft.clozes(
              text: 'El {{c1::Imperio}} cayó en {{c2::476}}',
              clozeNumbers: [1, 2],
              extra: 'Occidente',
            ),
          );
      expect(created.isRight(), isTrue, reason: '$created');
    }

    testWidgets('una de huecos vuelve a mostrar los huecos, y guardar '
        'actualiza a las hermanas', (tester) async {
      await seedCloze();
      await pumpSection(tester);

      await tester.tap(find.byTooltip(es.flashcardsEditAction).first);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cardFormClozeText')), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, es.cardFormKindQa), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('cardFormClozeText')),
        'El {{c1::Imperio romano}} cayó en {{c2::476}}',
      );
      await tester.pumpAndSettle();
      await saveForm(tester);

      final stored = await rows();
      expect(stored, hasLength(2));
      expect(
        stored.every(
          (r) => r.front == 'El {{c1::Imperio romano}} cayó en {{c2::476}}',
        ),
        isTrue,
      );
    });

    testWidgets('sacar un hueco borra su tarjeta y lo avisa', (tester) async {
      await seedCloze();
      await pumpSection(tester);

      await tester.tap(find.byTooltip(es.flashcardsEditAction).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('cardFormClozeText')),
        'El {{c1::Imperio}} cayó en 476',
      );
      await tester.pumpAndSettle();
      expect(find.text(es.cardFormClozeRemovesCards(1)), findsOneWidget);
      await saveForm(tester);

      expect((await rows()).map((r) => r.clozeIndex), [1]);
      expect(find.text(es.cardFormClozeEdited(0, 1)), findsOneWidget);
    });

    testWidgets('una de escribí la respuesta conserva su forma', (
      tester,
    ) async {
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(
            itemId: 'a',
            front: '¿Capital?',
            back: 'Roma\nLa Urbe',
            kind: FlashcardKind.typedAnswer,
          );
      await pumpSection(tester);

      await tester.tap(find.byTooltip(es.flashcardsEditAction));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'La Urbe'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Roma'),
        'Roma antigua',
      );
      await saveForm(tester);

      final stored = (await rows()).single;
      expect(stored.kind, FlashcardKind.typedAnswer);
      expect(stored.back, 'Roma antigua\nLa Urbe');
    });

    testWidgets('sin cambios no escribe nada', (tester) async {
      await seedCloze();
      await pumpSection(tester);
      final before = await rows();

      await tester.tap(find.byTooltip(es.flashcardsEditAction).first);
      await tester.pumpAndSettle();
      await saveForm(tester);

      final after = await rows();
      expect(after.map((r) => r.back), before.map((r) => r.back));
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('huecos con IA', () {
    Future<KnowledgeItem> captured(String text) async {
      await harness.capture('Historia\n\n$text');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getOrElse((f) => fail('$f'));
      return items.singleWhere((i) => i.title == 'Historia');
    }

    Future<void> generate(WidgetTester tester, KnowledgeItem shown) async {
      await pumpSection(tester, shown);
      await tester.tap(find.byTooltip(es.flashcardsAddAction));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, es.cardFormKindClozeAi));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.cardFormAiGenerate));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra lo que propone para revisar y guarda lo aceptado '
        'con su pasaje', (tester) async {
      final shown = await captured(
        'El Imperio romano cayó en el año 476. Constantinopla cayó en 1453.',
      );
      final text = extractableRendition(shown)!.content;
      clozeModel.drafts = [
        const ClozeDraft(
          text: 'El {{c1::Imperio romano}} cayó en el año {{c2::476}}',
          quote: 'El Imperio romano cayó en el año 476.',
        ),
      ];

      await generate(tester, shown);

      expect(find.text(es.cardFormAiReviewTitle), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      // Nada se guardó todavía.
      expect(await rows(), isEmpty);

      await tester.tap(find.text(es.flashcardsSaveSelected));
      await tester.pumpAndSettle();

      final stored = await rows();
      expect(stored, hasLength(2));
      expect(stored.every((r) => r.kind == FlashcardKind.cloze), isTrue);
      expect(stored[0].groupId, stored[1].groupId);
      final fragment = text.substring(
        stored.first.sourceCharStart!,
        stored.first.sourceCharEnd,
      );
      expect(fragment, startsWith('El Imperio romano cayó'));
      expect(find.text(es.cardFormAiSavedCount(2)), findsOneWidget);
    });

    testWidgets('lo descartado en la revisión no se guarda', (tester) async {
      final shown = await captured('El Imperio romano cayó en el año 476.');
      clozeModel.drafts = [
        const ClozeDraft(text: 'El {{c1::Imperio romano}} cayó'),
      ];

      await generate(tester, shown);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.flashcardsSaveSelected));
      await tester.pumpAndSettle();

      expect(await rows(), isEmpty);
    });

    testWidgets('sin el modelo de lenguaje lo dice y ofrece bajarlo', (
      tester,
    ) async {
      final shown = await captured('El Imperio romano cayó en el año 476.');
      clozeModel.failWith = const ChatModelNotReadyException();

      await generate(tester, shown);

      expect(find.text(es.flashcardsModelMissing), findsOneWidget);
      expect(find.text(es.cardFormAiReviewTitle), findsNothing);
    });

    testWidgets('si el modelo no propone nada que sirva, lo dice', (
      tester,
    ) async {
      final shown = await captured('El Imperio romano cayó en el año 476.');

      await generate(tester, shown);

      expect(find.text(es.flashcardsGenerationEmpty), findsOneWidget);
    });

    testWidgets('un elemento sin texto lo dice sin llamar al modelo', (
      tester,
    ) async {
      await generate(tester, item);

      expect(find.text(es.cardFormAiNoContent), findsOneWidget);
      expect(clozeModel.calls, 0);
    });
  });
}

/// Un modelo de huecos de mentira: devuelve [drafts] o falla con [failWith].
class _ClozeModel implements ClozeGenerator {
  List<ClozeDraft> drafts = const [];
  Exception? failWith;
  int calls = 0;

  @override
  Future<List<ClozeDraft>> generateClozes({
    required String content,
    int count = 5,
  }) async {
    calls++;
    final error = failWith;
    if (error != null) throw error;
    return drafts;
  }
}
