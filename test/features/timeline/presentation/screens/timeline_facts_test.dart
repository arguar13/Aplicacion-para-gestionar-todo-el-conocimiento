import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_badge.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/timeline/data/repositories/dated_event_repository_impl.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_seed.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/domain/repositories/dated_event_repository.dart';
import 'package:sinapsis/features/timeline/presentation/providers/dated_event_providers.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/dated_event_form.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/document_colors.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/document_legend.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_events_painter.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_frame.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';

/// Los hechos fechados dentro de un documento en la línea de tiempo (F40,
/// pasos 4b y 5): la ficha, los colores por documento y su leyenda, los
/// tramos, la cita al mantener apretado, y agregar un hecho a mano.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  late String lastRoute;

  final now = DateTime(2026, 10, 26, 10);

  const darwinText =
      'Darwin nació en 1809. En 1859 publicó El origen de las especies. '
      'Murió en 1882.';

  setUp(() async {
    harness = await LibraryHarness.create(now: now);
    db = harness.database;
    lastRoute = '';
  });

  DatedEventRepository repo() =>
      harness.container.read(datedEventRepositoryProvider);

  /// Un documento procesado [id] de la fuente `fuente-$id`, que tiene el
  /// texto (F41, paso 6): la línea de tiempo lee lo procesado, y sus citas
  /// están en el original.
  Future<void> seedDoc(
    String id,
    String title, {
    String text = darwinText,
    SourceKind kind = SourceKind.document,
  }) async {
    await insertItemRows(db, id: 'fuente-$id', title: title, kind: kind);
    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'texto-$id',
            itemId: 'fuente-$id',
            kind: RenditionKind.plainText,
            content: Value(text),
            isPrimary: true,
            createdAt: now,
          ),
        );
    await insertProcessedDocument(
      db,
      id: id,
      title: title,
      createdAt: now,
      sourceKind: kind,
      text: text,
    );
    await (db.update(db.processedDocuments)..where((d) => d.itemId.equals(id)))
        .write(ProcessedDocumentsCompanion(sourceItemId: Value('fuente-$id')));
  }

  /// Un elemento con su propia «Fecha del hecho», sin hechos fechados.
  Future<void> seedOwnDate(String id, String title, HistoricalDate date) async {
    await insertProcessedDocument(db, id: id, title: title, createdAt: now);
    final fechaId =
        (await (db.select(db.propertyDefinitions)..where(
                  (d) =>
                      d.isSystem.equals(true) &
                      d.name.equals(kFechaDelHechoCategoryName),
                ))
                .getSingle())
            .id;
    final organize = harness.container.read(organizeRepositoryProvider);
    final value = (await organize.getOrCreateHistoricalPropertyValue(
      definitionId: fechaId,
      date: date,
    )).getRight().toNullable()!;
    await organize.assignProperty(
      itemId: id,
      definitionId: fechaId,
      value: value.value,
    );
  }

  /// Un tema con esos elementos adentro; devuelve su id.
  Future<String> space(String name, List<String> itemIds) async {
    final created =
        (await harness.container
                .read(organizeRepositoryProvider)
                .createSpace(name))
            .getRight()
            .toNullable()!;
    await harness.container
        .read(libraryRepositoryProvider)
        .setSpaces(itemIds: itemIds, spaceIds: {created.id});
    return created.id;
  }

  HistoricalDate year(int y, {bool bce = false}) =>
      HistoricalDate(year: y, precision: DatePrecision.year, isBce: bce);

  /// Un hecho a mano en [docId], con la cita [quote] ubicada en su texto.
  Future<DatedEvent> seedFact(
    String docId,
    String title,
    HistoricalDate date, {
    String? quote,
    HistoricalDate? end,
    String text = darwinText,
  }) async {
    final start = quote == null ? null : text.indexOf(quote);
    final saved = await repo().add(
      docId,
      DatedEventInput(
        title: title,
        date: date,
        end: end,
        renditionId: quote == null ? null : 'texto-$docId',
        startOffset: start,
        endOffset: start == null ? null : start + quote!.length,
        excerpt: quote,
      ),
    );
    return saved.getOrElse((f) => fail('$f'));
  }

  /// Un hecho que puso la IA, con su pasada.
  Future<void> seedAiFact(
    String docId,
    String title,
    HistoricalDate date,
    String quote,
  ) async {
    final run = 'pasada-$title';
    await db
        .into(db.aiRuns)
        .insert(AiRunsCompanion.insert(id: run, itemId: docId, startedAt: now));
    final start = darwinText.indexOf(quote);
    await harness.container
        .read(datedEventRepositoryProvider)
        .addFromAi(
          itemId: docId,
          runId: run,
          drafts: [
            DatedEventInput(
              title: title,
              date: date,
              renditionId: 'texto-$docId',
              startOffset: start,
              endOffset: start + quote.length,
              excerpt: quote,
            ),
          ],
        );
  }

  Widget app({ThemeData? theme, bool inScope = true}) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const TimelineScreen()),
        GoRoute(
          path: RoutePaths.itemDetailPattern,
          builder: (_, state) {
            lastRoute = 'detalle ${state.pathParameters['id']}';
            return Scaffold(body: Text(lastRoute));
          },
        ),
        GoRoute(
          path: RoutePaths.readingPattern,
          builder: (_, state) {
            lastRoute =
                'lectura ${state.pathParameters['id']} '
                '${state.uri.queryParameters['start']}-'
                '${state.uri.queryParameters['end']}';
            return Scaffold(body: Text(lastRoute));
          },
        ),
      ],
    );
    final material = MaterialApp.router(
      theme: theme,
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
    return inScope
        ? UncontrolledProviderScope(
            container: harness.container,
            child: material,
          )
        : material;
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(900, 900),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(theme: theme));
    await tester.pumpAndSettle();
  }

  final canvasKey = find.byKey(const ValueKey('timeline-events'));

  TimelineEventsPainter painterOf(WidgetTester tester) =>
      tester.widget<CustomPaint>(canvasKey).painter! as TimelineEventsPainter;

  TimelineBox boxOf(WidgetTester tester, String title) => painterOf(
    tester,
  ).frame.boxes.singleWhere((box) => box.event.title == title);

  Future<void> tapEvent(WidgetTester tester, String title) => tester.tapAt(
    tester.getTopLeft(canvasKey) + boxOf(tester, title).rect.center,
  );

  /// Los hechos fechados que hay en la base, por título.
  Future<List<DatedEvent>> storedFacts(String docId) async => [
    for (final row
        in await (db.select(db.datedEvents)
              ..where((e) => e.itemId.equals(docId))
              ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
            .get())
      datedEventFromRow(row),
  ];

  Finder byKey(String key) => find.byKey(ValueKey(key));

  group('la ficha de un hecho fechado', () {
    setUp(() async {
      await seedDoc('darwin', 'Darwin, una vida');
      await seedFact(
        'darwin',
        'Publica El origen',
        year(1859),
        quote: 'En 1859 publicó El origen de las especies.',
      );
    });

    testWidgets('tocar el hecho abre su ficha, sin salir de la línea', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tapEvent(tester, 'Publica El origen');
      await tester.pumpAndSettle();

      expect(byKey('dated-event-title'), findsOneWidget);
      expect(
        tester.widget<Text>(byKey('dated-event-title')).data,
        'Publica El origen',
      );
      expect(tester.widget<Text>(byKey('dated-event-date')).data, '1859');
      expect(find.text('Darwin, una vida'), findsOneWidget);
      // Sigue en la línea de tiempo: no navegó a ningún lado.
      expect(lastRoute, isEmpty);
      expect(find.byType(TimelineScreen), findsOneWidget);
    });

    testWidgets('la cita lleva la fecha resaltada, y no depende del color', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tapEvent(tester, 'Publica El origen');
      await tester.pumpAndSettle();

      final quote = tester.widget<SelectableText>(
        find.descendant(
          of: byKey('dated-event-quote'),
          matching: find.byType(SelectableText),
        ),
      );
      final spans = quote.textSpan!.children!.cast<TextSpan>();
      expect(spans.map((s) => s.text), [
        'En ',
        '1859',
        ' publicó El origen de las especies.',
      ]);
      final marked = spans[1].style!;
      expect(byKey('dated-event-quote-lost'), findsNothing);
      expect(marked.fontWeight, FontWeight.w700);
      expect(marked.backgroundColor, isNotNull);
      expect(spans[0].style, isNull);
      expect(spans[2].style, isNull);
    });

    testWidgets('un hecho de la persona no lleva la marca de la IA', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tapEvent(tester, 'Publica El origen');
      await tester.pumpAndSettle();

      expect(find.byType(AiBadge), findsNothing);
    });

    testWidgets('un hecho de la IA lleva ✨', (tester) async {
      await seedAiFact('darwin', 'Nace Darwin', year(1809), 'nació en 1809');
      await pumpScreen(tester);

      await tapEvent(tester, 'Nace Darwin');
      await tester.pumpAndSettle();

      expect(find.byType(AiBadge), findsOneWidget);
      expect(find.byTooltip(es.timelineFactMadeByAi), findsOneWidget);
    });

    testWidgets('«Abrir en el documento» lleva al lector del original justo en '
        'esa cita: la de un procesado está en su fuente (F41)', (tester) async {
      await pumpScreen(tester);
      await tapEvent(tester, 'Publica El origen');
      await tester.pumpAndSettle();

      await tester.tap(byKey('dated-event-open'));
      await tester.pumpAndSettle();

      final start = darwinText.indexOf('En 1859 publicó');
      final end = start + 'En 1859 publicó El origen de las especies.'.length;
      expect(lastRoute, 'lectura fuente-darwin $start-$end');
      // La hoja se fue.
      expect(byKey('dated-event-title'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets(
      'sin ancla no se ofrece abrir el documento, y se dice por qué',
      (tester) async {
        // La cita se copió pero el texto cambió y ya no se ubica.
        await repo().add(
          'darwin',
          DatedEventInput(
            title: 'Zarpa el Beagle',
            date: year(1831),
            excerpt: 'En 1831 zarpó el Beagle.',
          ),
        );
        await pumpScreen(tester);

        await tapEvent(tester, 'Zarpa el Beagle');
        await tester.pumpAndSettle();

        expect(byKey('dated-event-open'), findsNothing);
        expect(byKey('dated-event-quote'), findsOneWidget);
        expect(byKey('dated-event-quote-lost'), findsOneWidget);
        expect(find.text(es.timelineFactQuoteLost), findsOneWidget);
        // Editar y quitar siguen estando.
        expect(byKey('dated-event-edit'), findsOneWidget);
        expect(byKey('dated-event-remove'), findsOneWidget);
      },
    );

    testWidgets('un hecho sin cita no muestra ninguna', (tester) async {
      await seedFact('darwin', 'Muere Darwin', year(1882));
      await pumpScreen(tester);

      await tapEvent(tester, 'Muere Darwin');
      await tester.pumpAndSettle();

      expect(byKey('dated-event-quote'), findsNothing);
      expect(byKey('dated-event-quote-lost'), findsNothing);
      expect(byKey('dated-event-open'), findsNothing);
    });

    testWidgets('el documento se abre desde la ficha', (tester) async {
      await pumpScreen(tester);
      await tapEvent(tester, 'Publica El origen');
      await tester.pumpAndSettle();

      await tester.tap(byKey('dated-event-document'));
      await tester.pumpAndSettle();

      expect(lastRoute, 'detalle darwin');
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('un tramo escribe sus dos fechas', (tester) async {
      await seedFact('darwin', 'Viaje del Beagle', year(1831), end: year(1836));
      await pumpScreen(tester);

      await tapEvent(tester, 'Viaje del Beagle');
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(byKey('dated-event-date')).data,
        '1831 – 1836',
      );
    });

    testWidgets('la ficha de un tramo resalta el rango entero en su cita', (
      tester,
    ) async {
      const war = 'La guerra duró de 1914 a 1918 y cambió Europa.';
      await seedDoc('historia', 'Historia', text: war);
      await seedFact(
        'historia',
        'Primera guerra',
        year(1914),
        end: year(1918),
        quote: war,
        text: war,
      );
      await pumpScreen(tester);

      await tapEvent(tester, 'Primera guerra');
      await tester.pumpAndSettle();

      final quote = tester.widget<SelectableText>(
        find.descendant(
          of: byKey('dated-event-quote'),
          matching: find.byType(SelectableText),
        ),
      );
      expect(quote.textSpan!.children!.cast<TextSpan>().map((s) => s.text), [
        'La guerra duró ',
        'de 1914 a 1918',
        ' y cambió Europa.',
      ]);
    });

    testWidgets('la ficha de un tramo resalta el rango y no la fecha suelta '
        'que lo antecede', (tester) async {
      const war = 'En 1914 empezó; duró de 1914 a 1918 en total.';
      await seedDoc('historia', 'Historia', text: war);
      await seedFact(
        'historia',
        'Primera guerra',
        year(1914),
        end: year(1918),
        quote: war,
        text: war,
      );
      await pumpScreen(tester);

      await tapEvent(tester, 'Primera guerra');
      await tester.pumpAndSettle();

      final quote = tester.widget<SelectableText>(
        find.descendant(
          of: byKey('dated-event-quote'),
          matching: find.byType(SelectableText),
        ),
      );
      expect(quote.textSpan!.children!.cast<TextSpan>().map((s) => s.text), [
        'En 1914 empezó; duró ',
        'de 1914 a 1918',
        ' en total.',
      ]);
    });

    testWidgets('cada hecho es un nodo de semántica, aunque dos compartan '
        'documento y fecha; el de un tramo dice las dos fechas', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await seedFact('darwin', 'Uno', year(1859));
      await seedFact('darwin', 'Otro', year(1859));
      await seedFact('darwin', 'Viaje del Beagle', year(1831), end: year(1836));
      await pumpScreen(tester);

      expect(find.semantics.byLabel('Uno, 1859').evaluate(), hasLength(1));
      expect(find.semantics.byLabel('Otro, 1859').evaluate(), hasLength(1));
      expect(
        find.semantics.byLabel('Viaje del Beagle, 1831 – 1836').evaluate(),
        hasLength(1),
      );

      // Y activar uno abre SU ficha.
      tester.semantics.tap(find.semantics.byLabel('Otro, 1859'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(byKey('dated-event-title')).data, 'Otro');
      semantics.dispose();
    });

    testWidgets('los botones miden lo que un dedo necesita', (tester) async {
      await pumpScreen(tester);
      await tapEvent(tester, 'Publica El origen');
      await tester.pumpAndSettle();

      for (final key in [
        'dated-event-open',
        'dated-event-edit',
        'dated-event-remove',
        'dated-event-document',
      ]) {
        final size = tester.getSize(byKey(key));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
      }
    });

    testWidgets('quitarlo avisa y se puede deshacer', (tester) async {
      await pumpScreen(tester);
      await tapEvent(tester, 'Publica El origen');
      await tester.pumpAndSettle();

      await tester.tap(byKey('dated-event-remove'));
      await tester.pumpAndSettle();

      expect(await storedFacts('darwin'), isEmpty);
      expect(byKey('dated-event-title'), findsNothing);
      expect(
        find.text(es.timelineFactRemoved('Publica El origen')),
        findsOneWidget,
      );

      await tester.tap(find.text(es.timelineFactUndo));
      await tester.pumpAndSettle();

      final back = await storedFacts('darwin');
      expect(back.map((f) => f.title), ['Publica El origen']);
      expect(back.single.excerpt, 'En 1859 publicó El origen de las especies.');
      expect(back.single.hasAnchor, isTrue);
    });

    testWidgets('quitar uno de la IA lo anota como «no era» y deshacer lo '
        'olvida', (tester) async {
      await seedAiFact('darwin', 'Nace Darwin', year(1809), 'nació en 1809');
      await pumpScreen(tester);
      await tapEvent(tester, 'Nace Darwin');
      await tester.pumpAndSettle();

      await tester.tap(byKey('dated-event-remove'));
      await tester.pumpAndSettle();
      expect(await db.select(db.aiRejections).get(), hasLength(1));

      await tester.tap(find.text(es.timelineFactUndo));
      await tester.pumpAndSettle();
      expect(await db.select(db.aiRejections).get(), isEmpty);
      expect(
        (await storedFacts('darwin')).map((f) => f.title),
        contains('Nace Darwin'),
      );
    });

    testWidgets('editarlo abre el formulario con sus datos; guardar lo '
        'cambia', (tester) async {
      await pumpScreen(tester);
      await tapEvent(tester, 'Publica El origen');
      await tester.pumpAndSettle();

      await tester.tap(byKey('dated-event-edit'));
      await tester.pumpAndSettle();

      // La ficha se fue y el formulario abrió con lo que había.
      expect(byKey('dated-event-title'), findsNothing);
      expect(byKey('dated-event-form-heading'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(byKey('dated-event-form-title'))
            .controller!
            .text,
        'Publica El origen',
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, es.datePickerYear),
            )
            .controller!
            .text,
        '1859',
      );
      // El documento no se cambia: la cita es de ese texto.
      expect(find.text('Darwin, una vida'), findsOneWidget);
      expect(find.text(es.timelineFormDocumentFixed), findsOneWidget);
      expect(byKey('dated-event-form-doc-none'), findsNothing);

      await tester.enterText(
        byKey('dated-event-form-title'),
        'Publica su gran obra',
      );
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final facts = await storedFacts('darwin');
      expect(facts.single.title, 'Publica su gran obra');
      // Y se conserva la cita.
      expect(facts.single.hasAnchor, isTrue);
      expect(find.byType(TimelineScreen), findsOneWidget);
    });

    testWidgets('editar un hecho de la IA lo vuelve de la persona', (
      tester,
    ) async {
      await seedAiFact('darwin', 'Nace Darwin', year(1809), 'nació en 1809');
      await pumpScreen(tester);
      await tapEvent(tester, 'Nace Darwin');
      await tester.pumpAndSettle();
      await tester.tap(byKey('dated-event-edit'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '1810',
      );
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final nace = (await storedFacts(
        'darwin',
      )).singleWhere((f) => f.title == 'Nace Darwin');
      expect(nace.origin, ContentOrigin.user);
      expect(nace.aiRunId, isNull);
      expect(nace.date.year, 1810);
    });

    testWidgets('editarlo: se le agrega un fin y se vuelve un tramo', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tapEvent(tester, 'Publica El origen');
      await tester.pumpAndSettle();
      await tester.tap(byKey('dated-event-edit'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(byKey('dated-event-form-range'));
      await tester.tap(byKey('dated-event-form-range'));
      await tester.pumpAndSettle();
      // Dos formularios de fecha: el segundo es el fin.
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear).last,
        '1860',
      );
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final fact = (await storedFacts('darwin')).single;
      expect(fact.date.year, 1859);
      expect(fact.end?.year, 1860);
    });

    testWidgets('«Fecha del hecho» sigue abriendo el elemento', (tester) async {
      // Una fuente con su propia fecha, sin hechos fechados.
      await seedOwnDate('carta', 'Carta de 1810', year(1810));
      await pumpScreen(tester);

      await tapEvent(tester, 'Carta de 1810');
      await tester.pumpAndSettle();

      expect(lastRoute, 'detalle carta');
      expect(byKey('dated-event-title'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('mantener apretado un hecho', () {
    setUp(() async {
      await seedDoc('darwin', 'Darwin, una vida');
      await seedFact(
        'darwin',
        'Publica El origen',
        year(1859),
        quote: 'En 1859 publicó El origen de las especies.',
      );
    });

    testWidgets('muestra su cita y su documento, sin abrir la ficha', (
      tester,
    ) async {
      await pumpScreen(tester);
      final at =
          tester.getTopLeft(canvasKey) +
          boxOf(tester, 'Publica El origen').rect.center;

      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump();

      expect(byKey('timeline-tip'), findsOneWidget);
      expect(
        tester.widget<Text>(byKey('timeline-tip-quote')).data,
        '«En 1859 publicó El origen de las especies.»',
      );
      expect(
        tester.widget<Text>(byKey('timeline-tip-document')).data,
        'Darwin, una vida',
      );
      expect(find.textContaining('Publica El origen\n1859'), findsOneWidget);
      // No abrió la ficha.
      expect(byKey('dated-event-title'), findsNothing);

      // Y dura lo bastante para leerla: a los 5 segundos sigue.
      await tester.pump(const Duration(seconds: 5));
      expect(byKey('timeline-tip'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(byKey('timeline-tip'), findsNothing);
    });

    testWidgets('un tramo escribe sus dos fechas en la ayuda', (tester) async {
      await seedFact('darwin', 'Viaje del Beagle', year(1831), end: year(1836));
      await pumpScreen(tester);
      final at =
          tester.getTopLeft(canvasKey) +
          boxOf(tester, 'Viaje del Beagle').rect.center;

      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump();

      expect(
        find.textContaining('Viaje del Beagle\n1831 – 1836'),
        findsOneWidget,
      );
    });

    testWidgets('un hecho sin cita muestra solo su título y su fecha', (
      tester,
    ) async {
      await seedFact('darwin', 'Muere Darwin', year(1882));
      await pumpScreen(tester);
      final at =
          tester.getTopLeft(canvasKey) +
          boxOf(tester, 'Muere Darwin').rect.center;

      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump();

      expect(byKey('timeline-tip'), findsOneWidget);
      expect(byKey('timeline-tip-quote'), findsNothing);
      expect(find.textContaining('Muere Darwin\n1882'), findsOneWidget);
    });

    testWidgets('pasar de un hecho a otro con el mouse cambia la ayuda', (
      tester,
    ) async {
      await seedFact('darwin', 'Muere Darwin', year(1882));
      await pumpScreen(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      Offset center(String title) =>
          tester.getTopLeft(canvasKey) + boxOf(tester, title).rect.center;

      await tester.sendEventToBinding(mouse.hover(center('Muere Darwin')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Muere Darwin'), findsOneWidget);

      await tester.sendEventToBinding(mouse.hover(center('Publica El origen')));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining('Publica El origen'), findsOneWidget);
      expect(find.textContaining('Muere Darwin'), findsNothing);
      expect(byKey('timeline-tip-quote'), findsOneWidget);
    });

    testWidgets('en una línea baja, si debajo no entra la ayuda va arriba', (
      tester,
    ) async {
      await pumpScreen(tester, size: const Size(900, 420));
      expect(tester.getSize(canvasKey).height, lessThan(200));
      final box = boxOf(tester, 'Publica El origen');
      final at = tester.getTopLeft(canvasKey) + box.rect.center;

      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump();

      final tip = tester.getRect(byKey('timeline-tip'));
      final boxTop = tester.getTopLeft(canvasKey).dy + box.rect.top;
      expect(tip.bottom, lessThanOrEqualTo(boxTop));
    });

    testWidgets('con lugar debajo, la ayuda va debajo', (tester) async {
      await pumpScreen(tester);
      final box = boxOf(tester, 'Publica El origen');
      final at = tester.getTopLeft(canvasKey) + box.rect.center;

      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump();

      final tip = tester.getRect(byKey('timeline-tip'));
      final boxBottom = tester.getTopLeft(canvasKey).dy + box.rect.bottom;
      expect(tip.top, greaterThanOrEqualTo(boxBottom));
    });

    testWidgets('con el mouse, la ayuda también trae la cita', (tester) async {
      await pumpScreen(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final at =
          tester.getTopLeft(canvasKey) +
          boxOf(tester, 'Publica El origen').rect.center;

      await tester.sendEventToBinding(mouse.hover(at));
      await tester.pump(const Duration(milliseconds: 600));

      expect(byKey('timeline-tip-quote'), findsOneWidget);
    });

    testWidgets('un hecho de la «Fecha del hecho» no tiene cita que mostrar', (
      tester,
    ) async {
      await seedOwnDate('carta', 'Carta de 1810', year(1810));
      await pumpScreen(tester);
      final at =
          tester.getTopLeft(canvasKey) +
          boxOf(tester, 'Carta de 1810').rect.center;

      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump();

      expect(byKey('timeline-tip'), findsOneWidget);
      expect(byKey('timeline-tip-quote'), findsNothing);
      expect(byKey('timeline-tip-document'), findsNothing);
    });
  });

  group('los tramos', () {
    testWidgets('se dibujan como tramos, de punta a punta', (tester) async {
      await seedDoc('historia', 'Historia del siglo XX');
      await seedFact('historia', 'Primera guerra', year(1914), end: year(1918));
      await seedFact('historia', 'Estalla la guerra', year(1914));
      await pumpScreen(tester);

      final war = boxOf(tester, 'Primera guerra');
      final point = boxOf(tester, 'Estalla la guerra');

      expect(war.event.barStyle, TimelineBarStyle.range);
      expect(point.event.barStyle, TimelineBarStyle.exact);
      // 1914 a 1918 son cinco años; un año exacto, uno. Mismo comienzo.
      expect(war.corePx / point.corePx, closeTo(5, 0.01));
      expect(war.rect.left, point.rect.left);
    });

    testWidgets('la leyenda explica cómo se ve un tramo', (tester) async {
      await seedDoc('historia', 'Historia del siglo XX');
      await seedFact('historia', 'Primera guerra', year(1914), end: year(1918));
      await pumpScreen(tester);

      expect(find.text(es.timelineLegendRange), findsOneWidget);
    });
  });

  group('colores por documento', () {
    Future<void> three() async {
      await seedDoc('darwin', 'Darwin, una vida');
      await seedDoc('roma', 'Roma antigua');
      await seedDoc('beagle', 'El viaje del Beagle');
      await seedFact('darwin', 'Hecho de Darwin', year(1859));
      await seedFact('roma', 'Hecho de Roma', year(476));
      await seedFact('beagle', 'Hecho del Beagle', year(1831));
    }

    testWidgets('con varios documentos, cada uno con su color', (tester) async {
      await three();
      await pumpScreen(tester);

      final colorOf = painterOf(tester).colorOf!;
      final theme = Theme.of(tester.element(find.byType(TimelineScreen)));
      final colors = DocumentColors(theme);
      expect(
        colorOf(boxOf(tester, 'Hecho de Darwin').event),
        colors.of('darwin'),
      );
      expect(colorOf(boxOf(tester, 'Hecho de Roma').event), colors.of('roma'));
      expect(
        colorOf(boxOf(tester, 'Hecho del Beagle').event),
        colors.of('beagle'),
      );
    });

    testWidgets('con un solo documento, el color de su rol', (tester) async {
      await seedDoc('darwin', 'Darwin, una vida');
      await seedFact('darwin', 'Uno', year(1809));
      await seedFact('darwin', 'Dos', year(1859));
      await pumpScreen(tester);

      expect(painterOf(tester).colorOf, isNull);
      expect(find.byType(TimelineDocumentLegend), findsNothing);
    });

    testWidgets('el color de un documento no cambia al filtrar', (
      tester,
    ) async {
      await three();
      final topic = await space('Biología', ['darwin', 'roma']);
      await pumpScreen(tester);
      final notifier = harness.container.read(timelineFilterProvider.notifier);
      Color romaNow() =>
          painterOf(tester).colorOf!(boxOf(tester, 'Hecho de Roma').event);
      final before = romaNow();

      // Se ven dos de los tres documentos: cada uno sigue con su color.
      notifier.setScope(TimelineScope.topic(spaceId: topic, label: 'Biología'));
      await tester.pumpAndSettle();
      expect(romaNow(), before);
      expect(painterOf(tester).frame.boxes.map((b) => b.event.itemId).toSet(), {
        'darwin',
        'roma',
      });

      // Y al volver a verlos todos, también.
      notifier.clear();
      await tester.pumpAndSettle();
      expect(romaNow(), before);
    });

    testWidgets('con un solo documento a la vista, sin colores por documento', (
      tester,
    ) async {
      await three();
      await pumpScreen(tester);
      expect(painterOf(tester).colorOf, isNotNull);

      harness.container
          .read(timelineFilterProvider.notifier)
          .setScope(
            const TimelineScope.document(itemId: 'roma', label: 'Roma antigua'),
          );
      await tester.pumpAndSettle();

      expect(painterOf(tester).colorOf, isNull);
    });

    testWidgets('otro tema, otro tono: sigue contrastando con el fondo', (
      tester,
    ) async {
      await three();
      await pumpScreen(tester, theme: AppThemeChoice.sepia.theme);
      final sepia = painterOf(tester).colorOf!(
        boxOf(tester, 'Hecho de Roma').event,
      );
      expect(
        documentColorContrast(
          sepia,
          AppThemeChoice.sepia.theme.scaffoldBackgroundColor,
        ),
        greaterThanOrEqualTo(kDocumentColorMinContrast),
      );

      await pumpScreen(tester, theme: AppThemeChoice.night.theme);
      final night = painterOf(tester).colorOf!(
        boxOf(tester, 'Hecho de Roma').event,
      );
      expect(night, isNot(sepia));
      expect(
        documentColorContrast(
          night,
          AppThemeChoice.night.theme.scaffoldBackgroundColor,
        ),
        greaterThanOrEqualTo(kDocumentColorMinContrast),
      );
    });

    testWidgets('la leyenda lista los documentos, plegada de entrada', (
      tester,
    ) async {
      await three();
      await pumpScreen(tester);

      expect(find.byType(TimelineDocumentLegend), findsOneWidget);
      expect(find.text(es.timelineDocsLegendTitle), findsOneWidget);
      expect(find.text(es.timelineDocsLegendCount(3)), findsOneWidget);
      // Plegada: la lista no está.
      expect(byKey('timeline-docs-legend-list'), findsNothing);
      expect(byKey('timeline-docs-legend-darwin'), findsNothing);

      await tester.tap(byKey('timeline-docs-legend-toggle'));
      await tester.pumpAndSettle();

      expect(byKey('timeline-docs-legend-list'), findsOneWidget);
      for (final id in ['darwin', 'roma', 'beagle']) {
        expect(byKey('timeline-docs-legend-$id'), findsOneWidget);
      }
      expect(find.text('Darwin, una vida'), findsOneWidget);
      expect(find.text('Roma antigua'), findsOneWidget);

      // Se vuelve a plegar.
      await tester.tap(byKey('timeline-docs-legend-toggle'));
      await tester.pumpAndSettle();
      expect(byKey('timeline-docs-legend-list'), findsNothing);
    });

    testWidgets('cada fila de la leyenda lleva el color de su documento', (
      tester,
    ) async {
      await three();
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-docs-legend-toggle'));
      await tester.pumpAndSettle();

      final colors = DocumentColors(
        Theme.of(tester.element(find.byType(TimelineScreen))),
      );
      for (final id in ['darwin', 'roma', 'beagle']) {
        final dot = find.descendant(
          of: byKey('timeline-docs-legend-$id'),
          matching: find.byType(Container),
        );
        final decoration =
            tester.widget<Container>(dot.first).decoration! as BoxDecoration;
        expect(decoration.color, colors.of(id), reason: id);
      }
    });

    testWidgets('tocar una fila recorta la línea a ese documento', (
      tester,
    ) async {
      await three();
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-docs-legend-toggle'));
      await tester.pumpAndSettle();

      await tester.tap(byKey('timeline-docs-legend-roma'));
      await tester.pumpAndSettle();

      final scope = harness.container.read(timelineFilterProvider).scope;
      expect(scope?.kind, TimelineScopeKind.document);
      expect(scope?.id, 'roma');
      expect(scope?.label, 'Roma antigua');
      // Con un solo documento, la leyenda se va.
      expect(find.byType(TimelineDocumentLegend), findsNothing);
    });

    testWidgets('la leyenda ordena por cuántos hechos tiene cada documento', (
      tester,
    ) async {
      await three();
      await seedFact('beagle', 'Otro del Beagle', year(1832));
      await seedFact('beagle', 'Y otro más', year(1833));
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-docs-legend-toggle'));
      await tester.pumpAndSettle();

      final order = [
        for (final id in ['beagle', 'darwin', 'roma'])
          tester.getTopLeft(byKey('timeline-docs-legend-$id')).dy,
      ];
      expect(order, [...order]..sort());
      expect(find.text(es.timelineEventCount(3)), findsOneWidget);
    });

    testWidgets('con muchos documentos, la leyenda lista los principales y '
        'dice cuántos faltan', (tester) async {
      const total = kDocumentLegendRows + 3;
      for (var i = 0; i < total; i++) {
        await seedDoc('doc$i', 'Documento $i');
        await seedFact('doc$i', 'Hecho $i', year(1000 + i));
      }
      await pumpScreen(tester, size: const Size(900, 1400));
      await tester.tap(byKey('timeline-docs-legend-toggle'));
      await tester.pumpAndSettle();

      expect(find.text(es.timelineDocsLegendCount(total)), findsOneWidget);
      // Con la misma cantidad de hechos, por título: del 0 al 6 y el 10.
      final list = find.descendant(
        of: byKey('timeline-docs-legend-list'),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        byKey('timeline-docs-legend-more'),
        100,
        scrollable: list,
      );
      expect(
        find.text(es.timelineDocsLegendMore(total - kDocumentLegendRows)),
        findsOneWidget,
      );
      expect(byKey('timeline-docs-legend-doc6'), findsOneWidget);
      expect(byKey('timeline-docs-legend-doc7'), findsNothing);
      expect(byKey('timeline-docs-legend-doc8'), findsNothing);
      expect(byKey('timeline-docs-legend-doc9'), findsNothing);
    });

    testWidgets('las filas de la leyenda miden lo que un dedo necesita', (
      tester,
    ) async {
      await three();
      await pumpScreen(tester);

      expect(
        tester.getSize(byKey('timeline-docs-legend-toggle')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(byKey('timeline-docs-legend-toggle'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(byKey('timeline-docs-legend-roma')).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('«Agregar un hecho»', () {
    testWidgets('es un botón visible, con palabras en una pantalla ancha', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(byKey('timeline-add-fact'), findsOneWidget);
      expect(find.text(es.timelineAddFact), findsWidgets);
    });

    testWidgets('en un teléfono angosto es un botón con ícono y su ayuda', (
      tester,
    ) async {
      await pumpScreen(tester, size: const Size(360, 800));

      expect(byKey('timeline-add-fact'), findsOneWidget);
      expect(find.byTooltip(es.timelineAddFact), findsOneWidget);
      expect(
        tester.getSize(byKey('timeline-add-fact')).shortestSide,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la línea vacía, el botón también está en el centro', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(byKey('timeline-empty-add-fact'), findsOneWidget);
      await tester.tap(byKey('timeline-empty-add-fact'));
      await tester.pumpAndSettle();

      expect(byKey('dated-event-form-heading'), findsOneWidget);
    });

    testWidgets('sin documento, el hecho va a la nota «Hechos sueltos»', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();

      expect(byKey('dated-event-form-heading'), findsOneWidget);
      // Sin documento es lo que viene elegido de entrada.
      expect(
        tester.widget<ChoiceChip>(byKey('dated-event-form-doc-none')).selected,
        isTrue,
      );
      expect(
        find.text(es.timelineFormDocumentLoose(es.timelineFormLooseNoteTitle)),
        findsOneWidget,
      );

      await tester.enterText(
        byKey('dated-event-form-title'),
        'Cae el Muro de Berlín',
      );
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '1989',
      );
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      // La nota se creó y el hecho cuelga de ella.
      final note = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.title.equals(es.timelineFormLooseNoteTitle))).get();
      expect(note, hasLength(1));
      final facts = await storedFacts(note.single.id);
      expect(facts.single.title, 'Cae el Muro de Berlín');
      expect(facts.single.date.year, 1989);
      expect(facts.single.origin, ContentOrigin.user);
      expect(facts.single.hasAnchor, isFalse);

      // Y se ve en la línea, con el aviso.
      expect(find.text(es.timelineFactAdded), findsOneWidget);
      expect(
        boxOf(tester, 'Cae el Muro de Berlín').event.itemId,
        note.single.id,
      );
    });

    testWidgets('el segundo hecho suelto reutiliza la misma nota', (
      tester,
    ) async {
      await pumpScreen(tester);
      for (final (title, y) in [('Uno', '1900'), ('Dos', '1950')]) {
        await tester.tap(byKey('timeline-add-fact'));
        await tester.pumpAndSettle();
        await tester.enterText(byKey('dated-event-form-title'), title);
        await tester.enterText(
          find.widgetWithText(TextField, es.datePickerYear),
          y,
        );
        await tester.tap(byKey('dated-event-form-save'));
        await tester.pumpAndSettle();
      }

      final notes = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.title.equals(es.timelineFormLooseNoteTitle))).get();
      expect(notes, hasLength(1));
      expect(await storedFacts(notes.single.id), hasLength(2));
    });

    testWidgets(
      'con un documento elegido como recorte, viene preseleccionado',
      (tester) async {
        await seedDoc('darwin', 'Darwin, una vida');
        await seedFact('darwin', 'Nace', year(1809));
        harness.container
            .read(timelineFilterProvider.notifier)
            .focusOn(
              const TimelineScope.document(
                itemId: 'darwin',
                label: 'Darwin, una vida',
              ),
            );
        await pumpScreen(tester);

        await tester.tap(byKey('timeline-add-fact'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<ChoiceChip>(byKey('dated-event-form-doc-one')).selected,
          isTrue,
        );
        expect(
          find.descendant(
            of: byKey('dated-event-form-doc-pick'),
            matching: find.text('Darwin, una vida'),
          ),
          findsOneWidget,
        );

        await tester.enterText(byKey('dated-event-form-title'), 'Zarpa');
        await tester.enterText(
          find.widgetWithText(TextField, es.datePickerYear),
          '1831',
        );
        await tester.tap(byKey('dated-event-form-save'));
        await tester.pumpAndSettle();

        expect(
          (await storedFacts('darwin')).map((f) => f.title),
          containsAll(['Nace', 'Zarpa']),
        );
        // Y no se creó ninguna nota de hechos sueltos.
        expect(
          await (db.select(
            db.knowledgeEntries,
          )..where((e) => e.title.equals(es.timelineFormLooseNoteTitle))).get(),
          isEmpty,
        );
      },
    );

    testWidgets('con un tema como recorte, no se preselecciona ningún '
        'documento', (tester) async {
      await seedDoc('darwin', 'Darwin, una vida');
      await seedFact('darwin', 'Nace', year(1809));
      final topic = await space('Biología', ['darwin']);
      harness.container
          .read(timelineFilterProvider.notifier)
          .focusOn(TimelineScope.topic(spaceId: topic, label: 'Biología'));
      await pumpScreen(tester);

      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ChoiceChip>(byKey('dated-event-form-doc-none')).selected,
        isTrue,
      );
    });

    testWidgets('se elige el documento de la lista de la biblioteca', (
      tester,
    ) async {
      await seedDoc('darwin', 'Darwin, una vida');
      await seedDoc('roma', 'Roma antigua');
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();

      await tester.tap(byKey('dated-event-form-doc-one'));
      await tester.pumpAndSettle();
      expect(find.text(es.timelineFormPickDocument), findsOneWidget);

      await tester.tap(byKey('dated-event-form-doc-pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roma antigua'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: byKey('dated-event-form-doc-pick'),
          matching: find.text('Roma antigua'),
        ),
        findsOneWidget,
      );

      await tester.enterText(byKey('dated-event-form-title'), 'Cae Roma');
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '476',
      );
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      expect((await storedFacts('roma')).single.title, 'Cae Roma');
    });

    testWidgets('«Un documento» sin elegir ninguno no se puede guardar', (
      tester,
    ) async {
      await seedDoc('darwin', 'Darwin, una vida');
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('dated-event-form-doc-one'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('dated-event-form-title'), 'Algo');
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '1900',
      );
      // Todavía no se intentó guardar: nada marcado.
      expect(byKey('dated-event-form-document-error'), findsNothing);

      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      expect(byKey('dated-event-form-document-error'), findsOneWidget);
      expect(find.text(es.timelineFormDocumentRequired), findsOneWidget);
      expect(await storedFacts('darwin'), isEmpty);
    });

    testWidgets('un formulario recién abierto no empieza con errores', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();

      expect(find.text(es.timelineFormTitleRequired), findsNothing);
      expect(find.text(es.timelineFormDateMissing), findsNothing);
    });

    testWidgets('sin título ni fecha, dice qué falta en cada campo', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();

      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      expect(find.text(es.timelineFormTitleRequired), findsOneWidget);
      expect(find.text(es.timelineFormDateMissing), findsOneWidget);
      expect(
        await db.select(db.knowledgeEntries).get(),
        isEmpty,
        reason: 'no creó ni la nota',
      );
    });

    testWidgets('un título en blanco es un título que falta', (tester) async {
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('dated-event-form-title'), '   ');
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '1900',
      );

      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      expect(find.text(es.timelineFormTitleRequired), findsOneWidget);
      expect(find.text(es.timelineFormDateMissing), findsNothing);
    });

    testWidgets('un tramo pide el fin, y el fin no puede ser anterior', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('dated-event-form-title'), 'Guerra');
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '1918',
      );
      await tester.ensureVisible(byKey('dated-event-form-range'));
      await tester.tap(byKey('dated-event-form-range'));
      await tester.pumpAndSettle();

      // Sin escribir el fin, al guardar falta.
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();
      expect(find.text(es.timelineFormEndMissing), findsOneWidget);

      // Un fin anterior se avisa apenas se escribe, sin guardar.
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear).last,
        '1914',
      );
      await tester.pumpAndSettle();
      expect(find.text(es.timelineFormEndBeforeStart), findsOneWidget);
      expect(find.text(es.timelineFormEndMissing), findsNothing);
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();
      expect(byKey('dated-event-form-heading'), findsOneWidget);

      // Corregido, se guarda.
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear).last,
        '1919',
      );
      await tester.pumpAndSettle();
      expect(find.text(es.timelineFormEndBeforeStart), findsNothing);
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final note = (await db.select(db.knowledgeEntries).get()).single;
      final fact = (await storedFacts(note.id)).single;
      expect(fact.date.year, 1918);
      expect(fact.end?.year, 1919);
      expect(boxOf(tester, 'Guerra').event.barStyle, TimelineBarStyle.range);
    });

    testWidgets('el fin de un tramo no ofrece «aproximada»: es la del hecho', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();
      expect(find.text(es.datePickerCirca), findsOneWidget);

      await tester.ensureVisible(byKey('dated-event-form-range'));
      await tester.tap(byKey('dated-event-form-range'));
      await tester.pumpAndSettle();

      // Dos formularios de fecha, un solo «aproximada».
      expect(
        find.widgetWithText(TextField, es.datePickerYear),
        findsNWidgets(2),
      );
      expect(find.text(es.datePickerCirca), findsOneWidget);
    });

    testWidgets('un día que no existe no se guarda, y lo dice el campo del '
        'día y no un «falta la fecha»', (tester) async {
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('dated-event-form-title'), 'Algo');
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '2023',
      );
      await tester.tap(find.text(es.datePickerPrecisionDay));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerDay),
        '31',
      );
      // Enero tiene 31 días; abril, 30.
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abril').last);
      await tester.pumpAndSettle();

      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      expect(find.text(es.datePickerDayInvalid(30)), findsOneWidget);
      expect(find.text(es.timelineFormDateMissing), findsNothing);
      expect(await db.select(db.knowledgeEntries).get(), isEmpty);
    });

    testWidgets('una cita mal formada no se guarda y lo dice en general', (
      tester,
    ) async {
      await seedDoc('darwin', 'Darwin, una vida');
      await pumpScreen(tester);
      final context = tester.element(find.byType(TimelineScreen));
      unawaited(
        showDatedEventForm(
          context,
          // Una posición que no es un tramo del texto.
          seed: const DatedEventSeed(
            itemId: 'darwin',
            title: 'Algo',
            renditionId: 'texto-darwin',
            startOffset: 5,
            endOffset: 5,
            excerpt: 'cita',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '1900',
      );

      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      expect(byKey('dated-event-form-error'), findsOneWidget);
      expect(find.text(es.timelineFormInvalid), findsOneWidget);
      expect(await storedFacts('darwin'), isEmpty);
    });

    testWidgets('cancelar cierra sin guardar nada', (tester) async {
      await pumpScreen(tester);
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('dated-event-form-title'), 'Algo');

      await tester.tap(byKey('dated-event-form-cancel'));
      await tester.pumpAndSettle();

      expect(byKey('dated-event-form-heading'), findsNothing);
      expect(find.text(es.timelineFactAdded), findsNothing);
      expect(await db.select(db.knowledgeEntries).get(), isEmpty);
    });

    testWidgets('si no se pudo guardar, lo dice en el formulario y no lo '
        'cierra', (tester) async {
      await seedDoc('darwin', 'Darwin, una vida');
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final failing = ProviderContainer(
        parent: harness.container,
        overrides: [
          datedEventRepositoryProvider.overrideWithValue(_FailingDatedEvents()),
        ],
      );
      addTearDown(failing.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: failing,
          child: app(inScope: false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(byKey('timeline-add-fact'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('dated-event-form-doc-one'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('dated-event-form-doc-pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Darwin, una vida'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('dated-event-form-title'), 'Algo');
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '1900',
      );

      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      expect(byKey('dated-event-form-error'), findsOneWidget);
      expect(find.text(es.globalErrorUnexpected), findsOneWidget);
      expect(byKey('dated-event-form-heading'), findsOneWidget);
      // Se puede volver a intentar: el botón sigue activo.
      expect(
        tester.widget<FilledButton>(byKey('dated-event-form-save')).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}

/// Un repositorio de hechos al que no se le puede agregar nada.
class _FailingDatedEvents implements DatedEventRepository {
  @override
  Stream<List<DatedEvent>> watchForItem(String itemId) =>
      Stream.value(const []);

  @override
  Future<Either<Failure, DatedEvent>> add(
    String itemId,
    DatedEventInput input,
  ) async => left(const Failure.unexpected(message: 'no se pudo'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
