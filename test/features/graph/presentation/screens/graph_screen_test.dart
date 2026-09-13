import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/graph/presentation/screens/graph_screen.dart';
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
}
