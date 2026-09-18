import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/relations/presentation/screens/tension_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpTension(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const TensionScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('sin ninguna contradicción, lo explica', (tester) async {
    await harness.capture('Un elemento sin vínculos');

    await pumpTension(tester);

    expect(find.text(es.tensionEmpty), findsOneWidget);
  });

  testWidgets('un vínculo relatedTo no cuenta como contradicción', (
    tester,
  ) async {
    await harness.capture('A');
    await harness.capture('B');
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    final itemA = items.firstWhere((i) => i.title == 'A');
    final itemB = items.firstWhere((i) => i.title == 'B');

    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: itemA.id,
          toItemId: itemB.id,
          kind: RelationKind.relatedTo,
        );

    await pumpTension(tester);

    expect(find.text(es.tensionEmpty), findsOneWidget);
  });

  testWidgets('con una contradicción, muestra los dos elementos', (
    tester,
  ) async {
    await harness.capture('Un artículo');
    await harness.capture('Otro que lo contradice');
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    final itemA = items.firstWhere((i) => i.title == 'Un artículo');
    final itemB = items.firstWhere((i) => i.title == 'Otro que lo contradice');

    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: itemA.id,
          toItemId: itemB.id,
          kind: RelationKind.contradicts,
        );

    await pumpTension(tester);

    expect(find.text(es.tensionEmpty), findsNothing);
    expect(find.text('Un artículo'), findsOneWidget);
    expect(find.text('Otro que lo contradice'), findsOneWidget);
  });

  testWidgets('tocar un título navega al detalle de ese elemento', (
    tester,
  ) async {
    await harness.capture('Un artículo');
    await harness.capture('Otro que lo contradice');
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    final itemA = items.firstWhere((i) => i.title == 'Un artículo');
    final itemB = items.firstWhere((i) => i.title == 'Otro que lo contradice');

    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: itemA.id,
          toItemId: itemB.id,
          kind: RelationKind.contradicts,
        );

    harness.goTo('/graph/tension');
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Un artículo'));
    await tester.pumpAndSettle();

    expect(find.text('Un artículo'), findsWidgets);
  });
}
