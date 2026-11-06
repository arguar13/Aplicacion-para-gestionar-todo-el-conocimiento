import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/services/index_outline.dart';
import 'package:sinapsis/features/index/presentation/providers/index_providers.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_leader_line.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_index_repository.dart';

/// Las filas del Índice (F46, paso 3), una por una: lo que dicen, lo que lee
/// el lector de pantalla y cómo se ven en los dos temas.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 11, 5, 10);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
    bool disableAnimations = false,
    Map<String, String> topics = const {},
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        indexTopicNamesProvider.overrideWithValue(topics),
      ],
      child: MaterialApp(
        theme: theme,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(body: ListView(children: [child])),
        ),
      ),
    ),
  );

  IndexOutlineRow row(IndexEntry entry, {bool hasChildren = false}) =>
      IndexOutlineRow(entry: entry, hasChildren: hasChildren, unfolded: true);

  group('lo que dice cada entrada', () {
    test('el título: el suyo, «Texto completo» o «Imagen N» por su lugar', () {
      expect(
        indexEntryTitle(es, indexChapters('d', [(1, 'Roma')]).single),
        'Roma',
      );
      expect(indexEntryTitle(es, indexWholeText('d', 1)), es.f46P3WholeText);
      expect(
        indexEntryTitle(es, indexImage('d', 1, position: 4)),
        es.f46P3UntitledImage(5),
      );
      expect(
        indexEntryTitle(es, indexImage('d', 1, position: 4, title: 'Foro')),
        'Foro',
      );
    });

    test('la página: la del PDF si la tiene, si no la del texto; el lugar de '
        'una imagen; nada en «Texto completo» ni sin lugar', () {
      final pdf = indexChapters('d', [(1, 'A')], pdf: true).single;
      final text = indexChapters('d', [(1, 'A')]).single;
      const lost = IndexEntry(
        key: 9,
        documentId: 'd',
        origin: IndexEntryOrigin.bookmark,
        level: 1,
        position: 0,
        title: 'Sin ubicar',
      );

      expect(indexEntryPage(es, pdf), es.f46P3PdfPage(10));
      expect(indexEntryPage(es, text), es.f46P3TextPage(1));
      expect(
        indexEntryPage(es, indexImage('d', 1, position: 2)),
        es.f46P3ImagePlace(3),
      );
      expect(indexEntryPage(es, indexWholeText('d', 1)), isNull);
      expect(indexEntryPage(es, lost), isNull);
    });

    test('lo que oye el lector de pantalla: el nivel, el número si se '
        'numera, el título y la página', () {
      final chapter = indexChapters('d', [(1, 'A'), (2, 'Roma')])[1];

      expect(
        indexEntrySemantics(es, chapter, number: '1.1'),
        '${es.f46P3SemChapter(2, '1.1 Roma')}, ${es.f46P3SemTextPage(2)}',
      );
      expect(
        indexEntrySemantics(es, indexImage('d', 1, position: 0, title: 'Foro')),
        es.f46P3SemImage('Foro', 1),
      );
      expect(
        indexEntrySemantics(es, indexWholeText('d', 1)),
        es.f46P3SemWholeText,
      );
    });
  });

  group('el documento', () {
    testWidgets('sin capítulos pero con imágenes, cuenta sus imágenes', (
      tester,
    ) async {
      await pump(
        tester,
        IndexDocumentRow(
          document: indexDocument('f', 'Fotos', hasText: false, images: 7),
          place: const IndexDocumentPlace.listed(),
          onTap: () {},
        ),
      );

      final count = tester.widget<IndexCount>(find.byType(IndexCount));
      expect(count.count, 7);
      expect(count.tooltip, es.f46P3DocumentImages(7));
    });

    testWidgets('el título en serif y, debajo, «Nuevo», que se indexa y los '
        'temas, en ese orden', (tester) async {
      await pump(
        tester,
        IndexDocumentRow(
          document: indexDocument(
            'd',
            'Historia',
            spaces: ['roma', 'egipto'],
            indexed: false,
            createdAt: now.subtract(const Duration(days: 1)),
          ),
          place: const IndexDocumentPlace.underTopic('roma'),
          onTap: () {},
        ),
        topics: {'roma': 'Roma', 'egipto': 'Egipto'},
      );

      final title = tester.widget<Text>(find.text('Historia'));
      expect(title.style?.fontFamily, 'Lora');
      expect(
        find.text(
          '￼${es.f46P3New} · ${es.f46P3Indexing} · '
          '${es.f46P3AlsoIn('Egipto')}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('un tema que el Índice no conoce no se nombra', (tester) async {
      await pump(
        tester,
        IndexDocumentRow(
          document: indexDocument('d', 'Historia', spaces: ['borrado']),
          place: const IndexDocumentPlace.listed(),
          onTap: () {},
        ),
      );

      expect(find.textContaining(es.f46P3InTopics('')), findsNothing);
    });
  });

  group('el brillo de lo que llega', () {
    testWidgets('brilla un momento y se apaga solo', (tester) async {
      await pump(
        tester,
        IndexGlow(arrivedAt: now, child: const SizedBox(height: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.descendant(
          of: find.byType(IndexGlow),
          matching: find.byType(DecoratedBox),
        ),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(IndexGlow),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    });

    testWidgets('con «sin animaciones», nada', (tester) async {
      await pump(
        tester,
        IndexGlow(arrivedAt: now, child: const SizedBox(height: 40)),
        disableAnimations: true,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.descendant(
          of: find.byType(IndexGlow),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    });

    testWidgets('lo que no llegó recién no brilla', (tester) async {
      await pump(
        tester,
        const IndexGlow(arrivedAt: null, child: SizedBox(height: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.descendant(
          of: find.byType(IndexGlow),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    });
  });

  group('el capítulo', () {
    testWidgets('⌄ solo si tiene capítulos adentro y se puede plegar; tocarlo '
        'pliega, y tocar la fila abre', (tester) async {
      var opened = 0;
      var toggled = 0;
      final entries = indexChapters('d', [(1, 'Parte'), (2, 'Capítulo')]);
      await pump(
        tester,
        Column(
          children: [
            IndexEntryRow(
              row: row(entries.first, hasChildren: true),
              onOpen: () => opened++,
              onToggle: () => toggled++,
            ),
            IndexEntryRow(
              row: row(entries.last),
              onOpen: () => opened++,
              onToggle: () => toggled++,
            ),
          ],
        ),
      );

      expect(find.byKey(const ValueKey('index-fold-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('index-fold-2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('index-fold-1')));
      await tester.tap(find.byType(IndexEntryRow).last);
      expect((toggled, opened), (1, 1));
    });

    for (final (name, theme) in [
      ('claro', AppTheme.lightTheme),
      ('oscuro', AppTheme.darkTheme),
    ]) {
      testWidgets('lo encontrado resaltado contrasta en el tema $name', (
        tester,
      ) async {
        await pump(
          tester,
          IndexEntryRow(
            row: row(indexChapters('d', [(1, 'El Concilio de Nicea')]).single),
            matched: true,
            query: 'nicea',
            onOpen: () {},
          ),
          theme: theme,
        );

        final line = tester.widget<IndexLeaderLine>(
          find.byType(IndexLeaderLine),
        );
        TextStyle? mark;
        line.title.visitChildren((span) {
          if (span is TextSpan && span.text == 'Nicea') mark = span.style;
          return mark == null;
        });
        expect(mark?.backgroundColor, theme.colorScheme.tertiaryContainer);
        expect(mark?.color, theme.colorScheme.onTertiaryContainer);
      });
    }

    testWidgets('un padre de lo encontrado se ve más tenue', (tester) async {
      await pump(
        tester,
        IndexEntryRow(
          row: row(indexChapters('d', [(1, 'Roma')]).single),
          matched: false,
          query: 'roma',
          onOpen: () {},
        ),
        theme: AppTheme.lightTheme,
      );

      final line = tester.widget<IndexLeaderLine>(find.byType(IndexLeaderLine));
      expect(
        line.titleStyle.color,
        AppTheme.lightTheme.colorScheme.onSurfaceVariant,
      );
      // Y no se resalta: no es lo que se buscó.
      var marked = false;
      line.title.visitChildren((span) {
        marked |= span is TextSpan && span.style?.backgroundColor != null;
        return true;
      });
      expect(marked, isFalse);
    });
  });
}
