import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/create_hub/domain/create_kind.dart';
import 'package:sinapsis/features/create_hub/presentation/widgets/create_button.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/fake_ai_organize_queue.dart';
import '../../../support/library_harness.dart';

const _id = 'f45-nota';
final _now = DateTime(2026, 10, 30, 10);

/// Una nota propia con [texts] como formas de texto —la primera, la
/// principal—.
KnowledgeItem _note({
  List<String> texts = const ['Nació en 1809.'],
  ProcessingState state = ProcessingState.ready,
}) => KnowledgeItem(
  id: _id,
  title: 'Una nota',
  source: Source(id: _id, kind: SourceKind.manualNote, capturedAt: _now),
  processingState: state,
  createdAt: _now,
  updatedAt: _now,
  renditions: [
    for (final (index, content) in texts.indexed)
      Rendition.text(
        id: '$_id-texto-$index',
        itemId: _id,
        kind: RenditionKind.plainText,
        content: content,
        isPrimary: index == 0,
        createdAt: _now,
      ),
  ],
);

/// Organizar una nota propia y buscarle fechas con la IA, desde «Crear» (F45,
/// paso 7b, mejora 14): lo que antes estaba en el «Más» de su panel, con los
/// mismos avisos —no dicen «en un momento» si no es cierto—.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  /// Guarda [item] y muestra el ✨ «Crear» de su barra, siguiendo al elemento
  /// en la base.
  Future<void> pumpCreate(
    WidgetTester tester,
    KnowledgeItem item, {
    bool chatModelReady = false,
    List<Override> extraOverrides = const [],
    Future<void> Function()? beforeShow,
  }) async {
    harness = await LibraryHarness.create(
      chatModelReady: chatModelReady,
      extraOverrides: extraOverrides,
    );
    await harness.container.read(libraryRepositoryProvider).save(item);
    await beforeShow?.call();

    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          appBar: AppBar(
            actions: [
              Consumer(
                builder: (context, ref, _) {
                  final current = ref
                      .watch(libraryItemProvider(item.id))
                      .valueOrNull;
                  return current == null
                      ? const SizedBox.shrink()
                      : CreateButton(target: CreateTarget.note(current));
                },
              ),
            ],
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCreate(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('create-button')));
    await tester.pumpAndSettle();
  }

  group('organizar con la IA (F27)', () {
    late FakeAiOrganizeQueue queue;

    Future<void> pumpWithQueue(
      WidgetTester tester, {
      required bool modelsReady,
    }) async {
      queue = FakeAiOrganizeQueue();
      // Una nota propia: una fuente se organiza en su documento procesado
      // (F41, decisión K).
      await pumpCreate(
        tester,
        _note(texts: const ['Un artículo.']),
        chatModelReady: modelsReady,
        extraOverrides: [aiOrganizeQueueProvider.overrideWithValue(queue)],
        beforeShow: () async =>
            harness.embeddingModelManager.ready = modelsReady,
      );
    }

    Future<void> organize(WidgetTester tester) async {
      await openCreate(tester);
      await tester.tap(find.byKey(const Key('create-organize')));
      await tester.pumpAndSettle();
    }

    testWidgets('se lo pide a la cola y avisa que lo organiza en un momento', (
      tester,
    ) async {
      await pumpWithQueue(tester, modelsReady: true);
      await organize(tester);

      expect(queue.organizeNowCalls, [_id]);
      expect(find.text(es.aiOrganizeNowQueued), findsOneWidget);
      // La hoja se cerró antes de pedirlo.
      expect(find.byKey(const Key('create-sheet')), findsNothing);
    });

    testWidgets('si falta un modelo, lo pide igual y dice que espera', (
      tester,
    ) async {
      await pumpWithQueue(tester, modelsReady: false);
      await organize(tester);

      expect(queue.organizeNowCalls, [_id]);
      expect(find.text(es.aiOrganizeNowNeedsModel), findsOneWidget);
    });

    testWidgets('con la IA en pausa, lo pide igual y dice cuándo sigue', (
      tester,
    ) async {
      await pumpWithQueue(tester, modelsReady: true);
      await harness.container
          .read(aiOrganizeSettingsProvider.notifier)
          .set(AiOrganizeToggle.enabled, on: false);
      await organize(tester);

      expect(queue.organizeNowCalls, [_id]);
      expect(find.text(es.aiOrganizeNowPaused), findsOneWidget);
    });

    group('con la IA en la nube (F32)', () {
      late List<bool> asked;

      Future<void> pumpWithCloud(
        WidgetTester tester,
        LanguageModelStatus status,
      ) async {
        queue = FakeAiOrganizeQueue();
        asked = [];
        await pumpCreate(
          tester,
          _note(texts: const ['Un artículo.']),
          extraOverrides: [
            aiOrganizeQueueProvider.overrideWithValue(queue),
            languageModelStatusCheckProvider.overrideWithValue(({
              bool background = false,
            }) async {
              asked.add(background);
              return status;
            }),
          ],
          beforeShow: () async => harness.embeddingModelManager.ready = true,
        );
      }

      testWidgets('lista, avisa que lo organiza y pregunta por la de fondo', (
        tester,
      ) async {
        await pumpWithCloud(
          tester,
          const LanguageModelReady(provider: AiProvider.gemini),
        );
        await organize(tester);

        expect(queue.organizeNowCalls, [_id]);
        expect(find.text(es.aiOrganizeNowQueued), findsOneWidget);
        // Lo hace la IA de fondo: con su tope del día, no con el de la
        // persona.
        expect(asked, [true]);
      });

      testWidgets('sin clave, lo pide igual y dice que falta la clave', (
        tester,
      ) async {
        await pumpWithCloud(
          tester,
          const LanguageModelNeedsAccount(provider: AiProvider.gemini),
        );
        await organize(tester);

        expect(queue.organizeNowCalls, [_id]);
        expect(find.text(es.aiOrganizeNowNeedsKey), findsOneWidget);
        expect(find.text(es.aiOrganizeNowNeedsModel), findsNothing);
      });

      for (final (name, status) in [
        (
          'sin cuota',
          LanguageModelOutOfQuota(
            provider: AiProvider.gemini,
            accounts: 2,
            resetsAt: DateTime(2026, 10, 17, 4),
          ),
        ),
        (
          'en el tope del día de la IA de fondo',
          LanguageModelBackgroundCapReached(
            provider: AiProvider.gemini,
            cap: 200,
            resetsAt: DateTime(2026, 10, 17, 4),
          ),
        ),
      ]) {
        testWidgets('$name, lo pide igual y dice que espera la cuota', (
          tester,
        ) async {
          await pumpWithCloud(tester, status);
          await organize(tester);

          expect(queue.organizeNowCalls, [_id]);
          expect(find.text(es.aiOrganizeNowWaits), findsOneWidget);
        });
      }

      testWidgets('lista pero sin el modelo de búsqueda, dice que falta '
          'bajarlo', (tester) async {
        await pumpWithCloud(
          tester,
          const LanguageModelReady(provider: AiProvider.gemini),
        );
        harness.embeddingModelManager.ready = false;
        await organize(tester);

        expect(find.text(es.aiOrganizeNowNeedsModel), findsOneWidget);
      });
    });
  });

  group('buscar fechas con IA (F40)', () {
    late FakeAiOrganizeQueue queue;
    late List<bool> asked;

    Future<void> pumpWith(
      WidgetTester tester, {
      List<String> texts = const ['Nació en 1809.'],
      ProcessingState state = ProcessingState.ready,
      bool modelsReady = true,
      LanguageModelStatus? cloud,
    }) async {
      queue = FakeAiOrganizeQueue();
      asked = [];
      await pumpCreate(
        tester,
        _note(texts: texts, state: state),
        chatModelReady: modelsReady,
        extraOverrides: [
          aiOrganizeQueueProvider.overrideWithValue(queue),
          if (cloud != null)
            languageModelStatusCheckProvider.overrideWithValue(({
              bool background = false,
            }) async {
              asked.add(background);
              return cloud;
            }),
        ],
        beforeShow: () async =>
            harness.embeddingModelManager.ready = modelsReady,
      );
    }

    Future<void> findDates(WidgetTester tester) async {
      await openCreate(tester);
      await tester.tap(find.byKey(const Key('create-dates')));
      await tester.pumpAndSettle();
    }

    testWidgets('«Crear» la ofrece con lo que hace, después de organizar', (
      tester,
    ) async {
      await pumpWith(tester);
      await openCreate(tester);

      expect(find.byKey(const Key('create-dates')), findsOneWidget);
      expect(find.text(es.f45S7bDates), findsOneWidget);
      expect(find.text(es.f45S7bDatesHint), findsOneWidget);
      // Las dos cosas de la IA llevan su ✨.
      expect(
        find.descendant(
          of: find.byKey(const Key('create-dates')),
          matching: find.byType(AiSparkCircle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('create-organize')),
          matching: find.byType(AiSparkCircle),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('create-organize'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('create-dates'))).dy),
      );
    });

    testWidgets('le pide a la cola solo las fechas de ese elemento y avisa '
        'que las busca en un rato', (tester) async {
      await pumpWith(tester);
      await findDates(tester);

      expect(queue.dateRequests, [
        [_id],
      ]);
      // No pidió organizarlo entero.
      expect(queue.organizeNowCalls, isEmpty);
      expect(find.text(es.datesAskQueued(1)), findsOneWidget);
      // La hoja se cerró antes de pedirlo.
      expect(find.byKey(const Key('create-sheet')), findsNothing);
    });

    testWidgets('sin texto se ve apagada, con el porqué: no hay fechas que '
        'buscar; organizar sigue', (tester) async {
      await pumpWith(tester, texts: const []);
      await openCreate(tester);

      expect(find.byKey(const Key('create-organize')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('create-dates')),
          matching: find.text(es.f45S7bBlockNoText),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('create-dates')));
      await tester.pumpAndSettle();
      expect(queue.dateRequests, isEmpty);
    });

    testWidgets('con un texto en blanco tampoco', (tester) async {
      await pumpWith(tester, texts: const ['  \n  ']);
      await openCreate(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('create-dates')),
          matching: find.text(es.f45S7bBlockNoText),
        ),
        findsOneWidget,
      );
    });

    testWidgets('con el texto en cualquiera de sus formas se ofrece', (
      tester,
    ) async {
      await pumpWith(tester, texts: const ['', 'Nació en 1809.']);
      await openCreate(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('create-dates')),
          matching: find.text(es.f45S7bDatesHint),
        ),
        findsOneWidget,
      );
    });

    test('mientras se procesa o si falló, ni organizar ni buscar fechas: el '
        'texto va a cambiar', () {
      for (final state in [
        ProcessingState.pending,
        ProcessingState.processing,
        ProcessingState.failed,
      ]) {
        final target = CreateTarget.note(_note(state: state));
        expect(
          target.blockOf(CreateKind.dates),
          CreateBlock.notReady,
          reason: state.name,
        );
        expect(
          target.blockOf(CreateKind.organize),
          CreateBlock.notReady,
          reason: state.name,
        );
      }
    });

    testWidgets('si falta un modelo, lo pide igual y dice que espera', (
      tester,
    ) async {
      await pumpWith(tester, modelsReady: false);
      await findDates(tester);

      expect(queue.dateRequests, hasLength(1));
      expect(find.text(es.datesAskNeedsModel(1)), findsOneWidget);
    });

    testWidgets('con la IA en pausa, lo pide igual y dice cuándo sigue', (
      tester,
    ) async {
      await pumpWith(tester);
      await harness.container
          .read(aiOrganizeSettingsProvider.notifier)
          .set(AiOrganizeToggle.enabled, on: false);
      await findDates(tester);

      expect(queue.dateRequests, hasLength(1));
      expect(find.text(es.datesAskPaused(1)), findsOneWidget);
    });

    testWidgets('no necesita el modelo de búsqueda: con el de lenguaje '
        'listo, alcanza', (tester) async {
      await pumpWith(tester);
      harness.embeddingModelManager.ready = false;
      await findDates(tester);

      expect(find.text(es.datesAskQueued(1)), findsOneWidget);
      expect(find.text(es.datesAskNeedsModel(1)), findsNothing);
    });

    group('con la IA en la nube (F32)', () {
      testWidgets('lista: avisa y pregunta por la de fondo', (tester) async {
        await pumpWith(
          tester,
          cloud: const LanguageModelReady(provider: AiProvider.gemini),
        );
        await findDates(tester);

        expect(find.text(es.datesAskQueued(1)), findsOneWidget);
        expect(asked, [true]);
      });

      testWidgets('sin clave, lo pide igual y dice que falta la clave', (
        tester,
      ) async {
        await pumpWith(
          tester,
          cloud: const LanguageModelNeedsAccount(provider: AiProvider.gemini),
        );
        await findDates(tester);

        expect(queue.dateRequests, hasLength(1));
        expect(find.text(es.datesAskNeedsKey(1)), findsOneWidget);
      });

      testWidgets('sin cuota, lo pide igual y dice que espera', (tester) async {
        await pumpWith(
          tester,
          cloud: LanguageModelOutOfQuota(
            provider: AiProvider.gemini,
            accounts: 1,
            resetsAt: DateTime(2026, 10, 17, 4),
          ),
        );
        await findDates(tester);

        expect(queue.dateRequests, hasLength(1));
        expect(find.text(es.datesAskWaits(1)), findsOneWidget);
      });
    });
  });
}
