import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/presentation/widgets/citation_section.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();

  final item = KnowledgeItem(
    id: 'item-1',
    title: 'La estructura de las revoluciones científicas',
    source: Source(
      id: 'source-1',
      kind: SourceKind.webPage,
      capturedAt: DateTime(2026, 9, 14),
      authorName: 'Thomas Kuhn',
      url: 'https://ejemplo.org/kuhn',
      publishedAt: DateTime(1962),
    ),
    processingState: ProcessingState.ready,
    createdAt: DateTime(2026, 9, 14),
    updatedAt: DateTime(2026, 9, 14),
  );

  Future<void> pumpCitation(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: CitationSection(item: item)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('arranca en APA, con el autor y el año', (tester) async {
    await pumpCitation(tester);

    expect(find.textContaining('Thomas Kuhn'), findsOneWidget);
    expect(find.textContaining('(1962)'), findsOneWidget);
  });

  testWidgets('cambiar a MLA reformatea la misma cita', (tester) async {
    await pumpCitation(tester);

    await tester.tap(find.text('MLA'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        '"La estructura de las revoluciones científicas."',
      ),
      findsOneWidget,
    );
  });

  testWidgets('copiar la cita avisa con un snackbar', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpCitation(tester);

    await tester.tap(find.text(es.citationCopyAction));
    await tester.pumpAndSettle();

    expect(find.text(es.citationCopied), findsOneWidget);
  });
}
