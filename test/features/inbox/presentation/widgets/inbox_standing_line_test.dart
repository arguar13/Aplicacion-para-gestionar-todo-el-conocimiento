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
import '../../../../support/triage_sheet.dart';

/// Cualquier botón de Material —relleno, tonal, con borde, de texto—:
/// `find.byType` busca el tipo exacto, y cada uno es una subclase.
final Finder _anyButton = find.byWidgetPredicate(
  (widget) => widget is ButtonStyleButton,
  description: 'un botón',
);

/// La tarjeta «Bandeja» del detalle (F28; F45, mejora 18): lo triado se
/// reencuentra, y desde ahí vuelve a la Bandeja o se vuelve a triar. Es el
/// único lugar del detalle que ofrece triar (F45, paso 7c): «Triar ahora» y
/// «Volver a triar» trían ahí mismo, y esperan apagados mientras el texto no
/// llegó.
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

  Future<KnowledgeItem> save(KnowledgeItem item) async {
    final saved = await harness.container
        .read(libraryRepositoryProvider)
        .save(item);
    saved.getOrElse((failure) => throw StateError('$failure'));
    return item;
  }

  /// Una fuente con [state]; sin [withText], con su procesamiento en
  /// [processing]: lo que dice en qué está el texto que le falta.
  Future<KnowledgeItem> seed({
    SourceKind kind = SourceKind.webPage,
    ItemState? state,
    bool withText = true,
    ProcessingState processing = ProcessingState.ready,
  }) async {
    final item = await save(
      KnowledgeItem(
        id: 'item-1',
        title: 'El Imperio romano',
        source: Source(
          id: 'src-1',
          kind: kind,
          capturedAt: now,
          url: kind == SourceKind.manualNote ? null : 'https://ejemplo.org/1',
        ),
        processingState: processing,
        createdAt: now,
        updatedAt: now,
        renditions: [if (withText) _text('item-1', now)],
      ),
    );
    if (state != null) {
      await harness.container
          .read(inboxRepositoryProvider)
          .transitionState(itemId: item.id, to: state);
    }
    return item;
  }

  Future<void> pumpDetail(WidgetTester tester, String id) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(ItemDetailScreen(itemId: id)));
    await tester.pumpAndSettle();
  }

  /// El detalle con el router de verdad, apilado como lo abre la
  /// Biblioteca: lo que hace falta para triar —el aviso, «Ver»— y para ver
  /// que no se va a otra pantalla.
  Future<void> openDetail(WidgetTester tester, String id) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.pushTo(RoutePaths.itemDetail(id));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailScreen), findsOneWidget);
  }

  Future<ItemState> stateOf(String id) async {
    final row = await (harness.database.select(
      harness.database.knowledgeEntries,
    )..where((e) => e.id.equals(id))).getSingle();
    return row.state;
  }

  Future<int> documentCount() async =>
      (await harness.database.select(harness.database.processedDocuments).get())
          .length;

  /// «11 sept»: el día y el mes, como lo escribe el chip en este año.
  String day(DateTime at) => DateFormat.MMMd('es').format(at);

  final retriage = find.byKey(const Key('detail-retriage'));
  final back = find.byKey(const Key('detail-back-to-inbox'));
  final triageNow = find.byKey(const Key('detail-triage-now'));

  /// El botón de [finder], con lo que se le puede pedir.
  ButtonStyleButton button(WidgetTester tester, Finder finder) =>
      tester.widget<ButtonStyleButton>(finder);

  /// La ayuda que acompaña al botón de [finder], o `null` si no tiene.
  String? tooltipOf(WidgetTester tester, Finder finder) {
    final tooltip = find.ancestor(of: finder, matching: find.byType(Tooltip));
    if (tooltip.evaluate().isEmpty) return null;
    return tester.widget<Tooltip>(tooltip.first).message;
  }

  testWidgets('una fuente triada dice cuándo, y vuelve a la Bandeja', (
    tester,
  ) async {
    final item = await seed(state: ItemState.triaged);
    await pumpDetail(tester, item.id);

    expect(find.text(es.inboxStandingTriagedOn(day(now))), findsOneWidget);

    await tester.tap(find.text(es.inboxBackToInbox));
    await tester.pumpAndSettle();

    expect(await stateOf(item.id), ItemState.processed);
    expect(find.text(es.inboxStandingPending), findsOneWidget);
    expect(find.text(es.inboxTriageNow), findsOneWidget);
    expect(
      find.text(es.inboxBackToInboxSnack('El Imperio romano')),
      findsOneWidget,
    );
  });

  testWidgets('lo triado sin texto también vuelve a la Bandeja: ahí espera '
      'su texto, como lo recién guardado (F41); volver a triarla, en cambio, '
      'espera apagado, con su motivo', (tester) async {
    final item = await seed(state: ItemState.triaged, withText: false);
    await pumpDetail(tester, item.id);

    expect(find.text(es.inboxStandingTriagedOn(day(now))), findsOneWidget);
    // Triar necesita el texto; volver a la Bandeja, no: no lleva la guarda.
    expect(button(tester, retriage).onPressed, isNull);
    expect(tooltipOf(tester, retriage), es.inboxTextNeededMissing);
    expect(button(tester, back).onPressed, isNotNull);
    expect(tooltipOf(tester, back), isNull);

    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(await stateOf(item.id), ItemState.processed);
    expect(find.text(es.inboxStandingPending), findsOneWidget);
    expect(button(tester, triageNow).onPressed, isNull);
  });

  testWidgets('una referencia bibliográfica sin texto no ofrece nada: ni '
      'volver a la Bandeja ni triar, porque no trae texto que procesar '
      '(decisión E)', (tester) async {
    final item = await seed(kind: SourceKind.reference, withText: false);
    await pumpDetail(tester, item.id);

    expect(find.byKey(const Key('inbox-standing-card')), findsOneWidget);
    expect(find.text(es.inboxStandingTriagedOn(day(now))), findsOneWidget);
    expect(back, findsNothing);
    expect(triageNow, findsNothing);
    expect(retriage, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('inbox-standing-card')),
        matching: _anyButton,
      ),
      findsNothing,
    );
    expect(find.byTooltip(es.inboxTextNeededMissing), findsNothing);
  });

  testWidgets('una referencia con texto sí se vuelve a triar, aunque no '
      'vuelva a la Bandeja', (tester) async {
    final item = await seed(kind: SourceKind.reference);
    await pumpDetail(tester, item.id);

    expect(back, findsNothing);
    expect(button(tester, retriage).onPressed, isNotNull);
    expect(tooltipOf(tester, retriage), isNull);
  });

  testWidgets('una fuente que todavía no tiene texto ya está «En la Bandeja», '
      'con «Triar ahora» apagado y su motivo; cuando el texto llega, se '
      'prende solo', (tester) async {
    final item = await seed(
      kind: SourceKind.audio,
      withText: false,
      processing: ProcessingState.processing,
    );
    await pumpDetail(tester, item.id);

    expect(find.text(es.inboxStandingPending), findsOneWidget);
    expect(button(tester, triageNow).onPressed, isNull);
    expect(tooltipOf(tester, triageNow), es.inboxTextNeededArriving);

    // Llega la transcripción: el procesamiento la guarda, como siempre.
    await save(
      item.copyWith(
        processingState: ProcessingState.ready,
        renditions: [_text(item.id, now)],
        updatedAt: now.add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(button(tester, triageNow).onPressed, isNotNull);
    expect(tooltipOf(tester, triageNow), isNull);
  });

  testWidgets('si sacarle el texto falló, el motivo lo dice: no llega solo', (
    tester,
  ) async {
    final item = await seed(
      withText: false,
      processing: ProcessingState.failed,
    );
    await pumpDetail(tester, item.id);

    expect(button(tester, triageNow).onPressed, isNull);
    expect(tooltipOf(tester, triageNow), es.inboxTextNeededFailed);
  });

  testWidgets('una descartada lo dice, también con la fecha', (tester) async {
    final item = await seed(state: ItemState.discarded);
    await pumpDetail(tester, item.id);

    expect(find.text(es.inboxStandingDiscardedOn(day(now))), findsOneWidget);
    expect(find.text(es.inboxBackToInbox), findsOneWidget);
    expect(button(tester, retriage).onPressed, isNotNull);
  });

  group('«Triar ahora» tría ahí mismo (F45, paso 7c)', () {
    testWidgets('abre la hoja sin irse del detalle; con «Listo» queda triada '
        'con su documento, y «Deshacer» deshace las dos cosas', (tester) async {
      final item = await seed();
      await openDetail(tester, item.id);

      expect(find.text(es.inboxStandingPending), findsOneWidget);
      expect(back, findsNothing);

      await tester.tap(triageNow);
      await tester.pumpAndSettle();

      // La hoja, en el detalle: ya no lleva a la Bandeja.
      expect(triageSheet, findsOneWidget);
      expect(find.byType(InboxScreen), findsNothing);

      await finishTriageWithText(tester);

      expect(triageSheet, findsNothing);
      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(find.byType(InboxScreen), findsNothing);
      expect(await stateOf(item.id), ItemState.triaged);
      expect(await documentCount(), 1);
      expect(
        find.text(es.processedRetriageTriagedSnack('El Imperio romano')),
        findsOneWidget,
      );
      // La tarjeta ya lo dice, y ofrece lo de lo triado.
      expect(find.text(es.inboxStandingTriagedOn(day(now))), findsOneWidget);
      expect(triageNow, findsNothing);
      expect(retriage, findsOneWidget);

      await tester.tap(find.text(es.inboxUndo));
      await tester.pumpAndSettle();

      expect(await documentCount(), 0);
      expect(await stateOf(item.id), ItemState.processed);
      expect(find.text(es.inboxStandingPending), findsOneWidget);
      expect(triageNow, findsOneWidget);
    });

    testWidgets('cerrar la hoja sin «Listo» la deja como estaba', (
      tester,
    ) async {
      final item = await seed();
      await openDetail(tester, item.id);

      await tester.tap(triageNow);
      await tester.pumpAndSettle();
      expect(triageSheet, findsOneWidget);
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(triageSheet, findsNothing);
      expect(await documentCount(), 0);
      expect(await stateOf(item.id), ItemState.processed);
      expect(find.text(es.inboxStandingPending), findsOneWidget);
    });

    testWidgets('«Volver a triar» abre la misma hoja, también ahí mismo', (
      tester,
    ) async {
      final item = await seed(state: ItemState.discarded);
      await openDetail(tester, item.id);

      await tester.tap(retriage);
      await tester.pumpAndSettle();

      expect(triageSheet, findsOneWidget);
      expect(find.byType(InboxScreen), findsNothing);
    });
  });

  testWidgets('una nota no pasa por la Bandeja: no hay tarjeta', (
    tester,
  ) async {
    final item = await seed(kind: SourceKind.manualNote);
    await pumpDetail(tester, item.id);

    expect(find.byKey(const Key('inbox-standing-card')), findsNothing);
  });

  group('la tarjeta «Bandeja», ordenada (F45, mejora 18)', () {
    final card = find.byKey(const Key('inbox-standing-card'));
    final status = find.byKey(const Key('inbox-standing-status'));

    /// La tarjeta sola, como la pone el detalle: debajo del título, en una
    /// columna alineada a la izquierda y con sus 24 de margen.
    Future<void> pumpCard(
      WidgetTester tester,
      KnowledgeItem item, {
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
                    InboxStandingLine(item: item),
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
      final item = await seed(state: ItemState.triaged);
      await pumpCard(tester, item);

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
      final item = await seed();
      await pumpCard(tester, item);

      expect(find.text(es.inboxStandingPending), findsOneWidget);
      expect(tester.widget(triageNow), isA<FilledButton>());
      expect(button(tester, triageNow).onPressed, isNotNull);
      expect(retriage, findsNothing);
      expect(back, findsNothing);
      // El ancho de la tarjeta menos su relleno.
      expect(tester.getSize(triageNow).width, 900 - 48 - 24);
    });

    testWidgets('una referencia sin texto: solo el estado, sin el espacio de '
        'los botones', (tester) async {
      final item = await seed(kind: SourceKind.reference, withText: false);
      await pumpCard(tester, item);

      // El alto de la tarjeta es el del estado más su relleno.
      expect(tester.getSize(card).height, tester.getSize(status).height + 24);
    });

    // La letra de las pruebas es más ancha que la del teléfono —cada letra,
    // un cuadrado—: el ancho en que los nombres van en dos renglones al lado
    // es otro, pero la regla es la misma.
    testWidgets('si cada nombre entra en medio ancho en dos renglones, van al '
        'lado y del mismo alto, sin partir una palabra', (tester) async {
      final item = await seed(state: ItemState.triaged);
      await pumpCard(tester, item, width: 520);

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
        final item = await seed(state: ItemState.triaged);
        await pumpCard(tester, item, width: 360, textScale: 2, theme: theme);

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

      testWidgets('a 360 dp con la letra al doble, tema $name: «Triar ahora» '
          'apagado, con su motivo, a lo ancho y sin desbordar', (tester) async {
        final item = await seed(
          withText: false,
          processing: ProcessingState.processing,
        );
        await pumpCard(tester, item, width: 360, textScale: 2, theme: theme);

        expect(tester.takeException(), isNull);
        expect(button(tester, triageNow).onPressed, isNull);
        expect(tooltipOf(tester, triageNow), es.inboxTextNeededArriving);
        expect(tester.getSize(triageNow).width, 360 - 48 - 24);
        expect(tester.getRect(card).right, lessThanOrEqualTo(360 - 24));
        expect(
          tester.getSize(find.text(es.inboxTriageNow)).width,
          lessThanOrEqualTo(360 - 48 - 24),
        );
      });
    }

    testWidgets('el lector de pantalla la lee como la tarjeta «Bandeja», con '
        'el estado y cada botón por su lado', (tester) async {
      final handle = tester.ensureSemantics();
      final item = await seed(state: ItemState.triaged);
      await pumpCard(tester, item);

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

    testWidgets('al lector de pantalla, el botón apagado le dice por qué', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final item = await seed(state: ItemState.triaged, withText: false);
      await pumpCard(tester, item);

      expect(
        tester.getSemantics(retriage),
        isSemantics(
          label: es.processedRetriage,
          tooltip: es.inboxTextNeededMissing,
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
      // «Volver a la Bandeja», prendido y sin ayuda: no necesita el texto.
      expect(
        tester.getSemantics(back),
        isSemantics(
          label: es.inboxBackToInbox,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
