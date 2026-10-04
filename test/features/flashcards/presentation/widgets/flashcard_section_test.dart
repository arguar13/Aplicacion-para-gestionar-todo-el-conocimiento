import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcards_by_parts.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_section.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// Las tarjetas de un elemento (F27): todas se editan, y las que hizo la IA
/// llevan la marca ✨ y se les puede decir que «no era», con «Deshacer».
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late KnowledgeItem item;
  late _PartsGenerator model;

  setUp(() async {
    model = _PartsGenerator();
    harness = await LibraryHarness.create(
      extraOverrides: [flashcardGeneratorProvider.overrideWithValue(model)],
    );
    await insertItemRows(harness.database, id: 'a', title: 'Termodinámica');
    item =
        (await harness.container.read(libraryRepositoryProvider).findById('a'))
            .getOrElse((f) => fail('$f'))!;
  });

  AppDatabase db() => harness.database;

  Future<void> seedCard({
    bool byAi = false,
    bool multipleChoice = false,
  }) async {
    AiProvenance? ai;
    if (byAi) {
      final run = await harness.container
          .read(aiRunRepositoryProvider)
          .startRun('a');
      ai = AiProvenance(runId: run.getOrElse((f) => fail('$f')));
    }
    final repository = harness.container.read(flashcardRepositoryProvider);
    final created = multipleChoice
        ? await repository.createMultipleChoice(
            itemId: 'a',
            front: '¿Qué mide?',
            options: const [
              FlashcardOptionDraft(content: 'El desorden', isCorrect: true),
              FlashcardOptionDraft(content: 'El orden', isCorrect: false),
            ],
            ai: ai,
          )
        : await repository.create(
            itemId: 'a',
            front: '¿Qué es la entropía?',
            back: 'El desorden.',
            ai: ai,
          );
    expect(created.isRight(), isTrue, reason: '$created');
  }

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: SingleChildScrollView(child: FlashcardSection(item: item)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  testWidgets('una de la IA lleva la marca; una de la persona, no', (
    tester,
  ) async {
    await seedCard(byAi: true);
    await pumpSection(tester);
    expect(find.byTooltip(es.flashcardMadeByAi), findsOneWidget);

    await db().delete(db().flashcards).go();
    await seedCard();
    await pumpSection(tester);
    expect(find.byTooltip(es.flashcardMadeByAi), findsNothing);
  });

  testWidgets('editarla abre su pregunta y su respuesta, y al guardar deja de '
      'ser de la IA', (tester) async {
    await seedCard(byAi: true);
    await pumpSection(tester);

    await tester.tap(find.byTooltip(es.flashcardsEditAction));
    await tester.pumpAndSettle();

    expect(find.text(es.flashcardsEditAction), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '¿Qué es la entropía?'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'El desorden.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '¿Qué es la entropía?'),
      '¿Qué mide la entropía?',
    );
    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();

    final row = await db().select(db().flashcards).getSingle();
    expect(row.front, '¿Qué mide la entropía?');
    expect(row.back, 'El desorden.');
    expect(row.origin, ContentOrigin.user);
    expect(row.aiRunId, isNull);
    expect(find.byTooltip(es.flashcardMadeByAi), findsNothing);
  });

  testWidgets('cancelar la edición no cambia nada', (tester) async {
    await seedCard(byAi: true);
    await pumpSection(tester);

    await tester.tap(find.byTooltip(es.flashcardsEditAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.commonCancel));
    await tester.pumpAndSettle();

    expect(
      (await db().select(db().flashcards).getSingle()).origin,
      ContentOrigin.ai,
    );
  });

  testWidgets('«No era» la borra, avisa, y «Deshacer» la devuelve', (
    tester,
  ) async {
    await seedCard(byAi: true);
    await pumpSection(tester);

    await openMenu(tester);
    await tester.tap(find.text(es.aiNotRight));
    await tester.pumpAndSettle();

    expect(find.text(es.flashcardRejected), findsOneWidget);
    expect(await db().select(db().flashcards).get(), isEmpty);
    expect(await db().select(db().aiRejections).get(), hasLength(1));

    await tester.tap(find.text(es.aiRejectionUndo));
    await tester.pumpAndSettle();

    expect(
      (await db().select(db().flashcards).getSingle()).origin,
      ContentOrigin.ai,
    );
    expect(await db().select(db().aiRejections).get(), isEmpty);
  });

  testWidgets('a una de la persona solo se la borra', (tester) async {
    await seedCard();
    await pumpSection(tester);

    await openMenu(tester);
    expect(find.text(es.aiNotRight), findsNothing);
    await tester.tap(find.text(es.flashcardsDeleteAction));
    await tester.pumpAndSettle();

    expect(await db().select(db().flashcards).get(), isEmpty);
    expect(await db().select(db().aiRejections).get(), isEmpty);
  });

  testWidgets('una de opción múltiple no se edita acá', (tester) async {
    await seedCard(byAi: true, multipleChoice: true);
    await pumpSection(tester);

    expect(find.byTooltip(es.flashcardsEditAction), findsNothing);
    expect(find.byTooltip(es.flashcardMadeByAi), findsOneWidget);
  });

  group('el ✨ lee por partes (F30)', () {
    /// Un libro: miles de oraciones, mucho más de lo que entra en la ventana
    /// del modelo.
    final book = [
      for (var i = 0; i < 3000; i++) 'La idea número $i del libro es esta.',
    ].join(' ');

    Future<KnowledgeItem> captured(String text) async {
      await harness.capture('Un libro\n\n$text');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getOrElse((f) => fail('$f'));
      return items.singleWhere((i) => i.title == 'Un libro');
    }

    Future<void> pumpAndGenerate(
      WidgetTester tester,
      KnowledgeItem item,
    ) async {
      await tester.pumpWidget(
        harness.wrap(
          Scaffold(
            body: SingleChildScrollView(child: FlashcardSection(item: item)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(es.flashcardsGenerateAction));
      await tester.pumpAndSettle();
    }

    testWidgets('un texto largo se le manda de a partes que entran en la '
        'ventana, y cada tarjeta guarda el pasaje real', (tester) async {
      final item = await captured(book);
      final text = extractableRendition(item)!.content;

      await pumpAndGenerate(tester, item);

      expect(model.contents.length, greaterThan(1));
      expect(
        model.contents.every((c) => c.length <= kFlashcardPartChars),
        isTrue,
      );
      // Repartidas por el libro, no todas del principio.
      expect(model.contents.last, isNot(contains('número 0 ')));
      expect(find.text(es.flashcardsReviewTitle), findsOneWidget);

      await tester.tap(find.text(es.flashcardsSaveSelected));
      await tester.pumpAndSettle();

      final rows = await harness.database
          .select(harness.database.flashcards)
          .get();
      expect(rows, hasLength(model.contents.length));
      for (final row in rows) {
        // La cita llegó parafraseada —en minúsculas y sin el punto—; el
        // fragmento es la oración del texto.
        final fragment = text.substring(
          row.sourceCharStart!,
          row.sourceCharEnd,
        );
        expect(row.back, startsWith(fragment));
      }
    });

    testWidgets('sin el modelo de lenguaje lo dice, y ofrece bajarlo', (
      tester,
    ) async {
      model.failWith = const ChatModelNotReadyException();
      final item = await captured(book);

      await pumpAndGenerate(tester, item);

      expect(find.text(es.flashcardsModelMissing), findsOneWidget);
      expect(find.text(es.flashcardsDownloadModel), findsOneWidget);
      expect(find.text(es.flashcardsReviewTitle), findsNothing);
    });

    testWidgets('si el modelo falla a mitad, ofrece lo que alcanzó a proponer '
        'y dice que falló', (tester) async {
      model
        ..failWith = const _OutOfMemory()
        ..failAfter = 1;
      final item = await captured(book);

      await pumpAndGenerate(tester, item);

      expect(find.text(es.flashcardsGenerationPartial), findsOneWidget);
      expect(find.text(es.flashcardsReviewTitle), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });

    testWidgets('si falla sin proponer nada, lo dice', (tester) async {
      model.failWith = const _OutOfMemory();
      final item = await captured(book);

      await pumpAndGenerate(tester, item);

      expect(find.text(es.flashcardsGenerationFailed), findsOneWidget);
      expect(find.text(es.flashcardsReviewTitle), findsNothing);
    });

    testWidgets('no vuelve a proponer una pregunta que el elemento ya tiene', (
      tester,
    ) async {
      final item = await captured('Roma fue fundada en el año 753.');
      // La pregunta que el modelo de mentira va a proponer: la de la primera
      // oración del texto, que también lleva el título.
      final text = extractableRendition(item)!.content;
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: item.id, front: _questionAbout(text), back: 'x');

      await pumpAndGenerate(tester, item);

      expect(find.text(es.flashcardsGenerationEmpty), findsOneWidget);
    });
  });
}

/// Un modelo de tarjetas de mentira: una tarjeta por parte, sobre su primera
/// oración, con la cita parafraseada —en minúsculas y sin el punto—. Puede
/// fallar desde el pedido [failAfter].
class _PartsGenerator implements FlashcardGenerator {
  final contents = <String>[];
  Exception? failWith;
  int failAfter = 0;

  @override
  Future<List<FlashcardDraft>> generate({
    required String content,
    int count = 5,
  }) async {
    final error = failWith;
    if (error != null && contents.length >= failAfter) throw error;
    contents.add(content);
    final sentence = _firstSentence(content);
    return [
      FlashcardDraft(
        front: _questionAbout(content),
        back: sentence,
        quote: sentence.toLowerCase().replaceAll('.', ''),
      ),
    ];
  }
}

String _firstSentence(String text) =>
    RegExp(r'[^.]+\.').firstMatch(text)!.group(0)!.trim();

String _questionAbout(String text) => '¿Qué dice «${_firstSentence(text)}»?';

/// Lo que lanza un modelo que se quedó sin memoria a mitad de una respuesta.
class _OutOfMemory implements Exception {
  const _OutOfMemory();
}
