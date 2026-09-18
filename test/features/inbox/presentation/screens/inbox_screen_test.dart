import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  /// Guarda una fuente ya "procesada" —lista para triar— directo por el
  /// mismo repositorio que usa la app, para que el espejo (F3) la deje en
  /// `ItemState.processed`. No pasa por la cola de la app: los adaptadores
  /// de URL dejarían el elemento en `pending` a propósito, esperando un
  /// procesamiento que la cola de mentira del harness nunca hace.
  Future<String> seedProcessedSource({String title = 'Un elemento'}) async {
    final n = counter++;
    final now = DateTime(2026, 9, 18, 10);
    final item = KnowledgeItem(
      id: 'item-$n',
      title: title,
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );
    await harness.container.read(libraryRepositoryProvider).save(item);
    return item.id;
  }

  Future<void> pumpInbox(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const InboxScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('sin nada pendiente, explica que no hay nada que triar', (
    tester,
  ) async {
    await pumpInbox(tester);

    expect(find.text(es.inboxEmptyTitle), findsOneWidget);
  });

  testWidgets('una fuente procesada aparece, con el contador correcto', (
    tester,
  ) async {
    await seedProcessedSource(title: 'Un artículo cualquiera');

    await pumpInbox(tester);

    expect(find.text('Un artículo cualquiera'), findsOneWidget);
    expect(find.text(es.inboxPendingCount(1)), findsOneWidget);
  });

  testWidgets('tocar Descartar la saca de la Bandeja', (tester) async {
    await seedProcessedSource(title: 'Algo para descartar');

    await pumpInbox(tester);
    await tester.tap(find.text(es.inboxActionDiscard));
    await tester.pumpAndSettle();

    expect(find.text('Algo para descartar'), findsNothing);
    expect(find.text(es.inboxEmptyTitle), findsOneWidget);
  });
}
