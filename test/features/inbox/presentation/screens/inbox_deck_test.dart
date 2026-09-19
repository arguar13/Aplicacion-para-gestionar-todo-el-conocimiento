import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/screens/extract_note_screen.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/swipe_card.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La Bandeja como un mazo: gestos, teclas, deshacer y chips de propiedades.
///
/// Cada gesto, cada tecla y cada botón tienen que hacer lo mismo: lo que se
/// prueba acá es que el estado de la fuente queda igual sea cual sea el camino.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  /// Guarda una fuente lista para triar, con su texto si se pide (sin texto no
  /// hay de dónde extraer notas).
  Future<String> seedSource({
    String? title,
    bool withText = false,
    DateTime? updatedAt,
  }) async {
    final n = counter++;
    final now =
        updatedAt ?? DateTime(2026, 9, 18, 10).add(Duration(minutes: n));
    final id = 'item-${n.toString().padLeft(3, '0')}';
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: title ?? 'Fuente $n',
            source: Source(
              id: 'src-$n',
              kind: SourceKind.webPage,
              capturedAt: now,
              url: 'https://ejemplo.org/$n',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              if (withText)
                Rendition.text(
                  id: 'rend-$n',
                  itemId: id,
                  kind: RenditionKind.plainText,
                  content: 'El texto de la fuente $n.',
                  isPrimary: true,
                  createdAt: now,
                ),
            ],
          ),
        );
    return id;
  }

  Future<ItemState> stateOf(String id) async {
    final row = await (harness.database.select(
      harness.database.knowledgeEntries,
    )..where((e) => e.id.equals(id))).getSingle();
    return row.state;
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

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  group('gestos', () {
    testWidgets('a la izquierda descarta', (tester) async {
      final id = await seedSource(title: 'Para descartar');
      await pumpInbox(tester);

      await swipe(tester, const Offset(-300, 0));

      expect(await stateOf(id), ItemState.discarded);
      expect(find.text('Para descartar'), findsNothing);
      expect(find.text(es.inboxEmptyTitle), findsOneWidget);
    });

    testWidgets('a la derecha la deja triada', (tester) async {
      final id = await seedSource(title: 'Para triar');
      await pumpInbox(tester);

      await swipe(tester, const Offset(300, 0));

      expect(await stateOf(id), ItemState.triaged);
      expect(find.text(es.inboxEmptyTitle), findsOneWidget);
    });

    testWidgets('hacia arriba la abre para extraer notas', (tester) async {
      final id = await seedSource(withText: true);
      await pumpInbox(tester);

      await swipe(tester, const Offset(0, -300));

      expect(await stateOf(id), ItemState.triaged);
      expect(find.byType(ExtractNoteScreen), findsOneWidget);
    });

    testWidgets('un arrastre corto no decide: la tarjeta vuelve a su lugar', (
      tester,
    ) async {
      final id = await seedSource(title: 'Sigue acá');
      await pumpInbox(tester);

      await swipe(tester, const Offset(-40, 0));

      expect(await stateOf(id), ItemState.processed);
      expect(find.text('Sigue acá'), findsOneWidget);
    });

    testWidgets('hacia abajo no significa nada', (tester) async {
      final id = await seedSource(title: 'Sigue acá');
      await pumpInbox(tester);

      await swipe(tester, const Offset(0, 300));

      expect(await stateOf(id), ItemState.processed);
      expect(find.text('Sigue acá'), findsOneWidget);
    });

    testWidgets('en diagonal manda el eje dominante', (tester) async {
      final id = await seedSource();
      await pumpInbox(tester);

      // Más a la izquierda que hacia arriba: descarta.
      await swipe(tester, const Offset(-250, -120));

      expect(await stateOf(id), ItemState.discarded);
    });

    testWidgets('un empujón rápido decide sin llegar al umbral', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpInbox(tester);

      await tester.fling(find.byType(SwipeCard), const Offset(-60, 0), 2000);
      await tester.pumpAndSettle();

      expect(await stateOf(id), ItemState.discarded);
    });

    testWidgets('mientras se arrastra se ve qué pasaría al soltar', (
      tester,
    ) async {
      await seedSource();
      await pumpInbox(tester);
      // Antes de arrastrar, "Descartar" solo está en el botón.
      expect(find.text(es.inboxActionDiscard), findsOneWidget);

      // Un dedo no salta 80 píxeles de una vez: son varios movimientos chicos.
      Future<void> drag(TestGesture gesture, double dx) async {
        for (var i = 0; i < 8; i++) {
          await gesture.moveBy(Offset(dx / 8, 0));
          await tester.pump();
        }
      }

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwipeCard)),
      );
      await drag(gesture, -120);

      // Ahora también en la pista de la tarjeta.
      expect(find.text(es.inboxActionDiscard), findsNWidgets(2));

      await drag(gesture, 240);
      expect(find.text(es.inboxActionTriage), findsNWidgets(2));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('lo que se suelta antes del umbral deja la fuente pendiente', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpInbox(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwipeCard)),
      );
      await gesture.moveBy(const Offset(-50, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(await stateOf(id), ItemState.processed);
    });
  });

  group('botones', () {
    testWidgets('Triado la deja triada', (tester) async {
      final id = await seedSource();
      await pumpInbox(tester);

      await tester.tap(find.text(es.inboxActionTriage));
      await tester.pumpAndSettle();

      expect(await stateOf(id), ItemState.triaged);
    });

    testWidgets('Descartar la descarta', (tester) async {
      final id = await seedSource();
      await pumpInbox(tester);

      await tester.tap(find.text(es.inboxActionDiscard));
      await tester.pumpAndSettle();

      expect(await stateOf(id), ItemState.discarded);
    });

    testWidgets('Extraer como nota la abre para extraer', (tester) async {
      final id = await seedSource(withText: true);
      await pumpInbox(tester);

      await tester.tap(find.text(es.inboxActionExtract));
      await tester.pumpAndSettle();

      expect(await stateOf(id), ItemState.triaged);
      expect(find.byType(ExtractNoteScreen), findsOneWidget);
    });
  });

  group('teclado', () {
    testWidgets('flecha izquierda descarta', (tester) async {
      final id = await seedSource();
      await pumpInbox(tester);

      await key(tester, LogicalKeyboardKey.arrowLeft);

      expect(await stateOf(id), ItemState.discarded);
    });

    testWidgets('flecha derecha la deja triada', (tester) async {
      final id = await seedSource();
      await pumpInbox(tester);

      await key(tester, LogicalKeyboardKey.arrowRight);

      expect(await stateOf(id), ItemState.triaged);
    });

    testWidgets('flecha arriba la abre para extraer', (tester) async {
      final id = await seedSource(withText: true);
      await pumpInbox(tester);

      await key(tester, LogicalKeyboardKey.arrowUp);

      expect(await stateOf(id), ItemState.triaged);
      expect(find.byType(ExtractNoteScreen), findsOneWidget);
    });

    testWidgets('Ctrl+Z devuelve la última a la Bandeja', (tester) async {
      final id = await seedSource(title: 'Se arrepintió');
      await pumpInbox(tester);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(find.text('Se arrepintió'), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(await stateOf(id), ItemState.processed);
      expect(find.text('Se arrepintió'), findsOneWidget);
    });
  });

  group('deshacer', () {
    testWidgets('sin nada que deshacer, el botón está deshabilitado', (
      tester,
    ) async {
      await seedSource();
      await pumpInbox(tester);

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.undo),
      );

      expect(button.onPressed, isNull);
    });

    testWidgets('el botón devuelve la fuente a la Bandeja', (tester) async {
      final id = await seedSource(title: 'Vuelve');
      await pumpInbox(tester);
      await swipe(tester, const Offset(-300, 0));
      expect(find.text('Vuelve'), findsNothing);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
      await tester.pumpAndSettle();

      expect(await stateOf(id), ItemState.processed);
      expect(find.text('Vuelve'), findsOneWidget);
    });

    testWidgets('el aviso ofrece deshacer', (tester) async {
      final id = await seedSource(title: 'Desde el aviso');
      await pumpInbox(tester);
      await swipe(tester, const Offset(-300, 0));
      expect(
        find.text(es.inboxDiscardedSnack('Desde el aviso')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(SnackBarAction, es.inboxUndo));
      await tester.pumpAndSettle();

      expect(await stateOf(id), ItemState.processed);
    });

    testWidgets('el aviso de triar también', (tester) async {
      await seedSource(title: 'Triada');
      await pumpInbox(tester);

      await swipe(tester, const Offset(300, 0));

      expect(find.text(es.inboxTriagedSnack('Triada')), findsOneWidget);
    });

    testWidgets('después de deshacer no queda nada más que deshacer', (
      tester,
    ) async {
      await seedSource();
      await pumpInbox(tester);
      await swipe(tester, const Offset(-300, 0));
      await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.undo),
      );

      expect(button.onPressed, isNull);
    });

    testWidgets('deshacer solo alcanza a la última', (tester) async {
      final first = await seedSource(title: 'Primera');
      final second = await seedSource(title: 'Segunda');
      await pumpInbox(tester);
      await swipe(tester, const Offset(-300, 0));
      await swipe(tester, const Offset(-300, 0));

      await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
      await tester.pumpAndSettle();

      expect(await stateOf(second), ItemState.processed);
      expect(await stateOf(first), ItemState.discarded);
    });

    testWidgets('la fuente vuelve al lugar que tenía en la fila', (
      tester,
    ) async {
      await seedSource(title: 'Primera');
      await seedSource(title: 'Segunda');
      await pumpInbox(tester);
      await swipe(tester, const Offset(-300, 0));
      expect(find.text('Segunda'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
      await tester.pumpAndSettle();

      // Sigue siendo la primera de la fila, no la última.
      expect(find.text('Primera'), findsOneWidget);
      expect(find.text('Segunda'), findsNothing);
    });
  });

  group('propiedades sugeridas', () {
    Future<String> suggest(
      String itemId, {
      String category = 'Región',
      String value = 'Roma',
    }) async {
      final definition =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .getOrCreatePropertyDefinition(category))
              .getRight()
              .toNullable()!;
      return (await harness.container
              .read(suggestionRepositoryProvider)
              .createPropertySuggestion(
                targetItemId: itemId,
                definitionId: definition.id,
                definitionName: category,
                value: value,
                isNewValue: true,
              ))
          .getRight()
          .toNullable()!
          .id;
    }

    Future<List<String>> propertiesOf(String id) async =>
        (await harness.container.read(libraryRepositoryProvider).findById(id))
            .getRight()
            .toNullable()!
            .properties
            .map((p) => p.value)
            .toList();

    Finder chip(String label) => find.widgetWithText(FilterChip, label);

    testWidgets('cada sugerencia de propiedad es un chip', (tester) async {
      final id = await seedSource();
      await suggest(id);
      await suggest(id, category: 'Época', value: 'Antigüedad');
      await pumpInbox(tester);

      expect(find.text(es.inboxSuggestedProperties), findsOneWidget);
      expect(chip('Región: Roma'), findsOneWidget);
      expect(chip('Época: Antigüedad'), findsOneWidget);
    });

    testWidgets('sin sugerencias no hay sección de chips', (tester) async {
      await seedSource();
      await pumpInbox(tester);

      expect(find.text(es.inboxSuggestedProperties), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('tocar un chip acepta la propiedad y el chip sigue a la '
        'vista, marcado', (tester) async {
      final id = await seedSource();
      await suggest(id);
      await pumpInbox(tester);

      await tester.tap(chip('Región: Roma'));
      await tester.pumpAndSettle();

      expect(await propertiesOf(id), ['Roma']);
      expect(tester.widget<FilterChip>(chip('Región: Roma')).selected, isTrue);
    });

    testWidgets('tocarlo de nuevo deshace esa propiedad', (tester) async {
      final id = await seedSource();
      await suggest(id);
      await pumpInbox(tester);
      await tester.tap(chip('Región: Roma'));
      await tester.pumpAndSettle();

      await tester.tap(chip('Región: Roma'));
      await tester.pumpAndSettle();

      expect(await propertiesOf(id), isEmpty);
      expect(tester.widget<FilterChip>(chip('Región: Roma')).selected, isFalse);
    });

    testWidgets('se puede volver a aceptar después de deshacer', (
      tester,
    ) async {
      final id = await seedSource();
      await suggest(id);
      await pumpInbox(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(chip('Región: Roma'));
        await tester.pumpAndSettle();
      }

      expect(await propertiesOf(id), ['Roma']);
      expect(tester.widget<FilterChip>(chip('Región: Roma')).selected, isTrue);
    });

    testWidgets('cada chip es independiente', (tester) async {
      final id = await seedSource();
      await suggest(id);
      await suggest(id, category: 'Época', value: 'Antigüedad');
      await pumpInbox(tester);

      await tester.tap(chip('Región: Roma'));
      await tester.pumpAndSettle();

      expect(await propertiesOf(id), ['Roma']);
      expect(
        tester.widget<FilterChip>(chip('Época: Antigüedad')).selected,
        isFalse,
      );
    });

    testWidgets('lo aceptado queda con el origen de una sugerencia aceptada', (
      tester,
    ) async {
      final id = await seedSource();
      await suggest(id);
      await pumpInbox(tester);

      await tester.tap(chip('Región: Roma'));
      await tester.pumpAndSettle();

      final item =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      expect(
        item.properties.single.origin,
        ItemPropertyOrigin.suggestedAccepted,
      );
    });

    testWidgets('triar con un chip aceptado conserva la propiedad', (
      tester,
    ) async {
      final id = await seedSource();
      await suggest(id);
      await pumpInbox(tester);
      await tester.tap(chip('Región: Roma'));
      await tester.pumpAndSettle();

      await swipe(tester, const Offset(300, 0));

      expect(await stateOf(id), ItemState.triaged);
      expect(await propertiesOf(id), ['Roma']);
    });

    testWidgets('los chips no pasan de una fuente a la siguiente', (
      tester,
    ) async {
      final first = await seedSource(title: 'Primera');
      await seedSource(title: 'Segunda');
      await suggest(first);
      await pumpInbox(tester);
      expect(chip('Región: Roma'), findsOneWidget);

      await swipe(tester, const Offset(300, 0));

      expect(find.text('Segunda'), findsOneWidget);
      expect(chip('Región: Roma'), findsNothing);
    });
  });

  group('sin salir de la pantalla', () {
    testWidgets('triar 50 fuentes con gestos y teclas no cambia de pantalla', (
      tester,
    ) async {
      final ids = [for (var i = 0; i < 50; i++) await seedSource()];
      await pumpInbox(tester);
      expect(find.text(es.inboxPendingCount(50)), findsOneWidget);

      for (var i = 0; i < 50; i++) {
        // Una mezcla de los tres caminos que hacen lo mismo.
        switch (i % 5) {
          case 0:
            await swipe(tester, const Offset(-300, 0));
          case 1:
            await swipe(tester, const Offset(300, 0));
          case 2:
            await key(tester, LogicalKeyboardKey.arrowLeft);
          case 3:
            await key(tester, LogicalKeyboardKey.arrowRight);
          case 4:
            await tester.tap(find.text(es.inboxActionTriage));
            await tester.pumpAndSettle();
        }

        // Nunca sale de la Bandeja.
        expect(find.byType(InboxScreen), findsOneWidget);
      }

      expect(find.text(es.inboxEmptyTitle), findsOneWidget);
      final states = [for (final id in ids) await stateOf(id)];
      expect(states.where((s) => s == ItemState.discarded), hasLength(20));
      expect(states.where((s) => s == ItemState.triaged), hasLength(30));
      // Ninguna pantalla quedó apilada encima.
      expect(
        Navigator.of(tester.element(find.byType(InboxScreen))).canPop(),
        isFalse,
      );
    });

    testWidgets('el contador baja de a uno con cada gesto', (tester) async {
      for (var i = 0; i < 4; i++) {
        await seedSource();
      }
      await pumpInbox(tester);

      for (var remaining = 4; remaining > 1; remaining--) {
        expect(find.text(es.inboxPendingCount(remaining)), findsOneWidget);
        await swipe(tester, const Offset(300, 0));
      }

      expect(find.text(es.inboxPendingCount(1)), findsOneWidget);
    });
  });
}
