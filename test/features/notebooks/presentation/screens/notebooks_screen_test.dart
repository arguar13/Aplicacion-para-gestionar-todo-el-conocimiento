import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_suggestions_controller.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebook_detail_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebooks_screen.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Lo que «encuentra» Crear con IA: lo que la prueba le da.
class _FakeFinder implements NotebookCandidateFinder {
  List<NotebookCandidate> candidates = const [];
  final topics = <String>[];

  @override
  Future<NotebookSearchResult> find(
    String topic, {
    int limit = kNotebookCandidateLimit,
  }) async {
    topics.add(topic);
    return NotebookSearchResult(
      candidates: candidates,
      senseSearch: SenseSearch.unavailable,
    );
  }
}

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late _FakeFinder finder;

  setUp(() async {
    finder = _FakeFinder();
    harness = await LibraryHarness.create(
      extraOverrides: [
        notebookCandidateFinderProvider.overrideWithValue(finder),
      ],
    );
  });

  GoRouter router() => GoRouter(
    routes: [
      GoRoute(
        path: RoutePaths.notebooks,
        builder: (_, _) => const NotebooksScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                NotebookDetailScreen(notebookId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.itemDetailPattern,
        builder: (_, state) =>
            Scaffold(body: Text('detalle de ${state.pathParameters['id']}')),
      ),
    ],
    initialLocation: RoutePaths.notebooks,
  );

  Future<void> pumpNotebooks(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('la pantalla de cuadernos', () {
    testWidgets('sin ninguno, explica para qué sirve un cuaderno', (
      tester,
    ) async {
      await pumpNotebooks(tester);

      expect(find.text(es.notebooksEmptyTitle), findsOneWidget);
    });

    testWidgets('crear uno manual lo deja en la lista', (tester) async {
      await pumpNotebooks(tester);

      await tester.tap(find.byKey(const Key('notebook-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notebook-new-manual')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('notebook-name-field')),
        'Tesis',
      );
      await tester.tap(find.byKey(const Key('notebook-confirm-create')));
      await tester.pumpAndSettle();

      expect(find.text('Tesis'), findsOneWidget);
      expect(find.text(es.notebooksModeManual), findsOneWidget);
    });

    testWidgets('sin ninguna vista guardada, el modo "por consulta" no está '
        'disponible', (tester) async {
      await pumpNotebooks(tester);

      await tester.tap(find.byKey(const Key('notebook-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notebook-new-manual')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SegmentedButton<NotebookMode>>(
              find.byType(SegmentedButton<NotebookMode>),
            )
            .segments
            .firstWhere((s) => s.value == NotebookMode.query)
            .enabled,
        isFalse,
      );
    });

    testWidgets('«Crear con IA»: se escribe de qué es, se destilda o tilda lo '
        'propuesto y se crea con los marcados (F30)', (tester) async {
      await harness.capture('El foro romano');
      await harness.capture('El Senado');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final foro = items.firstWhere((i) => i.title == 'El foro romano');
      final senado = items.firstWhere((i) => i.title == 'El Senado');
      finder.candidates = [
        NotebookCandidate(
          itemId: foro.id,
          title: foro.title,
          excerpt: 'El centro de Roma.',
          kind: SourceKind.webPage,
          matchedText: true,
        ),
        NotebookCandidate(
          itemId: senado.id,
          title: senado.title,
          excerpt: 'Trescientos miembros.',
          kind: SourceKind.webPage,
          similarity: 0.5,
        ),
      ];

      await pumpNotebooks(tester);
      await tester.tap(find.byKey(const Key('notebook-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notebook-new-ai')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ai-notebook-topic')),
        'mi tesis sobre Roma',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-notebook-search')));
      await tester.pumpAndSettle();

      expect(finder.topics, ['mi tesis sobre Roma']);
      expect(find.text(es.aiNotebookFound(2)), findsOneWidget);
      expect(find.text('Mi tesis sobre Roma'), findsOneWidget);
      // Sin el modelo de lenguaje: marcado lo que encontraron las palabras.
      expect(find.text(es.aiNotebookNotReviewed), findsOneWidget);
      CheckboxListTile tile(String id) => tester.widget<CheckboxListTile>(
        find.byKey(Key('ai-notebook-pick-$id')),
      );
      expect(tile(foro.id).value, isTrue);
      expect(tile(senado.id).value, isFalse);

      await tester.tap(find.byKey(Key('ai-notebook-pick-${senado.id}')));
      await tester.pump();
      expect(find.text(es.aiNotebookCreate(2)), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-notebook-create')));
      await tester.pumpAndSettle();

      // Se abre el cuaderno nuevo, con los dos.
      expect(find.text('Mi tesis sobre Roma'), findsOneWidget);
      expect(find.text('El foro romano'), findsOneWidget);
      expect(find.text('El Senado'), findsOneWidget);
      final notebook =
          (await harness.database.select(harness.database.notebooks).get())
              .single;
      expect(notebook.mode, NotebookMode.manual);
      expect(
        (await harness.container
                .read(notebookRepositoryProvider)
                .resolveQuery(notebook.id))
            .ids,
        {foro.id, senado.id},
      );
    });

    /// Un tema con [count] elementos, y la lista de cuadernos abierta.
    Future<String> seedTopic(int count, {String name = 'Roma'}) async {
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace(name))
              .getRight()
              .toNullable()!;
      for (var i = 0; i < count; i++) {
        await harness.capture('$name $i');
      }
      final ids =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .matchingIds(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpaceMany(itemIds: ids, spaceId: space.id);
      return space.id;
    }

    testWidgets('un tema con elementos de sobra se sugiere: se avisa, se '
        'elige y se crea un cuaderno por consulta que se abre (F30)', (
      tester,
    ) async {
      final spaceId = await seedTopic(3);

      await pumpNotebooks(tester);
      expect(
        find.byKey(const Key('notebooks-suggestions-banner')),
        findsOneWidget,
      );
      expect(find.text(es.notebooksSuggestedBannerTitle(1)), findsOneWidget);

      await tester.tap(find.byKey(const Key('notebooks-suggestions-view')));
      await tester.pumpAndSettle();
      // Sin el modelo de lenguaje, lleva el nombre del tema; sin marcar.
      expect(find.text(es.suggestedNotebooksNoModel), findsOneWidget);
      expect(find.text('Roma'), findsOneWidget);
      expect(find.text(es.suggestedNotebooksKindSpace(3)), findsOneWidget);
      final create = find.byKey(const Key('suggested-notebooks-create'));
      expect(tester.widget<FilledButton>(create).onPressed, isNull);

      await tester.tap(find.byKey(Key('suggested-notebook-space:$spaceId')));
      await tester.pump();
      expect(find.text(es.suggestedNotebooksCreate(1)), findsOneWidget);
      await tester.tap(create);
      await tester.pumpAndSettle();

      final created = await harness.database
          .select(harness.database.notebooks)
          .get();
      expect(created.single.name, 'Roma');
      expect(created.single.mode, NotebookMode.query);
      expect(
        (await harness.container
                .read(notebookRepositoryProvider)
                .resolveQuery(created.single.id))
            .spaceId,
        spaceId,
      );
      // Con uno solo, se abre; sus elementos son los del tema.
      expect(find.text('Roma 0'), findsOneWidget);
    });

    testWidgets('«Ahora no» deja de avisar de los que hay, y lo recuerda '
        '(F30)', (tester) async {
      await seedTopic(3);

      await pumpNotebooks(tester);
      await tester.tap(find.byKey(const Key('notebooks-suggestions-not-now')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notebooks-suggestions-banner')),
        findsNothing,
      );
      final dismissed = harness.container.read(
        notebookSuggestionDismissalsProvider,
      );
      expect(dismissed, hasLength(1));
      // Tampoco en «Nuevo cuaderno».
      await tester.tap(find.byKey(const Key('notebook-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notebook-new-suggested')), findsNothing);
    });

    testWidgets('con pocos elementos no se sugiere nada, y «Nuevo cuaderno» '
        'no ofrece los sugeridos (F30)', (tester) async {
      await seedTopic(2);

      await pumpNotebooks(tester);
      expect(
        find.byKey(const Key('notebooks-suggestions-banner')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('notebook-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notebook-new-suggested')), findsNothing);
    });

    testWidgets('lo que ya es un cuaderno por esa consulta no se vuelve a '
        'sugerir (F30)', (tester) async {
      final spaceId = await seedTopic(3);
      await harness.container
          .read(notebookRepositoryProvider)
          .create(
            name: 'Otro nombre',
            mode: NotebookMode.query,
            query: LibraryQuery(spaceId: spaceId),
          );

      await pumpNotebooks(tester);

      expect(
        find.byKey(const Key('notebooks-suggestions-banner')),
        findsNothing,
      );
    });

    testWidgets('sin ningún cuaderno, «Crear con IA» está a mano (F30)', (
      tester,
    ) async {
      await pumpNotebooks(tester);

      await tester.tap(find.byKey(const Key('notebooks-empty-ai')));
      await tester.pumpAndSettle();

      expect(find.text(es.aiNotebookTitle), findsOneWidget);
      expect(find.text(es.aiNotebookSenseOff), findsOneWidget);
      expect(find.text(es.aiNotebookReviewOff), findsOneWidget);
    });

    testWidgets('borrar un cuaderno lo saca de la lista', (tester) async {
      await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Para borrar', mode: NotebookMode.manual);

      await pumpNotebooks(tester);
      expect(find.text('Para borrar'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notebook-confirm-delete')));
      await tester.pumpAndSettle();

      expect(find.text('Para borrar'), findsNothing);
    });
  });

  group('el detalle de un cuaderno manual', () {
    testWidgets('agregar y sacar un elemento cambia el panel, no la bóveda', (
      tester,
    ) async {
      await harness.capture('Un artículo cualquiera');
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'A mano', mode: NotebookMode.manual);

      await pumpNotebooks(tester);
      await tester.tap(find.byKey(Key('notebook-${notebook.id}')));
      await tester.pumpAndSettle();

      expect(find.text(es.notebookDetailEmpty), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Un artículo cualquiera'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-items-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Un artículo cualquiera'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text(es.notebookDetailEmpty), findsOneWidget);
      // Sigue en la biblioteca: sacarlo del cuaderno no lo borró.
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      expect(items, hasLength(1));
    });

    testWidgets('se agregan varios a la vez, y los que ya están se ven '
        'marcados sin poder tocarlos (F30)', (tester) async {
      await harness.capture('Roma antigua');
      await harness.capture('El Senado');
      await harness.capture('Las guerras púnicas');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      KnowledgeItem titled(String title) =>
          items.firstWhere((i) => i.title == title);
      final first = titled('Roma antigua');
      final second = titled('El Senado');
      final third = titled('Las guerras púnicas');
      final repository = harness.container.read(notebookRepositoryProvider);
      final notebook = await repository.create(
        name: 'Roma',
        mode: NotebookMode.manual,
      );
      await repository.addItem(notebookId: notebook.id, itemId: first.id);

      await pumpNotebooks(tester);
      await tester.tap(find.byKey(Key('notebook-${notebook.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final already = tester.widget<CheckboxListTile>(
        find.byKey(Key('pick-items-${first.id}')),
      );
      expect(already.value, isTrue);
      expect(already.onChanged, isNull);
      expect(find.text(es.pickItemsAlreadyIn), findsOneWidget);

      await tester.tap(find.byKey(Key('pick-items-${second.id}')));
      await tester.tap(find.byKey(Key('pick-items-${third.id}')));
      await tester.pump();
      expect(find.text(es.pickItemsAdd(2)), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-items-confirm')));
      await tester.pumpAndSettle();

      expect((await repository.resolveQuery(notebook.id)).ids, {
        first.id,
        second.id,
        third.id,
      });
    });

    testWidgets('renombrar cambia el título de la pantalla', (tester) async {
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Antes', mode: NotebookMode.manual);

      await pumpNotebooks(tester);
      await tester.tap(find.byKey(Key('notebook-${notebook.id}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('notebook-rename-field')),
        'Después',
      );
      await tester.tap(find.byKey(const Key('notebook-confirm-rename')));
      await tester.pumpAndSettle();

      expect(find.text('Después'), findsOneWidget);
      expect(find.text('Antes'), findsNothing);
    });
  });

  group('el detalle de un cuaderno por consulta', () {
    testWidgets('la lista es de solo lectura', (tester) async {
      await harness.capture('Coincide con la vista');
      final view = await harness.container
          .read(savedViewRepositoryProvider)
          .create(
            name: 'Todo',
            query: const LibraryQuery(),
            viewMode: LibraryViewMode.list,
          );
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(
            name: 'Por consulta',
            mode: NotebookMode.query,
            query: view.query,
          );

      await pumpNotebooks(tester);
      await tester.tap(find.byKey(Key('notebook-${notebook.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Coincide con la vista'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });
}
