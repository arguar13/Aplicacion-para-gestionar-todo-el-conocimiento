import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// El chip de la Bandeja en el detalle (F28): lo triado se reencuentra, y
/// desde ahí vuelve a la Bandeja.
/// El texto que hace que una fuente esté en la Bandeja (F30, decisión 68): a
/// ella entra solo lo que ya tiene texto.
Rendition _text(String itemId, DateTime at) => Rendition.text(
  id: 'texto-$itemId',
  itemId: itemId,
  kind: RenditionKind.plainText,
  content: 'El texto de $itemId.',
  isPrimary: true,
  createdAt: at,
);

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  /// La hora fija del arnés: la de cada cambio de estado.
  final now = DateTime(2026, 9, 11, 10);

  setUp(() async {
    harness = await LibraryHarness.create(now: now);
  });

  Future<String> seed({
    SourceKind kind = SourceKind.webPage,
    ItemState? state,
    bool withText = true,
  }) async {
    final item = KnowledgeItem(
      id: 'item-1',
      title: 'El Imperio romano',
      source: Source(
        id: 'src-1',
        kind: kind,
        capturedAt: now,
        url: kind == SourceKind.manualNote ? null : 'https://ejemplo.org/1',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [if (withText) _text('item-1', now)],
    );
    await harness.container.read(libraryRepositoryProvider).save(item);
    if (state != null) {
      await harness.container
          .read(inboxRepositoryProvider)
          .transitionState(itemId: item.id, to: state);
    }
    return item.id;
  }

  Future<void> pumpDetail(WidgetTester tester, String id) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(ItemDetailScreen(itemId: id)));
    await tester.pumpAndSettle();
  }

  Future<ItemState> stateOf(String id) async {
    final row = await (harness.database.select(
      harness.database.knowledgeEntries,
    )..where((e) => e.id.equals(id))).getSingle();
    return row.state;
  }

  /// «11 sept»: el día y el mes, como lo escribe el chip en este año.
  String day(DateTime at) => DateFormat.MMMd('es').format(at);

  testWidgets('una fuente triada dice cuándo, y vuelve a la Bandeja', (
    tester,
  ) async {
    final id = await seed(state: ItemState.triaged);
    await pumpDetail(tester, id);

    expect(find.text(es.inboxStandingTriagedOn(day(now))), findsOneWidget);

    await tester.tap(find.text(es.inboxBackToInbox));
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.processed);
    expect(find.text(es.inboxStandingPending), findsOneWidget);
    expect(find.text(es.inboxTriageNow), findsOneWidget);
    expect(
      find.text(es.inboxBackToInboxSnack('El Imperio romano')),
      findsOneWidget,
    );
  });

  testWidgets('lo triado sin texto lo dice, pero no ofrece volver a la '
      'Bandeja: a ella solo entra lo que tiene texto (F30, decisión 68)', (
    tester,
  ) async {
    final id = await seed(state: ItemState.triaged, withText: false);
    await pumpDetail(tester, id);

    expect(find.text(es.inboxStandingTriagedOn(day(now))), findsOneWidget);
    expect(find.text(es.inboxBackToInbox), findsNothing);
  });

  testWidgets('una fuente que todavía no tiene texto no está en la Bandeja: '
      'sin chip ni «Triar ahora»', (tester) async {
    final id = await seed(withText: false);
    await pumpDetail(tester, id);

    expect(find.byKey(const Key('inbox-standing-chip')), findsNothing);
    expect(find.text(es.inboxTriageNow), findsNothing);
  });

  testWidgets('una descartada lo dice, también con la fecha', (tester) async {
    final id = await seed(state: ItemState.discarded);
    await pumpDetail(tester, id);

    expect(find.text(es.inboxStandingDiscardedOn(day(now))), findsOneWidget);
    expect(find.text(es.inboxBackToInbox), findsOneWidget);
  });

  testWidgets('una pendiente está «En la Bandeja», y «Triar ahora» la abre '
      'arriba del mazo', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Otra que espera desde antes: sin elegirla, el mazo empezaría por esa.
    final waiting = KnowledgeItem(
      id: 'item-0',
      title: 'La que espera desde antes',
      source: Source(
        id: 'src-0',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/0',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now.subtract(const Duration(days: 1)),
      renditions: [_text('item-0', now)],
    );
    await harness.container.read(libraryRepositoryProvider).save(waiting);
    final id = await seed();
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.goTo(RoutePaths.itemDetail(id));
    await tester.pumpAndSettle();

    expect(find.text(es.inboxStandingPending), findsOneWidget);
    expect(find.text(es.inboxBackToInbox), findsNothing);

    await tester.tap(find.text(es.inboxTriageNow));
    await tester.pumpAndSettle();

    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.text('El Imperio romano'), findsOneWidget);
    expect(find.text('La que espera desde antes'), findsNothing);
  });

  testWidgets('una nota no pasa por la Bandeja: no hay chip', (tester) async {
    final id = await seed(kind: SourceKind.manualNote);
    await pumpDetail(tester, id);

    expect(find.byKey(const Key('inbox-standing-chip')), findsNothing);
  });
}
