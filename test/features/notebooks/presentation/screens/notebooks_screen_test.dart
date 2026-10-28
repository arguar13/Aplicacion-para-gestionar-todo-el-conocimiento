import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_suggestions_controller.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebook_detail_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebooks_screen.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';

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
      GoRoute(
        path: RoutePaths.inbox,
        builder: (_, _) => const Scaffold(body: Text('la Bandeja')),
      ),
      GoRoute(
        path: RoutePaths.processed,
        builder: (_, _) => const Scaffold(body: Text('Procesado')),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                Scaffold(body: Text('procesado ${state.pathParameters['id']}')),
          ),
        ],
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
      // Lo que propone son documentos procesados (F41, paso 5).
      final db = harness.database;
      await insertProcessedRows(db, id: 'foro', title: 'El foro romano');
      await insertProcessedRows(db, id: 'senado', title: 'El Senado');
      const foro = (id: 'foro', title: 'El foro romano');
      const senado = (id: 'senado', title: 'El Senado');
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

    /// Un tema con [count] documentos procesados (F41, paso 5) —y, para que
    /// se vea que no cuentan, tantas fuentes de la Biblioteca como haga
    /// falta para sugerirlo—.
    Future<String> seedTopic(int count, {String name = 'Roma'}) async {
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace(name))
              .getRight()
              .toNullable()!;
      final ids = <String>[];
      for (var i = 0; i < count; i++) {
        await insertProcessedRows(
          harness.database,
          id: '$name-$i',
          title: '$name $i',
        );
        ids.add('$name-$i');
      }
      for (var i = 0; i < 3; i++) {
        await harness.capture('Fuente de $name $i');
      }
      ids.addAll(
        (await harness.container
                .read(libraryRepositoryProvider)
                .matchingIds(const LibraryQuery()))
            .getRight()
            .toNullable()!,
      );
      await harness.container
          .read(libraryRepositoryProvider)
          .setSpaces(itemIds: ids, spaceIds: {space.id});
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
    Future<void> openNotebook(WidgetTester tester, String notebookId) async {
      await pumpNotebooks(tester);
      await tester.tap(find.byKey(Key('notebook-$notebookId')));
      await tester.pumpAndSettle();
    }

    testWidgets('vacío, explica que se llena con documentos procesados y '
        'lleva a Procesado o a la Bandeja (F41, paso 5)', (tester) async {
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'A mano', mode: NotebookMode.manual);

      await openNotebook(tester, notebook.id);

      expect(find.byKey(const Key('notebook-detail-empty')), findsOneWidget);
      expect(find.text(es.notebookDetailEmptyTitle), findsOneWidget);
      expect(find.text(es.notebookDetailEmptyManual), findsOneWidget);
      await tester.tap(find.byKey(const Key('notebook-empty-inbox')));
      await tester.pumpAndSettle();
      expect(find.text('la Bandeja'), findsOneWidget);

      await openNotebook(tester, notebook.id);
      await tester.tap(find.text(es.notebookDetailGoToProcessed));
      await tester.pumpAndSettle();
      expect(find.text('Procesado'), findsOneWidget);
    });

    testWidgets('agregar y sacar un procesado cambia el panel, no la bóveda; '
        'las fuentes de la Biblioteca no se ofrecen', (tester) async {
      await insertProcessedRows(
        harness.database,
        id: 'articulo',
        title: 'Un artículo procesado',
      );
      await harness.capture('Una fuente de la Biblioteca');
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'A mano', mode: NotebookMode.manual);

      await openNotebook(tester, notebook.id);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text(es.notebookPickProcessedTitle), findsOneWidget);
      expect(find.text('Una fuente de la Biblioteca'), findsNothing);
      await tester.tap(find.text('Un artículo procesado'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-processed-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Un artículo procesado'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notebook-remove-articulo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notebook-detail-empty')), findsOneWidget);
      // Sigue en Procesado: sacarlo del cuaderno no lo borró.
      final rows = await harness.database
          .select(harness.database.processedDocuments)
          .get();
      expect(rows.map((r) => r.itemId), ['articulo']);
    });

    testWidgets('cada procesado se ve con el ícono de su fuente y los chips de '
        'sus partes, y tocarlo lo abre', (tester) async {
      await insertProcessedRows(
        harness.database,
        id: 'libro',
        title: 'Un libro procesado',
        parts: {
          ProcessedSection.text: ['El texto.'],
          ProcessedSection.summary: ['Lo principal.'],
          ProcessedSection.fragments: ['Un pasaje.'],
        },
      );
      final repository = harness.container.read(notebookRepositoryProvider);
      final notebook = await repository.create(
        name: 'A mano',
        mode: NotebookMode.manual,
      );
      await repository.addItem(notebookId: notebook.id, itemId: 'libro');

      await openNotebook(tester, notebook.id);

      final row = find.byKey(const Key('notebook-item-libro'));
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(SourceKind.document.icon),
        ),
        findsOneWidget,
      );
      for (final section in [
        ProcessedSection.text,
        ProcessedSection.summary,
        ProcessedSection.fragments,
      ]) {
        expect(
          find.byKey(Key('processed-part-libro-${section.name}')),
          findsOneWidget,
        );
      }
      expect(find.byKey(const Key('processed-part-libro-notes')), findsNothing);
      expect(find.text(es.processedSectionSummary), findsOneWidget);
      // El lector de pantalla oye todo junto, en una frase.
      expect(
        find.bySemanticsLabel(
          es.notebookMemberSemantics(
            'Un libro procesado',
            es.sourceKindDocument,
            [
              es.processedSectionText,
              es.processedSectionSummary,
              es.processedSectionFragments,
            ].join(', '),
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Un libro procesado'));
      await tester.pumpAndSettle();
      expect(find.text('procesado libro'), findsOneWidget);
    });

    testWidgets('se agregan varios a la vez, y los que ya están se ven '
        'marcados sin poder tocarlos (F30)', (tester) async {
      final db = harness.database;
      await insertProcessedRows(db, id: 'roma', title: 'Roma antigua');
      await insertProcessedRows(db, id: 'senado', title: 'El Senado');
      await insertProcessedRows(
        db,
        id: 'punicas',
        title: 'Las guerras púnicas',
      );
      final repository = harness.container.read(notebookRepositoryProvider);
      final notebook = await repository.create(
        name: 'Roma',
        mode: NotebookMode.manual,
      );
      await repository.addItem(notebookId: notebook.id, itemId: 'roma');

      await openNotebook(tester, notebook.id);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final already = tester.widget<CheckboxListTile>(
        find.byKey(const Key('pick-processed-roma')),
      );
      expect(already.value, isTrue);
      expect(already.onChanged, isNull);
      expect(find.text(es.pickItemsAlreadyIn), findsOneWidget);

      await tester.tap(find.byKey(const Key('pick-processed-senado')));
      await tester.tap(find.byKey(const Key('pick-processed-punicas')));
      await tester.pump();
      // Destildar uno lo saca de lo elegido.
      await tester.tap(find.byKey(const Key('pick-processed-punicas')));
      await tester.pump();
      expect(find.text(es.pickItemsAdd(1)), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-processed-punicas')));
      await tester.pump();
      expect(find.text(es.pickItemsAdd(2)), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-processed-confirm')));
      await tester.pumpAndSettle();

      expect((await repository.resolveQuery(notebook.id)).ids, {
        'roma',
        'senado',
        'punicas',
      });
    });

    testWidgets('el selector busca en Procesado y dice cuando no hay nada', (
      tester,
    ) async {
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Roma', mode: NotebookMode.manual);

      await openNotebook(tester, notebook.id);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text(es.notebookPickProcessedNone), findsOneWidget);

      await insertProcessedRows(
        harness.database,
        id: 'senado',
        title: 'El Senado',
        parts: {
          ProcessedSection.notes: ['Trescientos miembros.'],
        },
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pick-processed-search')),
        'trescientos',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pick-processed-senado')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('pick-processed-search')),
        'cartago',
      );
      await tester.pumpAndSettle();
      expect(
        find.text(es.notebookPickProcessedNoMatches('cartago')),
        findsOneWidget,
      );
    });

    testWidgets('renombrar cambia el título de la pantalla', (tester) async {
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Antes', mode: NotebookMode.manual);

      await openNotebook(tester, notebook.id);

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

  group('el aviso del cuaderno vaciado (F41, v46)', () {
    Future<String> emptiedNotebook(NotebookMode mode) async {
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(
            name: 'De antes',
            mode: mode,
            query: mode == NotebookMode.query ? const LibraryQuery() : null,
          );
      final db = harness.database;
      await (db.update(
        db.notebooks,
      )..where((n) => n.id.equals(notebook.id))).write(
        NotebooksCompanion(
          emptiedForProcessedAt: Value(DateTime(2026, 10, 28)),
        ),
      );
      return notebook.id;
    }

    Future<void> open(WidgetTester tester, String notebookId) async {
      await pumpNotebooks(tester);
      await tester.tap(find.byKey(Key('notebook-$notebookId')));
      await tester.pumpAndSettle();
    }

    testWidgets('explica por qué quedó vacío y cómo volver a llenarlo; '
        '«Entendido» lo saca y no vuelve', (tester) async {
      final id = await emptiedNotebook(NotebookMode.manual);

      await open(tester, id);

      expect(find.byKey(const Key('notebook-emptied-notice')), findsOneWidget);
      expect(find.text(es.notebookEmptiedTitle), findsOneWidget);
      expect(find.text(es.notebookEmptiedManual), findsOneWidget);
      // Junto con el vacío de siempre, que lleva a llenarlo.
      expect(find.byKey(const Key('notebook-detail-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('notebook-emptied-dismiss')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notebook-emptied-notice')), findsNothing);
      final row = await (harness.database.select(
        harness.database.notebooks,
      )..where((n) => n.id.equals(id))).getSingle();
      expect(row.emptiedForProcessedAt, isNull);

      // Al volver a abrirlo, sigue sin aviso.
      await open(tester, id);
      expect(find.byKey(const Key('notebook-emptied-notice')), findsNothing);
    });

    testWidgets('en uno por consulta dice que su vista ya no mira la '
        'Biblioteca, y lleva a la Bandeja', (tester) async {
      final id = await emptiedNotebook(NotebookMode.query);

      await open(tester, id);

      expect(find.text(es.notebookEmptiedQuery), findsOneWidget);
      expect(find.text(es.notebookEmptiedManual), findsNothing);
      await tester.tap(find.byKey(const Key('notebook-emptied-inbox')));
      await tester.pumpAndSettle();
      expect(find.text('la Bandeja'), findsOneWidget);
    });

    testWidgets('un cuaderno sin la marca no lo muestra', (tester) async {
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Nuevo', mode: NotebookMode.manual);

      await open(tester, notebook.id);

      expect(find.byKey(const Key('notebook-emptied-notice')), findsNothing);
    });
  });

  group('el detalle de un cuaderno por consulta', () {
    Future<String> queryNotebook() async {
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
      return notebook.id;
    }

    testWidgets('la lista es de solo lectura, y solo con procesados', (
      tester,
    ) async {
      await insertProcessedRows(
        harness.database,
        id: 'coincide',
        title: 'Coincide con la vista',
      );
      await harness.capture('Una fuente de la Biblioteca');
      final notebookId = await queryNotebook();

      await pumpNotebooks(tester);
      await tester.tap(find.byKey(Key('notebook-$notebookId')));
      await tester.pumpAndSettle();

      expect(find.text('Coincide con la vista'), findsOneWidget);
      expect(find.text('Una fuente de la Biblioteca'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('vacío, dice que se llena solo con lo procesado que cumple su '
        'vista', (tester) async {
      await harness.capture('Una fuente de la Biblioteca');
      final notebookId = await queryNotebook();

      await pumpNotebooks(tester);
      await tester.tap(find.byKey(Key('notebook-$notebookId')));
      await tester.pumpAndSettle();

      expect(find.text(es.notebookDetailEmptyQuery), findsOneWidget);
      expect(find.byKey(const Key('notebook-empty-inbox')), findsOneWidget);
    });

    testWidgets('al crearlo, se avisa que la vista se mira sobre Procesado', (
      tester,
    ) async {
      await harness.container
          .read(savedViewRepositoryProvider)
          .create(
            name: 'Todo',
            query: const LibraryQuery(),
            viewMode: LibraryViewMode.list,
          );

      await pumpNotebooks(tester);
      await tester.tap(find.byKey(const Key('notebook-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notebook-new-manual')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.notebooksModeQuery));
      await tester.pumpAndSettle();

      expect(find.text(es.notebooksQueryProcessedHint), findsOneWidget);
    });
  });
}
