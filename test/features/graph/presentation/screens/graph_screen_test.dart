import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/graph/presentation/screens/graph_screen.dart';
import 'package:sinapsis/features/graph/presentation/widgets/graph_edges_painter.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpGraph(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const GraphScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('sin ningún vínculo, explica que todavía no hay nada que ver', (
    tester,
  ) async {
    await harness.capture('una nota sin vínculos');

    await pumpGraph(tester);

    expect(find.text(es.graphEmpty), findsOneWidget);
  });

  testWidgets('con un vínculo, muestra los dos elementos como nodos tocables', (
    tester,
  ) async {
    await harness.capture('El artículo original');
    await harness.capture('La respuesta');

    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    final itemA = items.firstWhere((i) => i.title == 'El artículo original');
    final itemB = items.firstWhere((i) => i.title == 'La respuesta');

    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: itemA.id,
          toItemId: itemB.id,
          kind: RelationKind.relatedTo,
        );

    await pumpGraph(tester);

    expect(find.text(es.graphEmpty), findsNothing);
    expect(find.text('El artículo original'), findsOneWidget);
    expect(find.text('La respuesta'), findsOneWidget);
  });

  testWidgets('tocar un nodo navega al detalle de ese elemento', (
    tester,
  ) async {
    await harness.capture('El artículo original');
    await harness.capture('La respuesta');

    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    final itemA = items.firstWhere((i) => i.title == 'El artículo original');
    final itemB = items.firstWhere((i) => i.title == 'La respuesta');

    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: itemA.id,
          toItemId: itemB.id,
          kind: RelationKind.relatedTo,
        );

    harness.goTo('/graph');
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    await tester.tap(find.text('El artículo original'));
    await tester.pumpAndSettle();

    expect(find.text('El artículo original'), findsWidgets);
  });

  group('filtro por espacio', () {
    testWidgets('elegir un espacio deja solo los vínculos puertas adentro', (
      tester,
    ) async {
      await harness.capture('El artículo original');
      await harness.capture('La respuesta');
      await harness.capture('Algo de otro espacio');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final itemA = items.firstWhere((i) => i.title == 'El artículo original');
      final itemB = items.firstWhere((i) => i.title == 'La respuesta');
      final itemC = items.firstWhere((i) => i.title == 'Algo de otro espacio');

      final organize = harness.container.read(organizeRepositoryProvider);
      final space = (await organize.createSpace(
        'Filosofía',
      )).getRight().toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpace(itemId: itemA.id, spaceId: space.id);
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpace(itemId: itemB.id, spaceId: space.id);

      await organize.createRelation(
        fromItemId: itemA.id,
        toItemId: itemB.id,
        kind: RelationKind.relatedTo,
      );
      await organize.createRelation(
        fromItemId: itemB.id,
        toItemId: itemC.id,
        kind: RelationKind.relatedTo,
      );

      await pumpGraph(tester);

      // Sin filtrar, se ven los tres.
      expect(find.text('Algo de otro espacio'), findsOneWidget);

      await tester.tap(find.byTooltip(es.graphSpaceFilterTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filosofía').last);
      await tester.pumpAndSettle();

      // Al elegir el espacio, el grado por defecto es "todos": se ve la red
      // completa que toca el espacio. Achicando el grado a 0 queda solo lo
      // que conecta puertas adentro.
      await tester.tap(find.text('0'));
      await tester.pumpAndSettle();

      expect(find.text('El artículo original'), findsOneWidget);
      expect(find.text('La respuesta'), findsOneWidget);
      expect(find.text('Algo de otro espacio'), findsNothing);
    });
  });

  group('temas del grafo', () {
    testWidgets(
      'dos parejas sin vínculo entre sí muestran un solo tema de entrada',
      (tester) async {
        await harness.capture('Uno');
        await harness.capture('Dos');
        await harness.capture('Tres');
        await harness.capture('Cuatro');

        final items =
            (await harness.container
                    .read(libraryRepositoryProvider)
                    .list(const LibraryQuery()))
                .getRight()
                .toNullable()!;
        final uno = items.firstWhere((i) => i.title == 'Uno');
        final dos = items.firstWhere((i) => i.title == 'Dos');
        final tres = items.firstWhere((i) => i.title == 'Tres');
        final cuatro = items.firstWhere((i) => i.title == 'Cuatro');

        final organize = harness.container.read(organizeRepositoryProvider);
        // Dos parejas, sin ningún vínculo que las una entre sí: son dos
        // temas distintos, no uno con cuatro elementos.
        await organize.createRelation(
          fromItemId: uno.id,
          toItemId: dos.id,
          kind: RelationKind.relatedTo,
        );
        await organize.createRelation(
          fromItemId: tres.id,
          toItemId: cuatro.id,
          kind: RelationKind.relatedTo,
        );

        await pumpGraph(tester);

        // Solo una de las dos parejas está a la vista: la otra queda
        // escondida detrás del tema elegido automáticamente.
        final unoVisible = find.text('Uno').evaluate().isNotEmpty;
        if (unoVisible) {
          expect(find.text('Dos'), findsOneWidget);
          expect(find.text('Tres'), findsNothing);
          expect(find.text('Cuatro'), findsNothing);
        } else {
          expect(find.text('Tres'), findsOneWidget);
          expect(find.text('Cuatro'), findsOneWidget);
          expect(find.text('Uno'), findsNothing);
        }

        // El chip para volver a verlos todos juntos está ahí.
        expect(find.text(es.graphComponentAllLabel), findsOneWidget);

        await tester.tap(find.text(es.graphComponentAllLabel));
        await tester.pumpAndSettle();

        expect(find.text('Uno'), findsOneWidget);
        expect(find.text('Dos'), findsOneWidget);
        expect(find.text('Tres'), findsOneWidget);
        expect(find.text('Cuatro'), findsOneWidget);
      },
    );

    testWidgets('un solo grupo conectado no ofrece ningún selector de tema', (
      tester,
    ) async {
      await harness.capture('El artículo original');
      await harness.capture('La respuesta');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;

      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: items.first.id,
            toItemId: items.last.id,
            kind: RelationKind.relatedTo,
          );

      await pumpGraph(tester);

      expect(find.text(es.graphComponentAllLabel), findsNothing);
    });

    testWidgets('el chip de un tema usa la etiqueta que comparten sus '
        'elementos', (tester) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      await harness.capture('Tres');
      await harness.capture('Cuatro');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final uno = items.firstWhere((i) => i.title == 'Uno');
      final dos = items.firstWhere((i) => i.title == 'Dos');
      final tres = items.firstWhere((i) => i.title == 'Tres');
      final cuatro = items.firstWhere((i) => i.title == 'Cuatro');

      final organize = harness.container.read(organizeRepositoryProvider);
      final library = harness.container.read(libraryRepositoryProvider);
      final tag = (await organize.getOrCreateTag(
        'Filosofía',
      )).getRight().toNullable()!;
      await library.save(uno.copyWith(tags: [tag]));
      await library.save(dos.copyWith(tags: [tag]));

      await organize.createRelation(
        fromItemId: uno.id,
        toItemId: dos.id,
        kind: RelationKind.relatedTo,
      );
      await organize.createRelation(
        fromItemId: tres.id,
        toItemId: cuatro.id,
        kind: RelationKind.relatedTo,
      );

      await pumpGraph(tester);

      expect(
        find.text(es.graphComponentTagLabel('Filosofía', 2)),
        findsOneWidget,
      );
    });
  });

  group('agregar vínculo manualmente', () {
    testWidgets('el botón de agregar crea un vínculo entre dos elementos', (
      tester,
    ) async {
      await harness.capture('El artículo original');
      await harness.capture('La respuesta');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final itemA = items.firstWhere((i) => i.title == 'El artículo original');
      final itemB = items.firstWhere((i) => i.title == 'La respuesta');

      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: itemA.id,
            toItemId: itemB.id,
            kind: RelationKind.relatedTo,
          );

      await harness.capture('Un tercer elemento suelto');

      await pumpGraph(tester);

      await tester.tap(find.byTooltip(es.graphAddRelationTooltip));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Un tercer elemento suelto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('El artículo original').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.pickRelationConfirm));
      await tester.pumpAndSettle();

      expect(find.text('Un tercer elemento suelto'), findsOneWidget);
    });
  });

  group('arrastrar nodos', () {
    testWidgets('arrastrar un nodo bien lejos agranda el lienzo para seguir '
        'alcanzándolo con el toque, en vez de dejarlo fijado fuera de rango', (
      tester,
    ) async {
      await harness.capture('El artículo original');
      await harness.capture('La respuesta');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final itemA = items.firstWhere((i) => i.title == 'El artículo original');
      final itemB = items.firstWhere((i) => i.title == 'La respuesta');

      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: itemA.id,
            toItemId: itemB.id,
            kind: RelationKind.relatedTo,
          );

      await pumpGraph(tester);

      // El único `CustomPaint` de las aristas del grafo: su tamaño es
      // justo el rectángulo que arma `_canvasBounds` a partir de las
      // posiciones de verdad, el mismo que usa el `Stack` que contiene
      // a los nodos.
      Finder edgesPaint() => find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is GraphEdgesPainter,
      );

      final sizeBefore = tester.widget<CustomPaint>(edgesPaint()).size;
      final centerBefore = tester.getCenter(find.text('El artículo original'));

      // Arrastrar bien lejos: el layout de fuerzas ya no tiene límite
      // (ver `computeGraphLayout`), y este mismo arrastre a mano es la
      // otra forma en la que un nodo puede terminar bien afuera del
      // rectángulo con el que arrancó el lienzo.
      //
      // Paso a paso con `startGesture`/`moveBy`, no `tester.drag()`: cada
      // movimiento dispara un `setState` —ver el comentario de
      // `_liveDragPosition`— y sin un `pump()` propio entre cada uno,
      // `drag()` los manda todos de corrido antes de que el primer
      // `setState` llegue a aplicarse, y el gesto se pierde entero contra
      // este árbol en particular.
      final gesture = await tester.startGesture(centerBefore);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        await gesture.moveBy(const Offset(150, 150));
      }
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.up();
      await tester.pumpAndSettle();

      final sizeAfter = tester.widget<CustomPaint>(edgesPaint()).size;

      // El lienzo tiene que haber crecido para seguir conteniendo al
      // nodo recién arrastrado: si se hubiera quedado con el tamaño de
      // siempre, el nodo se seguiría viendo —`Clip.none`— pero ya no
      // respondería a ningún toque, porque Flutter rechaza de entrada
      // cualquier gesto fuera del tamaño propio de un `Stack`, sin
      // llegar a preguntarle a sus hijos.
      expect(sizeAfter.width, greaterThan(sizeBefore.width + 400));
      expect(sizeAfter.height, greaterThan(sizeBefore.height + 400));
    });
  });

  group('sugerir vínculos con IA', () {
    testWidgets('sin el modelo descargado, avisa antes de pedir nada', (
      tester,
    ) async {
      await harness.capture('El artículo original');
      await harness.capture('La respuesta');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;

      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: items.first.id,
            toItemId: items.last.id,
            kind: RelationKind.relatedTo,
          );

      await pumpGraph(tester);

      await tester.tap(find.byTooltip(es.graphAiSuggestTooltip));
      await tester.pumpAndSettle();

      expect(find.text(es.graphAiModelRequiredTitle), findsOneWidget);
      expect(harness.relationSuggestionService.requests, isEmpty);
    });

    testWidgets(
      'con el modelo listo, muestra las sugerencias y las guarda al confirmar',
      (tester) async {
        harness = await LibraryHarness.create(chatModelReady: true);

        await harness.capture('El artículo original');
        await harness.capture('La respuesta');
        await harness.capture('Un candidato');

        final items =
            (await harness.container
                    .read(libraryRepositoryProvider)
                    .list(const LibraryQuery()))
                .getRight()
                .toNullable()!;
        final seed = items.firstWhere((i) => i.title == 'El artículo original');
        final candidate = items.firstWhere((i) => i.title == 'Un candidato');

        await harness.container
            .read(organizeRepositoryProvider)
            .createRelation(
              fromItemId: seed.id,
              toItemId: items.firstWhere((i) => i.title == 'La respuesta').id,
              kind: RelationKind.relatedTo,
            );

        harness.relationSuggestionService.suggestions = [
          RelationSuggestion(
            itemId: candidate.id,
            kind: RelationKind.relatedTo,
            reason: 'Hablan de lo mismo',
          ),
        ];

        await pumpGraph(tester);

        await tester.tap(find.byTooltip(es.graphAiSuggestTooltip));
        await tester.pumpAndSettle();

        await tester.tap(find.text('El artículo original').last);
        await tester.pumpAndSettle();

        expect(find.text('Un candidato'), findsOneWidget);
        expect(find.text('Hablan de lo mismo'), findsOneWidget);
        expect(harness.relationSuggestionService.requests, hasLength(1));

        await tester.tap(find.text(es.graphAiDialogConfirm(1)));
        await tester.pumpAndSettle();

        expect(find.text(es.graphRelationsAdded(1)), findsOneWidget);
      },
    );
  });

  testWidgets('el botón de tensión navega a la pantalla de Tensión', (
    tester,
  ) async {
    harness.goTo('/graph');
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(es.graphTensionTooltip));
    await tester.pumpAndSettle();

    expect(find.text(es.tensionTitle), findsOneWidget);
  });
}
