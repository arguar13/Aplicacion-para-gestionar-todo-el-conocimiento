import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_standing_line.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La tarjeta «Bandeja» del detalle (F28; F45, mejora 18): lo triado se
/// reencuentra, y desde ahí vuelve a la Bandeja o se vuelve a triar.
///
/// El texto de una fuente lista para triar; desde F41 lo que todavía no lo
/// tiene también está en la Bandeja, esperándolo.
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

  testWidgets('lo triado sin texto también vuelve a la Bandeja: ahí espera '
      'su texto, como lo recién guardado (F41)', (tester) async {
    final id = await seed(state: ItemState.triaged, withText: false);
    await pumpDetail(tester, id);

    expect(find.text(es.inboxStandingTriagedOn(day(now))), findsOneWidget);

    await tester.tap(find.text(es.inboxBackToInbox));
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.processed);
    expect(find.text(es.inboxStandingPending), findsOneWidget);
  });

  testWidgets('una referencia bibliográfica no ofrece volver a la Bandeja: no '
      'trae texto que procesar (decisión E)', (tester) async {
    final id = await seed(kind: SourceKind.reference, withText: false);
    await pumpDetail(tester, id);

    expect(find.byKey(const Key('inbox-standing-card')), findsOneWidget);
    expect(find.text(es.inboxBackToInbox), findsNothing);
    expect(find.text(es.inboxTriageNow), findsNothing);
    // Volver a triarla sí: es lo único que le queda.
    expect(find.byKey(const Key('detail-retriage')), findsOneWidget);
  });

  testWidgets('una fuente que todavía no tiene texto ya está «En la Bandeja», '
      'con «Triar ahora» (F41)', (tester) async {
    final id = await seed(withText: false);
    await pumpDetail(tester, id);

    expect(find.text(es.inboxStandingPending), findsOneWidget);
    expect(find.text(es.inboxTriageNow), findsOneWidget);
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

    // El detalle ya no vive en el shell: al irse a la Bandeja se suelta, y
    // drift cierra sus consultas con un temporizador que hay que dejar correr.
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('una nota no pasa por la Bandeja: no hay tarjeta', (
    tester,
  ) async {
    final id = await seed(kind: SourceKind.manualNote);
    await pumpDetail(tester, id);

    expect(find.byKey(const Key('inbox-standing-card')), findsNothing);
  });

  group('la tarjeta «Bandeja», ordenada (F45, mejora 18)', () {
    final card = find.byKey(const Key('inbox-standing-card'));
    final status = find.byKey(const Key('inbox-standing-status'));
    final retriage = find.byKey(const Key('detail-retriage'));
    final back = find.byKey(const Key('detail-back-to-inbox'));
    final triageNow = find.byKey(const Key('detail-triage-now'));

    /// La tarjeta sola, como la pone el detalle: debajo del título, en una
    /// columna alineada a la izquierda y con sus 24 de margen.
    Future<void> pumpCard(
      WidgetTester tester,
      String id, {
      double width = 900,
      double textScale = 1,
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        harness.wrap(
          Theme(
            data: theme ?? AppTheme.lightTheme,
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('El Imperio romano'),
                    InboxStandingLine(itemId: id, itemTitle: 'El Imperio'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('triada: el estado arriba, y «Volver a triar» relleno al lado '
        'de «Volver a la Bandeja» con borde, del mismo alto', (tester) async {
      final id = await seed(state: ItemState.triaged);
      await pumpCard(tester, id);

      // A todo lo ancho, aunque la columna del detalle alinee a la izquierda.
      expect(tester.getSize(card).width, 900 - 48);
      // El estado, con su ícono, arriba de los botones.
      expect(
        find.descendant(of: status, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: status,
          matching: find.text(es.inboxStandingTriagedOn(day(now))),
        ),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(status).dy,
        lessThan(tester.getTopLeft(retriage).dy),
      );

      // «Volver a triar», el que más se usa, relleno; la Bandeja, con borde.
      expect(tester.widget(retriage), isA<FilledButton>());
      expect(tester.widget(back), isA<OutlinedButton>());
      expect(
        find.descendant(
          of: retriage,
          matching: find.text(es.processedRetriage),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: back, matching: find.text(es.inboxBackToInbox)),
        findsOneWidget,
      );
      // La Bandeja con su ícono, no la flecha de deshacer.
      expect(
        find.descendant(
          of: back,
          matching: find.byIcon(Icons.move_to_inbox_outlined),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.undo), findsNothing);

      // Uno al lado del otro, primero «Volver a triar», del mismo alto y del
      // mismo ancho.
      final left = tester.getRect(retriage);
      final right = tester.getRect(back);
      expect(left.top, right.top);
      expect(left.height, right.height);
      expect(left.width, closeTo(right.width, 0.01));
      expect(left.right, lessThan(right.left));
    });

    testWidgets('lo que espera en la Bandeja tiene un solo botón, «Triar '
        'ahora», a todo lo ancho', (tester) async {
      final id = await seed();
      await pumpCard(tester, id);

      expect(find.text(es.inboxStandingPending), findsOneWidget);
      expect(tester.widget(triageNow), isA<FilledButton>());
      expect(retriage, findsNothing);
      expect(back, findsNothing);
      // El ancho de la tarjeta menos su relleno.
      expect(tester.getSize(triageNow).width, 900 - 48 - 24);
    });

    // La letra de las pruebas es más ancha que la del teléfono —cada letra,
    // un cuadrado—: el ancho en que los nombres van en dos renglones al lado
    // es otro, pero la regla es la misma.
    testWidgets('si cada nombre entra en medio ancho en dos renglones, van al '
        'lado y del mismo alto, sin partir una palabra', (tester) async {
      final id = await seed(state: ItemState.triaged);
      await pumpCard(tester, id, width: 520);

      expect(tester.takeException(), isNull);
      final left = tester.getRect(retriage);
      final right = tester.getRect(back);
      expect(left.top, right.top);
      expect(left.height, right.height);
      expect(left.right, lessThan(right.left));
      expect(right.right, lessThanOrEqualTo(520 - 24 - 12));
      // En dos renglones: más alto que un botón de uno solo.
      final label = find.text(es.inboxBackToInbox);
      expect(
        tester
            .renderObject<RenderParagraph>(label)
            .getMaxIntrinsicWidth(double.infinity),
        greaterThan(tester.getSize(label).width),
      );
    });

    for (final (name, theme) in [
      ('claro', AppTheme.lightTheme),
      ('oscuro', AppTheme.darkTheme),
    ]) {
      testWidgets('a 360 dp con la letra al doble, tema $name: uno debajo del '
          'otro, a lo ancho y sin desbordar', (tester) async {
        final id = await seed(state: ItemState.triaged);
        await pumpCard(tester, id, width: 360, textScale: 2, theme: theme);

        expect(tester.takeException(), isNull);
        final top = tester.getRect(retriage);
        final bottom = tester.getRect(back);
        // «Volver a triar» arriba, y los dos del ancho de la tarjeta.
        expect(top.bottom, lessThan(bottom.top));
        expect(top.width, 360 - 48 - 24);
        expect(bottom.width, top.width);
        expect(tester.getRect(card).right, lessThanOrEqualTo(360 - 24));
        // Ninguna palabra partida: cada nombre, entero en su botón.
        for (final label in [es.processedRetriage, es.inboxBackToInbox]) {
          expect(
            tester.getSize(find.text(label)).width,
            lessThanOrEqualTo(top.width),
            reason: label,
          );
        }
      });
    }

    testWidgets('el lector de pantalla la lee como la tarjeta «Bandeja», con '
        'el estado y cada botón por su lado', (tester) async {
      final handle = tester.ensureSemantics();
      final id = await seed(state: ItemState.triaged);
      await pumpCard(tester, id);

      expect(find.bySemanticsLabel(es.navInbox), findsOneWidget);
      expect(
        find.bySemanticsLabel(es.inboxStandingTriagedOn(day(now))),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(retriage),
        isSemantics(
          label: es.processedRetriage,
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(back),
        isSemantics(
          label: es.inboxBackToInbox,
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
