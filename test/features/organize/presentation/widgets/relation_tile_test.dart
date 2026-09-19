import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/organize/presentation/widgets/relations_section.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// La fila de un vínculo: una nota extraída sabe de dónde salió y lleva de
/// vuelta al fragmento exacto de la fuente.
void main() {
  final es = AppLocalizationsEs();

  ItemRelation relation({
    RelationDirection direction = RelationDirection.outgoing,
    RelationKind kind = RelationKind.extractedFrom,
    int? start,
    int? end,
  }) => ItemRelation(
    relationId: 'rel-1',
    direction: direction,
    kind: kind,
    createdAt: DateTime(2026),
    otherItemId: 'fuente',
    otherItemTitle: 'La fuente',
    otherItemSourceKind: SourceKind.webPage,
    sourceCharStart: start,
    sourceCharEnd: end,
  );

  Future<void> pumpTile(
    WidgetTester tester,
    ItemRelation relation, {
    VoidCallback? onDelete,
  }) async {
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                body: RelationTile(
                  relation: relation,
                  onDelete: onDelete ?? () {},
                ),
              ),
            ),
            GoRoute(
              path: RoutePaths.readingPattern,
              builder: (_, state) => Scaffold(
                body: Text(
                  'lectura ${state.pathParameters['id']} '
                  '${state.uri.queryParameters['start']}-'
                  '${state.uri.queryParameters['end']}',
                ),
              ),
            ),
            GoRoute(
              path: RoutePaths.itemDetailPattern,
              builder: (_, state) => Scaffold(
                body: Text('detalle de ${state.pathParameters['id']}'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('una nota extraída con posición ofrece ver en la fuente', (
    tester,
  ) async {
    await pumpTile(tester, relation(start: 10, end: 40));

    expect(find.byTooltip(es.relationViewInSource), findsOneWidget);
  });

  testWidgets('tocarlo abre la fuente en el fragmento exacto', (tester) async {
    await pumpTile(tester, relation(start: 10, end: 40));

    await tester.tap(find.byTooltip(es.relationViewInSource));
    await tester.pumpAndSettle();

    expect(find.text('lectura fuente 10-40'), findsOneWidget);
  });

  testWidgets('sin posición guardada no lo ofrece', (tester) async {
    await pumpTile(tester, relation());

    expect(find.byTooltip(es.relationViewInSource), findsNothing);
  });

  testWidgets('desde la fuente, el vínculo apunta a la nota: tampoco', (
    tester,
  ) async {
    await pumpTile(
      tester,
      relation(direction: RelationDirection.incoming, start: 10, end: 40),
    );

    expect(find.byTooltip(es.relationViewInSource), findsNothing);
  });

  testWidgets('un vínculo que no es una extracción no lo ofrece', (
    tester,
  ) async {
    await pumpTile(tester, relation(kind: RelationKind.relatedTo));

    expect(find.byTooltip(es.relationViewInSource), findsNothing);
  });

  testWidgets('borrar el vínculo sigue funcionando', (tester) async {
    var deleted = 0;
    await pumpTile(
      tester,
      relation(start: 10, end: 40),
      onDelete: () => deleted++,
    );

    await tester.tap(find.byTooltip(es.detailRemoveRelation));

    expect(deleted, 1);
  });

  testWidgets('tocar la fila abre el otro elemento', (tester) async {
    await pumpTile(tester, relation(start: 10, end: 40));

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(find.text('detalle de fuente'), findsOneWidget);
  });
}
