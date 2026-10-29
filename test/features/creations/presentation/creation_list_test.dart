import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
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

  /// Mantiene apretada la fila de [creation] y toca [action] en su menú.
  Future<void> menu(
    WidgetTester tester,
    StudyCreation creation,
    String action,
  ) async {
    await tester.ensureVisible(tileOf(creation));
    await tester.pumpAndSettle();
    await tester.longPress(tileOf(creation));
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

  /// Desliza la fila de [creation] [dx] píxeles.
  Future<void> swipe(
    WidgetTester tester,
    StudyCreation creation,
    double dx,
  ) async {
    await tester.drag(tileOf(creation), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  Finder swipeButton(String action, StudyCreation creation) =>
      find.byKey(ValueKey('creation-swipe-$action-${creation.id}'));

  /// Un tipo que arma su archivo, para «Compartir» y «Descargar».
  CreationKindSpec exporting(StudyCreationKind kind) =>
      defaultCreationKindSpec(kind).copyWith(
        exporter: (context, ref, creation) async => CreationExportFile(
          fileName: '${creation.title}.pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'application/pdf',
        ),
      );

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

  group('mantener apretada una fila: su menú flotante', () {
    testWidgets('ofrece lo que tiene sentido en cada estado, en el orden de '
        'NotebookLM', (tester) async {
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
        await tester.ensureVisible(tileOf(c));
        await tester.pumpAndSettle();
        await tester.longPress(tileOf(c));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('creation-actions-menu-${c.id}')),
          findsOneWidget,
        );
        final shown = actionsIn(tester);
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        return shown;
      }

      // Sin archivo de su tipo, ni Compartir ni Descargar: nunca un botón
      // que no hace nada.
      expect(await open(ready), [
        'open',
        'rename',
        'details',
        'regenerate',
        'trash',
      ]);
      expect(await open(queued), ['rename', 'details', 'cancel', 'trash']);
      expect(await open(failed), [
        'rename',
        'details',
        'retry',
        'regenerate',
        'trash',
      ]);
    });

    testWidgets('«Cambiar nombre» le cambia el título', (tester) async {
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

    testWidgets('«Eliminar» la manda a la papelera, y «Deshacer» la trae', (
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

    testWidgets('«Descargar» guarda el archivo que arma su tipo', (
      tester,
    ) async {
      harness = await RepasarHarness.create(
        specs: [exporting(StudyCreationKind.quiz)],
      );
      final quiz = await harness.creation(
        StudyCreationKind.quiz,
        title: 'Éxodo Cuestionario',
      );
      await harness.openRepasar(tester);

      await tester.longPress(tileOf(quiz));
      await tester.pumpAndSettle();
      // Sin cómo compartir en esta app, «Compartir» no se ofrece.
      expect(actionsIn(tester), [
        'open',
        'download',
        'rename',
        'details',
        'regenerate',
        'trash',
      ]);
      await tester.tap(find.byKey(const ValueKey('creation-action-download')));
      await tester.pumpAndSettle();

      expect(harness.library.fileSaver.savedFileName, 'Éxodo Cuestionario.pdf');
      expect(harness.library.fileSaver.savedBytes, [1, 2, 3]);
      expect(
        find.text(es.f43StudioDownloaded('Éxodo Cuestionario.pdf')),
        findsOneWidget,
      );
    });

    testWidgets('«Compartir» solo si la app tiene cómo, y le pasa el archivo', (
      tester,
    ) async {
      final shared = <(String, String)>[];
      harness = await RepasarHarness.create(
        specs: [exporting(StudyCreationKind.quiz)],
        sharer: (file, {required title}) async =>
            shared.add((file.fileName, title)),
      );
      final quiz = await harness.creation(
        StudyCreationKind.quiz,
        title: 'Éxodo Cuestionario',
      );
      await harness.openRepasar(tester);

      await menu(tester, quiz, 'share');

      expect(shared, [('Éxodo Cuestionario.pdf', 'Éxodo Cuestionario')]);
    });

    testWidgets('el lector de pantalla tiene las mismas acciones', (
      tester,
    ) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        title: 'Un informe',
      );
      await harness.openRepasar(tester);

      final semantics = tester.widget<Semantics>(
        find.ancestor(
          of: tileOf(ready),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics && w.properties.customSemanticsActions != null,
          ),
        ),
      );
      final actions = semantics.properties.customSemanticsActions!;
      expect(actions.keys.map((a) => a.label), [
        es.f43StudioMenuRename,
        es.f43StudioMenuDetails,
        es.f43StudioMenuRegenerate,
        es.f43StudioMenuTrash,
      ]);
      actions[CustomSemanticsAction(label: es.f43StudioMenuTrash)]!();
      await tester.pumpAndSettle();
      expect(tileOf(ready), findsNothing);
    });
  });

  group('deslizar una fila a la izquierda', () {
    testWidgets('muestra Eliminar al ras de la derecha; tocarlo la manda a la '
        'papelera', (tester) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        title: 'La Topografía de lo Invisible',
      );
      await harness.openRepasar(tester);
      expect(swipeButton('trash', ready), findsNothing);

      await swipe(tester, ready, -400);

      expect(swipeButton('trash', ready), findsOneWidget);
      // Sin archivo de su tipo, no hay Descargar.
      expect(swipeButton('download', ready), findsNothing);
      final row = tester.getRect(tileOf(ready));
      final button = tester.getRect(swipeButton('trash', ready));
      expect(
        button.right,
        closeTo(tester.getSize(find.byType(Scaffold).first).width, 1),
      );
      expect(row.right, lessThanOrEqualTo(button.left + 1));

      await tester.tap(swipeButton('trash', ready));
      await tester.pumpAndSettle();
      expect(harness.queue.calls.last.action, 'trash');
      expect(tileOf(ready), findsNothing);
    });

    testWidgets('con archivo, Descargar al lado de Eliminar', (tester) async {
      harness = await RepasarHarness.create(
        specs: [exporting(StudyCreationKind.infographic)],
      );
      final ready = await harness.creation(
        StudyCreationKind.infographic,
        title: 'Lámina',
      );
      await harness.openRepasar(tester);

      await swipe(tester, ready, -400);
      expect(
        tester.getCenter(swipeButton('download', ready)).dx,
        lessThan(tester.getCenter(swipeButton('trash', ready)).dx),
      );
      await tester.tap(swipeButton('download', ready));
      await tester.pumpAndSettle();

      expect(harness.library.fileSaver.savedFileName, 'Lámina.pdf');
      // Hacer algo la cierra.
      expect(swipeButton('download', ready), findsNothing);
    });

    testWidgets('un poco no alcanza: vuelve a cerrarse sola', (tester) async {
      final ready = await harness.creation(StudyCreationKind.report);
      await harness.openRepasar(tester);

      // Despacio —sin envión— y menos de la mitad de los botones.
      final gesture = await tester.startGesture(
        tester.getCenter(tileOf(ready)),
      );
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getTopLeft(tileOf(ready)).dx, lessThan(0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(swipeButton('trash', ready), findsNothing);
      expect(tester.getTopLeft(tileOf(ready)).dx, 0);
    });

    testWidgets('una sola abierta a la vez; tocar la abierta la cierra', (
      tester,
    ) async {
      final first = await harness.creation(
        StudyCreationKind.report,
        title: 'Primera',
      );
      final second = await harness.creation(
        StudyCreationKind.quiz,
        title: 'Segunda',
      );
      await harness.openRepasar(tester);

      await swipe(tester, first, -400);
      expect(swipeButton('trash', first), findsOneWidget);
      await swipe(tester, second, -400);
      expect(swipeButton('trash', second), findsOneWidget);
      expect(swipeButton('trash', first), findsNothing);

      // Lo que se ve de la fila corrida: su borde izquierdo.
      await tester.tapAt(Offset(24, tester.getCenter(tileOf(second)).dy));
      await tester.pumpAndSettle();
      expect(swipeButton('trash', second), findsNothing);
      // Cerrar no es abrir: sigue en Repasar.
      expect(find.byType(CreationViewerScreen), findsNothing);
    });

    testWidgets('con la letra al doble en 360 dp, los botones entran y nada '
        'se desborda', (tester) async {
      harness = await RepasarHarness.create(
        specs: [exporting(StudyCreationKind.report)],
      );
      final ready = await harness.creation(
        StudyCreationKind.report,
        title: 'Resumen Teológico y Sintético: Éxodo, el Señor de la Historia',
      );
      await harness.openRepasar(
        tester,
        size: const Size(360, 1600),
        textScale: 2,
      );
      await tester.scrollUntilVisible(
        tileOf(ready),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('review-entry')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      await swipe(tester, ready, -500);

      expect(swipeButton('download', ready), findsOneWidget);
      expect(swipeButton('trash', ready), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('«Ver petición y fuentes»', () {
    testWidgets('lo pedido con los nombres de la hoja, el idioma, el modelo '
        'y las fuentes', (tester) async {
      final ready = await harness.creation(
        StudyCreationKind.presentation,
        sources: ['p-1', 'ya-no-esta'],
        title: 'Éxodo en diapositivas',
        options: const {
          CreationOptionValues.length: CreationOptionValues.short,
          CreationOptionValues.illustrations: true,
          CreationOptionKeys.description: 'Para chicos',
        },
      );
      await harness.openRepasar(tester);

      await menu(tester, ready, 'details');

      final sheet = find.byKey(const Key('creation-details-sheet'));
      expect(sheet, findsOneWidget);
      for (final text in [
        es.f43StudioOptDuration,
        es.f43StudioOptShort,
        es.f43StudioOptIllustrations,
        es.f43StudioYes,
        'Para chicos',
        'Español',
      ]) {
        expect(
          find.descendant(of: sheet, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(
        find.descendant(
          of: sheet,
          matching: find.byKey(const ValueKey('creation-source-ya-no-esta')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(es.f43StudioSourceDeleted),
        ),
        findsOneWidget,
      );
    });
  });

  group('las fuentes como chips (M6)', () {
    Future<Finder> detailsOf(WidgetTester tester, StudyCreation c) async {
      await menu(tester, c, 'details');
      return find.byKey(const Key('creation-details-sheet'));
    }

    testWidgets('un documento abre su pantalla de procesado', (tester) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        sources: ['p-2'],
      );
      await harness.openRepasar(tester);
      final sheet = await detailsOf(tester, ready);

      final chip = find.descendant(
        of: sheet,
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
      final sheet = await detailsOf(tester, ready);

      final chip = find.descendant(
        of: sheet,
        matching: find.byKey(const ValueKey('creation-source-ya-no-esta')),
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
      final sheet = await detailsOf(tester, ready);

      final chip = find.descendant(
        of: sheet,
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
      final sheet = await detailsOf(tester, ready);

      await tester.tap(
        find.descendant(
          of: sheet,
          matching: find.byKey(
            ValueKey('creation-scope-chip-${scope.storageKey}'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExplorerScreen), findsOneWidget);
    });

    testWidgets('en el visor, las que no entran van en «+N», que abre la '
        'lista entera', (tester) async {
      final ready = await harness.creation(
        StudyCreationKind.report,
        sources: ['p-1', 'p-2', 'p-3', 'ya-no-esta'],
      );
      await harness.openRepasar(tester);
      harness.library.pushTo('/creations/${ready.id}');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('creation-source-ya-no-esta')),
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
