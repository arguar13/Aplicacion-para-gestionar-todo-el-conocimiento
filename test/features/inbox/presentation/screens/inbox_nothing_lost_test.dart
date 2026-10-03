import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_intro_card.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_queue_sheet.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pick_living_note_dialog.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/swipe_card.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/links/presentation/providers/link_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';


import '../../../../support/library_harness.dart';

/// La Bandeja no se traga nada (F28): las acciones que se cancelan no
/// deciden, cada decisión se avisa con «Ver» y «Deshacer», se deshace de a
/// muchos pasos aunque se salga de la pantalla, «N pendientes» abre la cola,
/// y la primera vez una tarjeta explica qué es triar.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  /// Una fuente lista para triar. Las más nuevas, más abajo en la fila.
  Future<String> seedSource({String? title, SourceKind? kind}) async {
    final n = counter++;
    final now = DateTime(2026, 9, 18, 10).add(Duration(minutes: n));
    final id = 'item-${n.toString().padLeft(3, '0')}';
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: title ?? 'Fuente $n',
            source: Source(
              id: 'src-$n',
              kind: kind ?? SourceKind.webPage,
              capturedAt: now,
              url: 'https://ejemplo.org/$n',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<String> seedLivingNote(String title) async =>
      (await harness.container
              .read(linkRepositoryProvider)
              .createNoteForLink(title: title))
          .getRight()
          .toNullable()!
          .id;

  /// Las notas vivas, leídas directo de la base: un `watch…().first` no
  /// emite bajo el reloj simulado de una prueba de pantalla.
  Future<List<KnowledgeEntryRow>> livingNotes() async {
    final db = harness.database;
    final rows = await (db.select(db.knowledgeEntries).join([
      innerJoin(
        db.knowledgeNotes,
        db.knowledgeNotes.itemId.equalsExp(db.knowledgeEntries.id),
      ),
    ])..where(db.knowledgeNotes.noteKind.equalsValue(NoteKind.living))).get();
    return [for (final row in rows) row.readTable(db.knowledgeEntries)];
  }

  Future<ItemState> stateOf(String id) async {
    final row = await (harness.database.select(
      harness.database.knowledgeEntries,
    )..where((e) => e.id.equals(id))).getSingle();
    return row.state;
  }

  /// Los vínculos `cites` que llegan a [sourceId], como (de dónde, a dónde).
  Future<List<(String, String)>> citationsOf(String sourceId) async {
    final rows =
        await (harness.database.select(harness.database.relations)..where(
              (r) =>
                  r.toItemId.equals(sourceId) &
                  r.kind.equalsValue(RelationKind.cites),
            ))
            .get();
    return [for (final row in rows) (row.fromItemId, row.toItemId)];
  }

  Future<void> pumpInbox(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const InboxScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> swipe(WidgetTester tester, Offset offset) async {
    await tester.drag(find.byType(SwipeCard), offset);
    await tester.pumpAndSettle();
  }

  Future<void> undo(WidgetTester tester) async {
    await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
    await tester.pumpAndSettle();
  }

  bool canUndo(WidgetTester tester) =>
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
          .onPressed !=
      null;

  Future<void> openLinkPicker(WidgetTester tester) async {
    await tester.tap(find.text(es.inboxActionLink));
    await tester.pumpAndSettle();
  }

  group('vincular a una nota viva', () {
    testWidgets('cancelar el selector deja la fuente en la Bandeja', (
      tester,
    ) async {
      final id = await seedSource(title: 'Sin decidir');
      await seedLivingNote('Roma antigua');
      await pumpInbox(tester);

      await openLinkPicker(tester);
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await stateOf(id), ItemState.processed);
      expect(find.text('Sin decidir'), findsOneWidget);
      expect(canUndo(tester), isFalse);
    });

    testWidgets('elegir una la vincula, la tría y lo informa', (tester) async {
      final id = await seedSource(title: 'El Imperio romano');
      final note = await seedLivingNote('Roma antigua');
      await pumpInbox(tester);

      await openLinkPicker(tester);
      await tester.tap(find.text('Roma antigua'));
      await tester.pumpAndSettle();

      expect(await citationsOf(id), [(note, id)]);
      expect(await stateOf(id), ItemState.triaged);
      expect(
        find.text(es.inboxLinkedSnack('Roma antigua', 'El Imperio romano')),
        findsOneWidget,
      );
    });

    testWidgets('sin ninguna nota viva, el selector explica cómo crear una y '
        'no la tría mientras no se crea', (tester) async {
      final id = await seedSource();
      await pumpInbox(tester);

      await openLinkPicker(tester);

      expect(find.text(es.pickLivingNoteNoOthers), findsOneWidget);
      expect(find.text(es.pickLivingNoteCreateHint), findsOneWidget);

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();
      expect(await stateOf(id), ItemState.processed);
    });

    testWidgets('crear una desde el selector: nota viva nueva, vinculada, y '
        'la fuente triada', (tester) async {
      final id = await seedSource(title: 'El Imperio romano');
      await pumpInbox(tester);

      await openLinkPicker(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(PickLivingNoteDialog),
          matching: find.byType(TextField),
        ),
        'Roma antigua',
      );
      await tester.pumpAndSettle();
      expect(find.text(es.pickLivingNoteNoMatches('Roma antigua')), findsOne);
      await tester.tap(find.byKey(const Key('pick-living-note-create')));
      await tester.pumpAndSettle();

      final notes = await livingNotes();
      expect(notes.map((n) => n.title), ['Roma antigua']);
      expect(await citationsOf(id), [(notes.single.id, id)]);
      expect(await stateOf(id), ItemState.triaged);
    });

    testWidgets('con el nombre de una fuente no crea nada: lo dice y la deja '
        'en la Bandeja', (tester) async {
      final id = await seedSource(title: 'El Imperio romano');
      await pumpInbox(tester);

      await openLinkPicker(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(PickLivingNoteDialog),
          matching: find.byType(TextField),
        ),
        'El Imperio romano',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-living-note-create')));
      await tester.pumpAndSettle();

      expect(
        find.text(es.inboxLinkNameTaken('El Imperio romano')),
        findsOneWidget,
      );
      expect(await citationsOf(id), isEmpty);
      expect(await stateOf(id), ItemState.processed);
    });

    testWidgets('deshacer un vínculo con una nota creada para él: sin '
        'vínculo, la nota en la papelera y la fuente de vuelta', (
      tester,
    ) async {
      final id = await seedSource(title: 'El Imperio romano');
      await pumpInbox(tester);
      await openLinkPicker(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(PickLivingNoteDialog),
          matching: find.byType(TextField),
        ),
        'Roma antigua',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-living-note-create')));
      await tester.pumpAndSettle();
      final noteId = (await citationsOf(id)).single.$1;

      await tester.tap(find.widgetWithText(SnackBarAction, es.inboxUndo));
      await tester.pumpAndSettle();

      expect(await citationsOf(id), isEmpty);
      expect(await stateOf(id), ItemState.processed);
      final note = await (harness.database.select(
        harness.database.knowledgeEntries,
      )..where((e) => e.id.equals(noteId))).getSingle();
      expect(note.deletedAt, isNotNull);
      expect(find.text(es.inboxUndoneNoteTrashed('Roma antigua')), findsOne);
    });

    testWidgets('deshacer un vínculo con una nota que ya existía no la toca', (
      tester,
    ) async {
      final id = await seedSource();
      final note = await seedLivingNote('Roma antigua');
      await pumpInbox(tester);
      await openLinkPicker(tester);
      await tester.tap(find.text('Roma antigua'));
      await tester.pumpAndSettle();

      await undo(tester);

      expect(await citationsOf(id), isEmpty);
      expect(await stateOf(id), ItemState.processed);
      final row = await (harness.database.select(
        harness.database.knowledgeEntries,
      )..where((e) => e.id.equals(note))).getSingle();
      expect(row.deletedAt, isNull);
    });
  });

  group('avisos y deshacer', () {
    testWidgets('cada decisión deja un aviso con «Ver» y «Deshacer»', (
      tester,
    ) async {
      await seedSource(title: 'Triada');
      await pumpInbox(tester);

      await swipe(tester, const Offset(300, 0));

      expect(find.text(es.inboxTriagedSnack('Triada')), findsOneWidget);
      expect(find.widgetWithText(TextButton, es.inboxView), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, es.inboxUndo), findsOne);
    });

    testWidgets('«Ver» abre el elemento', (tester) async {
      final id = await seedSource(title: 'Para mirar');
      await tester.pumpWidget(harness.wrapWithAppRouter());
      harness.container.read(goRouterProvider).go(RoutePaths.inbox);
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.inboxActionTriage));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, es.inboxView));
      await tester.pumpAndSettle();

      final detail = tester.widget<ItemDetailScreen>(
        find.byType(ItemDetailScreen),
      );
      expect(detail.itemId, id);
    });

    testWidgets('se deshace de a muchos pasos, del último al primero', (
      tester,
    ) async {
      final first = await seedSource(title: 'Primera');
      final second = await seedSource(title: 'Segunda');
      final third = await seedSource(title: 'Tercera');
      await pumpInbox(tester);
      await swipe(tester, const Offset(-300, 0));
      await swipe(tester, const Offset(300, 0));
      await swipe(tester, const Offset(-300, 0));
      expect(find.text(es.inboxEmptyTitle), findsOneWidget);

      await undo(tester);
      expect(await stateOf(third), ItemState.processed);
      expect(await stateOf(second), ItemState.triaged);
      // Lo que vuelve se ve arriba del mazo.
      expect(find.text('Tercera'), findsOneWidget);

      await undo(tester);
      await undo(tester);

      expect(await stateOf(second), ItemState.processed);
      expect(await stateOf(first), ItemState.processed);
      expect(find.text('Primera'), findsOneWidget);
      expect(canUndo(tester), isFalse);
    });

    testWidgets('Ctrl+Z también deshace más de un paso', (tester) async {
      final first = await seedSource();
      final second = await seedSource();
      await pumpInbox(tester);
      await swipe(tester, const Offset(-300, 0));
      await swipe(tester, const Offset(-300, 0));

      for (var i = 0; i < 2; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      expect(await stateOf(first), ItemState.processed);
      expect(await stateOf(second), ItemState.processed);
    });

    testWidgets('el historial sobrevive a salir de la Bandeja y volver', (
      tester,
    ) async {
      final id = await seedSource(title: 'Me arrepentí después');
      await pumpInbox(tester);
      await swipe(tester, const Offset(-300, 0));

      // Otra pantalla: la Bandeja se desmonta entera.
      await tester.pumpWidget(harness.wrap(const SizedBox()));
      await tester.pumpAndSettle();
      expect(find.byType(InboxScreen), findsNothing);

      await tester.pumpWidget(harness.wrap(const InboxScreen()));
      await tester.pumpAndSettle();
      expect(canUndo(tester), isTrue);

      await undo(tester);

      expect(await stateOf(id), ItemState.processed);
      expect(find.text('Me arrepentí después'), findsOneWidget);
    });
  });

  group('la cola detrás de «N pendientes»', () {
    testWidgets('lista todo lo que espera, con su tipo', (tester) async {
      await seedSource(title: 'Un artículo');
      await seedSource(title: 'Un video', kind: SourceKind.youtube);
      await seedSource(title: 'Un documento', kind: SourceKind.document);
      await pumpInbox(tester);

      await tester.tap(find.text(es.inboxPendingCount(3)));
      await tester.pumpAndSettle();

      final sheet = find.byType(InboxQueueSheet);
      expect(sheet, findsOneWidget);
      for (final title in ['Un artículo', 'Un video', 'Un documento']) {
        expect(
          find.descendant(of: sheet, matching: find.text(title)),
          findsOneWidget,
        );
      }
      // La que está a la vista, marcada.
      expect(
        find.descendant(of: sheet, matching: find.text(es.inboxQueueShowing)),
        findsOneWidget,
      );
    });

    testWidgets('tocar una la lleva arriba del mazo', (tester) async {
      await seedSource(title: 'Primera');
      final last = await seedSource(title: 'La que elijo');
      await pumpInbox(tester);
      expect(find.text('Primera'), findsOneWidget);

      await tester.tap(find.text(es.inboxPendingCount(2)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(InboxQueueSheet),
          matching: find.text('La que elijo'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InboxQueueSheet), findsNothing);
      expect(find.text('La que elijo'), findsOneWidget);
      expect(find.text('Primera'), findsNothing);

      // Y lo que se decida es sobre esa.
      await swipe(tester, const Offset(300, 0));
      expect(await stateOf(last), ItemState.triaged);
      expect(find.text('Primera'), findsOneWidget);
    });
  });

  group('la tarjeta de la primera vez', () {
    setUp(() async {
      harness = await LibraryHarness.create(inboxIntroDismissed: false);
    });

    testWidgets('explica qué es triar, y «Entendido» la cierra para siempre', (
      tester,
    ) async {
      await seedSource();
      await pumpInbox(tester);

      expect(find.byType(InboxIntroCard), findsOneWidget);
      expect(find.text(es.inboxIntroTitle), findsOneWidget);

      await tester.tap(find.text(es.inboxIntroDismiss));
      await tester.pumpAndSettle();

      expect(find.text(es.inboxIntroTitle), findsNothing);
      // Recordada entre reinicios, no solo en esta pantalla: quien la lea al
      // arrancar de nuevo ya la encuentra cerrada.
      final prefs = harness.container.read(sharedPreferencesProvider);
      expect(InboxIntroNotifier(prefs: prefs).state, isTrue);
    });
  });
}
