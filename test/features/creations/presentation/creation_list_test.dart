import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/screens/creation_viewer_screen.dart';
import 'package:sinapsis/features/creations/presentation/widgets/scope_creations_section.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_entry_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebook_detail_screen.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import 'repasar_harness.dart';

/// «Lo creado» de Repasar (F43, paso 6): sus estados, su menú, las fuentes
/// como chips tocables (M6), el visor y la sección «En Repasar».
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;

  setUp(() async {
    harness = await RepasarHarness.create();
    await harness.processed('p-1', 'Éxodo — Comentario');
    await harness.processed('p-2', 'Génesis');
    await harness.processed('p-3', 'Levítico');
  });

  Finder tileOf(StudyCreation creation) =>
      find.byKey(ValueKey('creation-tile-${creation.id}'));

  Finder statusOf(StudyCreation creation) =>
      find.byKey(ValueKey('creation-status-${creation.id}'));

  Future<void> menu(
    WidgetTester tester,
    StudyCreation creation,
    String action,
  ) async {
    final button = find.byKey(ValueKey('creation-menu-${creation.id}'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('creation-action-$action')));
    await tester.pumpAndSettle();
  }

  List<String> actionsIn(WidgetTester tester) => [
    for (final element
        in find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'creation-action-',
                  ),
            )
            .evaluate())
      (element.widget.key! as ValueKey<String>).value.substring(
        'creation-action-'.length,
      ),
  ];

  group('los estados de cada fila', () {
    testWidgets('lista: su título, cuántas fuentes y cuándo', (tester) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        sources: ['p-1'],
        title: 'Éxodo: Liberación y Alianza',
      );
      await harness.openRepasar(tester);

      expect(find.text('Éxodo: Liberación y Alianza'), findsOneWidget);
      expect(
        tester.widget<Text>(statusOf(ready)).data,
        '${es.f43StudioSourceCount(1)} · ${es.f43StudioAgoNow}',
      );
    });

    testWidgets('en la cola, ahora o más tarde, con su brillo quieto', (
      tester,
    ) async {
      final now = await harness.creation(
        StudyCreationKind.mindMap,
        status: CreationStatus.queued,
        sources: ['p-1'],
      );
      final later = await harness.creation(
        StudyCreationKind.quiz,
        status: CreationStatus.queued,
        sources: ['p-1'],
        runNow: false,
      );
      await harness.openRepasar(tester);

      expect(tester.widget<Text>(statusOf(now)).data, es.f43StudioStatusQueued);
      expect(
        tester.widget<Text>(statusOf(later)).data,
        es.f43StudioStatusLater,
      );
      // Sin título todavía: el nombre de su tipo.
      expect(find.text(es.f43DataKindMindMap), findsWidgets);
      expect(find.byKey(const Key('creation-shimmer')), findsNWidgets(2));
    });

    testWidgets('generándose: el paso, cuánto va y la barra', (tester) async {
      final generating = await harness.creation(
        StudyCreationKind.presentation,
        status: CreationStatus.generating,
        progress: 0.4,
        step: CreationStep.readingParts,
        sources: ['p-1'],
      );
      await harness.openRepasar(tester);

      expect(
        find.descendant(
          of: statusOf(generating),
          matching: find.textContaining(es.f43DataStepReadingParts),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: statusOf(generating),
          matching: find.textContaining('40'),
        ),
        findsOneWidget,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: statusOf(generating),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.value, closeTo(0.4, 0.001));
    });

    testWidgets('fallida: por qué en una línea y «Reintentar», que la '
        'vuelve a la cola', (tester) async {
      final failed = await harness.creation(
        StudyCreationKind.dataTable,
        status: CreationStatus.failed,
        failure: CreationFailure.unreadableReply,
        sources: ['p-1'],
      );
      await harness.openRepasar(tester);

      expect(find.text(es.f43DataFailureUnreadableReply), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('creation-retry-${failed.id}')));
      await tester.pumpAndSettle();

      expect(harness.queue.calls.last.action, 'retry');
      expect(harness.queue.calls.last.id, failed.id);
      expect(
        tester.widget<Text>(statusOf(failed)).data,
        es.f43StudioStatusQueued,
      );
    });
  });

  group('el menú ⋮', () {
    testWidgets('ofrece lo que tiene sentido en cada estado', (tester) async {
      final ready = await harness.creation(StudyCreationKind.quiz);
      final queued = await harness.creation(
        StudyCreationKind.report,
        status: CreationStatus.queued,
      );
      final failed = await harness.creation(
        StudyCreationKind.mindMap,
        status: CreationStatus.failed,
      );
      await harness.openRepasar(tester);

      Future<List<String>> open(StudyCreation c) async {
        final button = find.byKey(ValueKey('creation-menu-${c.id}'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        final shown = actionsIn(tester);
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        return shown;
      }

      expect(await open(ready), [
        'open',
        'rename',
        'regenerate',
        'sources',
        'trash',
      ]);
      expect(await open(queued), ['cancel', 'rename', 'sources', 'trash']);
      expect(await open(failed), [
        'retry',
        'rename',
        'regenerate',
        'sources',
        'trash',
      ]);
    });

    testWidgets('renombrar le cambia el título', (tester) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        title: 'Un informe',
      );
      await harness.openRepasar(tester);

      await menu(tester, ready, 'rename');
      await tester.enterText(
        find.byKey(const Key('creation-rename-field')),
        'Análisis exegético del Éxodo',
      );
      await tester.tap(find.byKey(const Key('creation-rename-save')));
      await tester.pumpAndSettle();

      expect(find.text('Análisis exegético del Éxodo'), findsOneWidget);
      expect(find.text('Un informe'), findsNothing);
    });

    testWidgets('borrar la manda a la papelera, y «Deshacer» la trae', (
      tester,
    ) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        title: 'Un informe',
      );
      await harness.openRepasar(tester);

      await menu(tester, ready, 'trash');

      expect(harness.queue.calls.last.action, 'trash');
      expect(tileOf(ready), findsNothing);
      expect(find.text(es.f43StudioTrashed), findsOneWidget);

      await tester.tap(find.text(es.f43StudioUndo));
      await tester.pumpAndSettle();
      expect(tileOf(ready), findsOneWidget);
    });

    testWidgets('cancelar una pendiente la deja cancelada, con «Reintentar»', (
      tester,
    ) async {
      final queued = await harness.creation(
        StudyCreationKind.presentation,
        status: CreationStatus.queued,
      );
      await harness.openRepasar(tester);

      await menu(tester, queued, 'cancel');

      expect(harness.queue.calls.last.action, 'cancel');
      expect(find.text(es.f43DataFailureCancelled), findsOneWidget);
      expect(
        find.byKey(ValueKey('creation-retry-${queued.id}')),
        findsOneWidget,
      );
    });

    testWidgets('«Exportar o compartir» solo si su tipo sabe', (tester) async {
      final exported = <String>[];
      harness = await RepasarHarness.create(
        specs: [
          defaultCreationKindSpec(StudyCreationKind.quiz).copyWith(
            onExport: (context, ref, creation) async =>
                exported.add(creation.id),
          ),
        ],
      );
      final quiz = await harness.creation(StudyCreationKind.quiz);
      await harness.openRepasar(tester);

      await menu(tester, quiz, 'export');

      expect(exported, [quiz.id]);
    });
  });

  group('las fuentes como chips (M6)', () {
    testWidgets('un documento abre su pantalla de procesado', (tester) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        sources: ['p-2'],
      );
      await harness.openRepasar(tester);

      final chip = find.descendant(
        of: tileOf(ready),
        matching: find.byKey(const ValueKey('creation-source-p-2')),
      );
      expect(
        find.descendant(of: chip, matching: find.text('Génesis')),
        findsOneWidget,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
    });

    testWidgets('una fuente que ya no existe dice «Fuente borrada» y no abre '
        'nada', (tester) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        sources: ['ya-no-esta'],
      );
      await harness.openRepasar(tester);

      final chip = find.descendant(
        of: tileOf(ready),
        matching: find.byKey(const ValueKey('creation-source-ya-no-esta')),
      );
      expect(
        find.descendant(
          of: chip,
          matching: find.text(es.f43StudioSourceDeleted),
        ),
        findsOneWidget,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(ProcessedDocumentScreen), findsNothing);
    });

    testWidgets('el cuaderno sobre el que se creó abre el cuaderno', (
      tester,
    ) async {
      final notebooks = harness.container.read(notebookRepositoryProvider);
      final notebook = await notebooks.create(
        name: 'Pentateuco',
        mode: NotebookMode.manual,
      );
      await notebooks.addItems(notebookId: notebook.id, itemIds: ['p-1']);
      final scope = CreationScope.notebook(notebook.id);
      final ready = await harness.creation(
        StudyCreationKind.mindMap,
        scope: scope,
        sources: ['p-1'],
      );
      await harness.openRepasar(tester);

      final chip = find.descendant(
        of: tileOf(ready),
        matching: find.byKey(
          ValueKey('creation-scope-chip-${scope.storageKey}'),
        ),
      );
      expect(
        find.descendant(of: chip, matching: find.text('Pentateuco')),
        findsOneWidget,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.byType(NotebookDetailScreen), findsOneWidget);
    });

    testWidgets('el tema abre su material, como desde el Atlas', (
      tester,
    ) async {
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace('Ley'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .setSpaces(itemIds: ['p-1'], spaceIds: {space.id});
      final scope = CreationScope.space(space.id);
      final ready = await harness.creation(
        StudyCreationKind.mindMap,
        scope: scope,
        sources: ['p-1'],
      );
      await harness.openRepasar(tester);

      await tester.tap(
        find.descendant(
          of: tileOf(ready),
          matching: find.byKey(
            ValueKey('creation-scope-chip-${scope.storageKey}'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExplorerScreen), findsOneWidget);
    });

    testWidgets('las que no entran van en «+N», que abre la lista entera', (
      tester,
    ) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        sources: ['p-1', 'p-2', 'p-3'],
      );
      await harness.openRepasar(tester);

      expect(
        find.descendant(
          of: tileOf(ready),
          matching: find.byKey(const ValueKey('creation-source-p-3')),
        ),
        findsNothing,
      );
      await tester.tap(
        find.byKey(ValueKey('creation-sources-more-${ready.id}')),
      );
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('creation-sources-sheet'));
      for (final title in ['Éxodo — Comentario', 'Génesis', 'Levítico']) {
        expect(
          find.descendant(of: sheet, matching: find.text(title)),
          findsOneWidget,
        );
      }
    });
  });

  group('el visor', () {
    testWidgets('un tipo sin visor todavía dice «en camino», con la barra '
        'común y sus fuentes', (tester) async {
      final ready = await harness.creation(
        StudyCreationKind.infographic,
        sources: ['p-1', 'p-2'],
        title: 'Éxodo en una lámina',
      );
      await harness.openRepasar(tester);

      await tester.tapAt(
        tester.getTopLeft(tileOf(ready)) + const Offset(80, 20),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CreationViewerScreen), findsOneWidget);
      expect(find.byKey(const Key('creation-viewer-coming')), findsOneWidget);
      expect(
        find.text(es.f43StudioViewerComingHint(es.f43DataKindInfographic)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('creation-viewer-title')))
            .data,
        'Éxodo en una lámina',
      );
      expect(find.text(es.f43StudioViewSources(2)), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('creation-source-p-2')).last);
      await tester.pumpAndSettle();
      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
    });

    testWidgets('un tipo con su visor registrado lo muestra, con sus '
        'botones en la barra', (tester) async {
      harness = await RepasarHarness.create(
        specs: [
          defaultCreationKindSpec(StudyCreationKind.mindMap).copyWith(
            viewerBuilder: (context, creation) =>
                Text('Árbol de ${creation.id}', key: const Key('mi-visor')),
            viewerActions: (context, creation) => [
              IconButton(
                key: const Key('mi-accion'),
                onPressed: () {},
                icon: const Icon(Icons.fullscreen),
              ),
            ],
          ),
        ],
      );
      await harness.processed('p-1', 'Éxodo');
      final ready = await harness.creation(
        StudyCreationKind.mindMap,
        sources: ['p-1'],
      );
      await harness.openRepasar(tester);

      await tester.tapAt(
        tester.getTopLeft(tileOf(ready)) + const Offset(80, 20),
      );
      await tester.pumpAndSettle();

      expect(find.text('Árbol de ${ready.id}'), findsOneWidget);
      expect(find.byKey(const Key('mi-accion')), findsOneWidget);
      expect(find.byKey(const Key('creation-viewer-coming')), findsNothing);
    });

    testWidgets('una que se genera no se abre desde la lista; por dirección '
        'dice en qué va', (tester) async {
      final generating = await harness.creation(
        StudyCreationKind.report,
        status: CreationStatus.generating,
        progress: 0.5,
      );
      await harness.openRepasar(tester);

      await tester.tapAt(
        tester.getTopLeft(tileOf(generating)) + const Offset(80, 20),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CreationViewerScreen), findsNothing);

      harness.library.pushTo('/creations/${generating.id}');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('creation-viewer-pending')), findsOneWidget);
    });

    testWidgets('una que no existe lo dice', (tester) async {
      await harness.openRepasar(tester);

      harness.library.pushTo('/creations/no-existe');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('creation-viewer-missing')), findsOneWidget);
    });
  });

  group('«En Repasar» (M6), para un documento o un cuaderno', () {
    Widget host() {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  ScopeCreationsSection(scope: CreationScope.document('p-1')),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/review',
            builder: (context, state) => ReviewEntryScreen(
              requestedScopeKey: state.uri.queryParameters['scope'],
            ),
          ),
          GoRoute(
            path: '/creations/:id',
            builder: (context, state) =>
                CreationViewerScreen(creationId: state.pathParameters['id']!),
          ),
        ],
      );
      return UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    Future<void> pumpHost(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(420, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
    }

    testWidgets('lo creado sobre él y lo que lo usó como fuente', (
      tester,
    ) async {
      final own = await harness.creation(
        StudyCreationKind.presentation,
        scope: const CreationScope.document('p-1'),
        sources: ['p-1'],
        title: 'Sobre el Éxodo',
      );
      final notebooks = harness.container.read(notebookRepositoryProvider);
      final notebook = await notebooks.create(
        name: 'Pentateuco',
        mode: NotebookMode.manual,
      );
      final viaNotebook = await harness.creation(
        StudyCreationKind.quiz,
        scope: CreationScope.notebook(notebook.id),
        sources: ['p-1', 'p-2'],
        title: 'Del cuaderno',
      );
      final other = await harness.creation(
        StudyCreationKind.quiz,
        scope: const CreationScope.document('p-2'),
        sources: ['p-2'],
        title: 'De otro',
      );
      await pumpHost(tester);

      expect(tileOf(own), findsOneWidget);
      expect(tileOf(viaNotebook), findsOneWidget);
      expect(tileOf(other), findsNothing);

      await tester.tapAt(tester.getTopLeft(tileOf(own)) + const Offset(80, 20));
      await tester.pumpAndSettle();
      expect(find.byType(CreationViewerScreen), findsOneWidget);
    });

    testWidgets('sin nada creado lo dice; «Crear en Repasar» abre Repasar con '
        'el documento elegido', (tester) async {
      await pumpHost(tester);

      expect(find.text(es.f43StudioInRepasarEmpty), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('scope-creations-create-document:p-1')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      expect(harness.scope, const CreationScope.document('p-1'));
      expect(
        tester.widget<Text>(find.byKey(const Key('repasar-scope-name'))).data,
        'Éxodo — Comentario',
      );
      expect(
        harness.container.read(recentCreationScopesProvider).first,
        const CreationScope.document('p-1'),
      );
    });
  });
}
