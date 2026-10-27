import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_documents.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/document_colors.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/document_legend.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// La leyenda de colores por documento (F40) sola.
void main() {
  final es = AppLocalizationsEs();

  TimelineDocument document(String id, String title, int count) =>
      TimelineDocument(
        itemId: id,
        title: title,
        sourceKind: SourceKind.document,
        noteKind: null,
        eventCount: count,
        firstDate: '1900',
        lastDate: '1950',
      );

  group('qué documentos se listan primero', () {
    test('los de más hechos, y a igual cantidad, por título', () {
      final ordered = legendDocuments([
        document('c', 'Cuaderno', 1),
        document('a', 'Álbum', 1),
        document('z', 'Zeta', 7),
        document('m', 'Mapa', 3),
      ]);

      expect(ordered.map((d) => d.itemId), ['z', 'm', 'a', 'c']);
    });

    test('no toca la lista que recibe', () {
      final input = [document('a', 'A', 1), document('b', 'B', 2)];

      legendDocuments(input);

      expect(input.map((d) => d.itemId), ['a', 'b']);
    });

    test('sin documentos, nada', () {
      expect(legendDocuments(const []), isEmpty);
    });
  });

  group('la leyenda', () {
    late List<TimelineDocument> tapped;

    Future<void> pump(
      WidgetTester tester,
      List<TimelineDocument> documents, {
      bool disableAnimations = false,
    }) async {
      tapped = [];
      final theme = AppThemeChoice.light.theme;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: TimelineDocumentLegend(
                  documents: documents,
                  colors: DocumentColors(theme),
                  onPick: tapped.add,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('plegada muestra el título, cuántos son y una muestra de '
        'colores', (tester) async {
      await pump(tester, [document('a', 'Alfa', 2), document('b', 'Beta', 1)]);

      expect(find.text(es.timelineDocsLegendTitle), findsOneWidget);
      expect(find.text(es.timelineDocsLegendCount(2)), findsOneWidget);
      expect(find.text('Alfa'), findsNothing);
      // Un círculo de color por documento, hasta seis.
      final dots = find.descendant(
        of: find.byKey(const ValueKey('timeline-docs-legend-toggle')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(dots, findsNWidgets(2));
    });

    testWidgets('la muestra plegada no pasa de seis colores', (tester) async {
      await pump(tester, [
        for (var i = 0; i < 10; i++) document('d$i', 'Doc $i', 1),
      ]);

      final dots = find.descendant(
        of: find.byKey(const ValueKey('timeline-docs-legend-toggle')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(dots, findsNWidgets(6));
    });

    testWidgets('el botón dice qué hace y cómo está, para un lector de '
        'pantalla', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, [document('a', 'Alfa', 2)]);

      expect(
        find.bySemanticsLabel(es.timelineDocsLegendExpand),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('timeline-docs-legend-toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(es.timelineDocsLegendCollapse),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('desplegada lista cada documento y tocarlo avisa cuál', (
      tester,
    ) async {
      await pump(tester, [document('a', 'Alfa', 2), document('b', 'Beta', 1)]);
      await tester.tap(
        find.byKey(const ValueKey('timeline-docs-legend-toggle')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alfa'), findsOneWidget);
      expect(find.text(es.timelineEventCount(2)), findsOneWidget);
      expect(find.text(es.timelineEventCount(1)), findsOneWidget);
      expect(find.byTooltip(es.timelineDocsLegendRowTooltip), findsNWidgets(2));
      // Sin «y N más»: entran todos.
      expect(
        find.byKey(const ValueKey('timeline-docs-legend-more')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('timeline-docs-legend-b')));

      expect(tapped.map((d) => d.itemId), ['b']);
    });

    testWidgets('sin animaciones se despliega de golpe', (tester) async {
      await pump(tester, [document('a', 'Alfa', 2)], disableAnimations: true);

      await tester.tap(
        find.byKey(const ValueKey('timeline-docs-legend-toggle')),
      );
      await tester.pump();

      expect(find.text('Alfa'), findsOneWidget);
    });
  });
}
