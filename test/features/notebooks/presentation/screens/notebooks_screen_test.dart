import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebook_detail_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebooks_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
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

      await tester.tap(find.text(es.notebooksCreateAction).first);
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

      await tester.tap(find.text(es.notebooksCreateAction).first);
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
