import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/presentation/index_download.dart';
import 'package:sinapsis/features/index/presentation/providers/index_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/fake_file_saver.dart';
import '../../../support/fake_index_repository.dart';
import 'screens/index_screen_harness.dart';

/// «Descargar el índice» en ⋮ (F46, paso 4): la hoja común con lo que se va a
/// descargar, el PDF y el Markdown de lo que se está mirando —la forma, los
/// niveles, la numeración, lo que se busca—, guardados con el selector de
/// siempre, y lo que se avisa.
void main() {
  final es = AppLocalizationsEs();
  late FakeIndexRepository repo;
  late IndexScreenHarness harness;

  setUp(() {
    repo = FakeIndexRepository();
    harness = IndexScreenHarness(repo);
  });
  tearDown(() => repo.dispose());

  void library() {
    repo.spaces.addAll({'roma': 'Roma', 'egipto': 'Egipto'});
    repo.documents.addAll([
      indexDocument('historia', 'Historia de Roma', spaces: ['roma']),
      indexDocument('cleopatra', 'Cleopatra', spaces: ['roma', 'egipto']),
      indexDocument('suelto', 'Apuntes sueltos'),
    ]);
    repo.entries['historia'] = indexChapters('historia', [
      (1, 'La Monarquía'),
      (2, 'Rómulo'),
      (3, 'La loba'),
      (1, 'La República'),
    ]);
    repo.entries['cleopatra'] = indexChapters(
      'cleopatra',
      [(1, 'La reina')],
      firstKey: 20,
      pdf: true,
    );
    repo.entries['suelto'] = [indexWholeText('suelto', 40)];
  }

  Future<void> openDownload(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('index-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('index-download')));
    await tester.pumpAndSettle();
  }

  Future<String> downloadMarkdown(WidgetTester tester) async {
    await openDownload(tester);
    await tester.tap(find.byKey(const Key('index-download-markdown')));
    await tester.pumpAndSettle();
    return utf8.decode(harness.saver.savedBytes!);
  }

  testWidgets('la hoja dice qué se descarga y ofrece PDF y Markdown', (
    tester,
  ) async {
    library();
    await harness.pump(tester);
    await openDownload(tester);

    expect(find.byKey(const Key('reading-more-sheet')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('reading-more-title'))).data,
      es.f46P4Download,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('reading-more-kind'))).data,
      '${es.f46P3ByTopic} · ${es.f46P4ScopeLevels(3)}',
    );
    expect(find.byKey(const Key('index-download-pdf')), findsOneWidget);
    expect(find.byKey(const Key('index-download-markdown')), findsOneWidget);
  });

  testWidgets('en Markdown, por tema: cada tema con sus documentos —uno con '
      'dos temas bajo los dos— y los capítulos hasta los niveles, aunque los '
      'documentos estén plegados en la pantalla', (tester) async {
    library();
    await harness.pump(tester);
    final markdown = await downloadMarkdown(tester);

    expect(harness.saver.savedFileName, '${es.f46P4FileName('2026-11-05')}.md');
    expect(
      find.text(es.f46P4Saved('${es.f46P4FileName('2026-11-05')}.md')),
      findsOneWidget,
    );
    expect(markdown, startsWith('# ${es.f46P4PrintTitle}\n'));
    expect(markdown, contains('5 de noviembre de 2026'));
    final egipto = markdown.indexOf('\n## Egipto\n');
    final roma = markdown.indexOf('\n## Roma\n');
    expect(egipto, greaterThan(0));
    expect(roma, greaterThan(egipto));
    expect('\n### Cleopatra\n'.allMatches(markdown), hasLength(2));
    expect(markdown, contains('*${es.f46P3AlsoIn('Roma')}*'));
    expect(markdown, contains('- La Monarquía — ${es.f46P3TextPage(1)}'));
    expect(markdown, contains('  - Rómulo — ${es.f46P3TextPage(2)}'));
    expect(markdown, contains('    - La loba — ${es.f46P3TextPage(3)}'));
    expect(markdown, contains('- La reina — ${es.f46P3PdfPage(10)}'));
    expect(markdown, contains('\n## ${es.f46P3Untopiced}\n'));
    expect(markdown, contains('- *${es.f46P3WholeText}*'));
  });

  testWidgets('con «Niveles: 1» y numerado, lo mismo que se ve: sin los '
      'subcapítulos, con su número', (tester) async {
    library();
    await harness.pump(tester);
    harness.container.read(indexViewProvider.notifier)
      ..showDepth(IndexDepth.one)
      ..toggleNumbering();
    await tester.pumpAndSettle();
    final markdown = await downloadMarkdown(tester);

    expect(markdown, contains('- 1 La Monarquía'));
    expect(markdown, contains('- 2 La República'));
    expect(markdown, isNot(contains('Rómulo')));
    expect(
      markdown,
      contains(
        '${es.f46P3ByTopic} · ${es.f46P4ScopeLevels(1)} · '
        '${es.f46P4ScopeNumbered}',
      ),
    );
  });

  testWidgets('por documento: sin temas, cada uno con los suyos', (
    tester,
  ) async {
    library();
    await harness.pump(tester);
    harness.container
        .read(indexViewProvider.notifier)
        .arrange(IndexArrangement.byDocument);
    await tester.pumpAndSettle();
    final markdown = await downloadMarkdown(tester);

    expect(markdown, isNot(contains('\n## Roma\n')));
    expect('\n## Cleopatra\n'.allMatches(markdown), hasLength(1));
    expect(markdown, contains('*${es.f46P3InTopics('Roma, Egipto')}*'));
    expect(markdown, contains(es.f46P4ScopeByTitle));
  });

  testWidgets('buscando: lo que coincide, con los capítulos que lo '
      'contienen', (tester) async {
    library();
    await harness.pump(tester);
    await harness.search(tester, 'loba');
    final markdown = await downloadMarkdown(tester);

    expect(markdown, contains(es.f46P4ScopeSearch('loba')));
    expect(markdown, contains('- La Monarquía'));
    expect(markdown, contains('    - La loba'));
    expect(markdown, isNot(contains('La República')));
    expect(markdown, isNot(contains('Cleopatra')));
  });

  testWidgets('en PDF: un PDF de verdad, con su nombre', (tester) async {
    library();
    await harness.pump(tester);
    await openDownload(tester);
    await tester.tap(find.byKey(const Key('index-download-pdf')));
    await tester.pumpAndSettle();

    final name = '${es.f46P4FileName('2026-11-05')}.pdf';
    expect(harness.saver.savedFileName, name);
    expect(harness.saver.savedBytes!.sublist(0, 5), '%PDF-'.codeUnits);
    expect(
      find.text(es.f46P4Saved('${es.f46P4FileName('2026-11-05')}.pdf')),
      findsOneWidget,
    );
  });

  testWidgets('cancelar el selector no dice nada', (tester) async {
    library();
    harness.saver = FakeFileSaver(path: null);
    await harness.pump(tester);
    await downloadMarkdown(tester);
    expect(harness.saver.savedFileName, '${es.f46P4FileName('2026-11-05')}.md');
    expect(find.text(es.f46P4Working), findsNothing);
    expect(
      find.text(es.f46P4Saved('${es.f46P4FileName('2026-11-05')}.md')),
      findsNothing,
    );
    expect(find.text(es.f46P4DownloadFailed), findsNothing);
  });

  testWidgets('si guardar falla, lo dice', (tester) async {
    library();
    harness.saver.error = Exception('disco lleno');
    await harness.pump(tester);
    await openDownload(tester);
    await tester.tap(find.byKey(const Key('index-download-markdown')));
    await tester.pumpAndSettle();
    expect(find.text(es.f46P4DownloadFailed), findsOneWidget);
  });

  testWidgets('con el Índice vacío, no hay nada para descargar', (
    tester,
  ) async {
    repo.spaces['roma'] = 'Roma';
    await harness.pump(tester);
    await openDownload(tester);
    await tester.tap(find.byKey(const Key('index-download-markdown')));
    await tester.pumpAndSettle();
    expect(harness.saver.savedFileName, isNull);
    expect(find.text(es.f46P4DownloadEmpty), findsOneWidget);
  });

  test('lo que dice la hoja en cada forma', () {
    expect(
      indexDownloadScope(
        es,
        const IndexView(
          arrangement: IndexArrangement.byDocument,
          order: IndexDocumentOrder.recent,
          depth: IndexDepth.all,
        ),
      ),
      '${es.f46P4ScopeByRecent} · ${es.f46P4ScopeAllLevels}',
    );
    expect(
      indexDownloadScope(es, const IndexView(query: 'nicea', numbered: true)),
      es.f46P4ScopeSearch('nicea'),
    );
  });
}
