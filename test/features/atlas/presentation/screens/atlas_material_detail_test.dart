import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/atlas/presentation/screens/atlas_screen.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';

/// Del Atlas al detalle de cada elemento de una rama, con el router real.
///
/// El material de una rama se abre ENCIMA del shell (es una ruta de la raíz),
/// y de ahí cada elemento empujaba `/library/:id`, una ruta que vive DENTRO
/// del shell: apilaba un segundo shell con la misma clave de página y el
/// detalle salía en blanco. Estas pruebas recorren la rama entera —cada
/// documento procesado, que es lo que el Atlas cuenta desde F41— y piden que
/// cada uno se vea con lo suyo.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  final now = DateTime(2026, 9, 21, 10);

  final sources = [for (var i = 1; i <= 5; i++) 'Fuente $i'];
  const note = 'Nota de Darwin';

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
  });

  /// «Charles Darwin»: 5 fuentes y 1 nota, como la rama que se rompía.
  Future<void> seedEtiqueta() async {
    final tema = await temaDefinitionId(db);
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: 'darwin',
            definitionId: tema,
            value: 'Charles Darwin',
            createdAt: now,
          ),
        );
    Future<void> assign(String itemId) => db
        .into(db.itemPropertyValues)
        .insert(
          ItemPropertyValuesCompanion.insert(
            itemId: itemId,
            propertyValueId: 'darwin',
          ),
        );
    for (var i = 0; i < sources.length; i++) {
      await insertProcessedDocument(
        db,
        id: 's$i',
        title: sources[i],
        createdAt: now,
      );
      await assign('s$i');
    }
    await insertProcessedDocument(
      db,
      id: 'n1',
      title: note,
      createdAt: now,
      sections: {ProcessedSection.notes},
    );
    await assign('n1');
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.goTo(RoutePaths.atlas);
    await tester.pumpAndSettle();
  }

  /// «Atrás». El tick de más deja correr los temporizadores con que drift
  /// cierra sus consultas al soltar la pantalla que las miraba: sin él, la
  /// prueba termina con uno pendiente.
  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Abre el documento procesado [title] desde el material —el detalle por id
  /// lleva a su pantalla (F41, paso 2)— y comprueba que se vea con su título
  /// en la barra, y que «atrás» vuelva a la lista entera.
  Future<void> openAndBack(
    WidgetTester tester,
    String title,
    List<String> all,
  ) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: title);
    expect(find.byType(ProcessedDocumentScreen), findsOneWidget, reason: title);
    expect(
      find.descendant(
        of: find.descendant(
          of: find.byType(ProcessedDocumentScreen),
          matching: find.byType(AppBar),
        ),
        matching: find.text(title),
      ),
      findsOneWidget,
      reason: title,
    );

    await back(tester);

    expect(find.byType(ProcessedDocumentScreen), findsNothing, reason: title);
    expect(find.byType(ExplorerScreen), findsOneWidget, reason: title);
    for (final other in all) {
      expect(find.text(other), findsOneWidget, reason: other);
    }
  }

  testWidgets('una rama por etiquetas muestra TODO lo suyo, y cada elemento '
      'abre su detalle', (tester) async {
    await seedEtiqueta();
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('atlas-node-darwin')));
    await tester.pumpAndSettle();

    expect(find.byType(ExplorerScreen), findsOneWidget);
    // Las cinco fuentes y la nota: el filtro con insignia «1» es la rama
    // misma, no deja nada afuera.
    final everything = [...sources, note];
    for (final title in everything) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('1')),
      findsOneWidget,
    );

    for (final title in everything) {
      await openAndBack(tester, title, everything);
    }

    // Y «atrás» desde el material vuelve al Atlas.
    await back(tester);
    expect(find.byType(AtlasScreen), findsOneWidget);
  });

  testWidgets('«Ver el material» del menú de la rama también llega al detalle '
      'de sus elementos', (tester) async {
    await seedEtiqueta();
    await pump(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('atlas-node-darwin')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.atlasOpenMaterial));
    await tester.pumpAndSettle();

    await openAndBack(tester, note, [...sources, note]);
  });

  testWidgets('una rama por temas: cada elemento abre su detalle', (
    tester,
  ) async {
    await insertProcessedDocument(
      db,
      id: 'a',
      title: 'Roma antigua',
      createdAt: now,
    );
    await insertProcessedDocument(
      db,
      id: 'b',
      title: 'Nota del foro',
      createdAt: now,
      sections: {ProcessedSection.notes},
    );
    final space =
        (await harness.container
                .read(organizeRepositoryProvider)
                .createSpace('Antigüedad'))
            .getRight()
            .toNullable()!;
    await harness.container
        .read(libraryRepositoryProvider)
        .setSpaces(itemIds: ['a', 'b'], spaceIds: {space.id});
    await pump(tester);

    await tester.tap(find.byKey(ValueKey('atlas-node-${space.id}')));
    await tester.pumpAndSettle();

    expect(find.byType(ExplorerScreen), findsOneWidget);
    const titles = ['Roma antigua', 'Nota del foro'];
    for (final title in titles) {
      await openAndBack(tester, title, titles);
    }
  });
}
