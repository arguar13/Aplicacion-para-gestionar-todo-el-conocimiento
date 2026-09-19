import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/notes/domain/entities/cited_source.dart';
import 'package:sinapsis/features/notes/presentation/providers/note_sources_providers.dart';
import 'package:sinapsis/features/notes/presentation/widgets/cited_sources_section.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// De dónde sale lo que dice una nota: las fuentes que cita, cada una con la
/// manera en que la cita y, para las que salieron de notas atómicas, el lugar
/// exacto.
void main() {
  final es = AppLocalizationsEs();

  CitedSource source(
    String id, {
    String? title,
    SourceKind kind = SourceKind.webPage,
    bool direct = false,
    List<CitedFragment> fragments = const [],
  }) => CitedSource(
    sourceId: id,
    title: title ?? 'Fuente $id',
    sourceKind: kind,
    isDirect: direct,
    fragments: fragments,
  );

  CitedFragment fragment(
    String noteId, {
    int? start,
    int? end,
    int? ms,
    int? page,
  }) => CitedFragment(
    noteId: noteId,
    noteTitle: 'Nota $noteId',
    start: start,
    end: end,
    startMs: ms,
    pageNumber: page,
  );

  Future<void> pumpSection(
    WidgetTester tester,
    List<CitedSource> sources,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          citedSourcesProvider.overrideWith(
            (ref, noteId) => Stream.value(sources),
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(
                  body: SingleChildScrollView(
                    child: CitedSourcesSection(noteId: 'viva'),
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
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin fuentes citadas no dibuja nada', (tester) async {
    await pumpSection(tester, const []);

    expect(find.textContaining(es.citedSourcesTitle), findsNothing);
  });

  testWidgets('el encabezado cuenta las fuentes', (tester) async {
    await pumpSection(tester, [
      source('a', direct: true),
      source('b', direct: true),
    ]);

    expect(find.text('${es.citedSourcesTitle} (2)'), findsOneWidget);
    expect(find.text('Fuente a'), findsOneWidget);
    expect(find.text('Fuente b'), findsOneWidget);
  });

  group('cómo se cita', () {
    testWidgets('directamente', (tester) async {
      await pumpSection(tester, [source('a', direct: true)]);

      expect(find.text(es.citedSourceDirect), findsOneWidget);
    });

    testWidgets('a través de una atómica', (tester) async {
      await pumpSection(tester, [
        source('a', fragments: [fragment('n1')]),
      ]);

      expect(find.text(es.citedSourceViaNotes(1)), findsOneWidget);
    });

    testWidgets('a través de varias', (tester) async {
      await pumpSection(tester, [
        source('a', fragments: [fragment('n1'), fragment('n2')]),
      ]);

      expect(find.text(es.citedSourceViaNotes(2)), findsOneWidget);
    });

    testWidgets('de las dos maneras a la vez', (tester) async {
      await pumpSection(tester, [
        source('a', direct: true, fragments: [fragment('n1'), fragment('n2')]),
      ]);

      expect(
        find.text('${es.citedSourceDirect} · ${es.citedSourceViaNotes(2)}'),
        findsOneWidget,
      );
    });
  });

  group('una fuente citada directamente', () {
    testWidgets('tocarla abre su detalle', (tester) async {
      await pumpSection(tester, [source('a', direct: true)]);

      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      expect(find.text('detalle de a'), findsOneWidget);
    });
  });

  group('los fragmentos', () {
    testWidgets('se despliegan con la nota que los usa', (tester) async {
      await pumpSection(tester, [
        source('a', fragments: [fragment('n1', start: 10, end: 40)]),
      ]);
      expect(find.text('Nota n1'), findsNothing);

      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      expect(find.text('Nota n1'), findsOneWidget);
    });

    testWidgets('el botón lleva al fragmento exacto de la fuente', (
      tester,
    ) async {
      await pumpSection(tester, [
        source('a', fragments: [fragment('n1', start: 10, end: 40)]),
      ]);
      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(es.relationViewInSource));
      await tester.pumpAndSettle();

      expect(find.text('lectura a 10-40'), findsOneWidget);
    });

    testWidgets('sin posición guardada no hay botón', (tester) async {
      await pumpSection(tester, [
        source('a', fragments: [fragment('n1')]),
      ]);
      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      expect(find.byTooltip(es.relationViewInSource), findsNothing);
    });

    testWidgets('tocar la nota abre su detalle', (tester) async {
      await pumpSection(tester, [
        source('a', fragments: [fragment('n1', start: 1, end: 5)]),
      ]);
      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nota n1'));
      await tester.pumpAndSettle();

      expect(find.text('detalle de n1'), findsOneWidget);
    });

    testWidgets('la fuente sigue a un toque desde adentro', (tester) async {
      await pumpSection(tester, [
        source('a', fragments: [fragment('n1', start: 1, end: 5)]),
      ]);
      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      // El mismo título de la fuente, dentro del desplegado, la abre.
      await tester.tap(find.text('Fuente a').last);
      await tester.pumpAndSettle();

      expect(find.text('detalle de a'), findsOneWidget);
    });
  });

  group('el lugar en la fuente', () {
    testWidgets('un instante se lee en minutos y segundos', (tester) async {
      await pumpSection(tester, [
        source(
          'a',
          kind: SourceKind.youtube,
          fragments: [fragment('n1', start: 1, end: 5, ms: 750000)],
        ),
      ]);
      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      expect(find.text(es.citedFragmentTime('12:30')), findsOneWidget);
    });

    testWidgets('pasada la hora incluye las horas', (tester) async {
      await pumpSection(tester, [
        source(
          'a',
          kind: SourceKind.youtube,
          fragments: [fragment('n1', start: 1, end: 5, ms: 3725000)],
        ),
      ]);
      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      expect(find.text(es.citedFragmentTime('1:02:05')), findsOneWidget);
    });

    testWidgets('el segundo va con dos dígitos', (tester) async {
      await pumpSection(tester, [
        source('a', fragments: [fragment('n1', start: 1, end: 5, ms: 65000)]),
      ]);
      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      expect(find.text(es.citedFragmentTime('1:05')), findsOneWidget);
    });

    testWidgets('una página se lee como página', (tester) async {
      await pumpSection(tester, [
        source(
          'a',
          kind: SourceKind.document,
          fragments: [fragment('n1', start: 1, end: 5, page: 4)],
        ),
      ]);
      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      expect(find.text(es.citedFragmentPage(4)), findsOneWidget);
    });

    testWidgets('sin instante ni página no dice ningún lugar', (tester) async {
      await pumpSection(tester, [
        source('a', fragments: [fragment('n1', start: 1, end: 5)]),
      ]);
      await tester.tap(find.text('Fuente a'));
      await tester.pumpAndSettle();

      expect(find.textContaining('minuto'), findsNothing);
      expect(find.textContaining('página'), findsNothing);
    });
  });
}
