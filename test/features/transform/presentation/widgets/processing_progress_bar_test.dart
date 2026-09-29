import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue_state.dart';
import 'package:sinapsis/features/transform/presentation/widgets/processing_status.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();

  Future<void> pump(
    WidgetTester tester,
    ProcessingProgress progress, {
    SourceKind? kind,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ProcessingProgressBar(progress: progress, kind: kind),
      ),
    ),
  );

  testWidgets('un documento en el carril largo dice qué página va', (
    tester,
  ) async {
    await pump(
      tester,
      const ProcessingProgress(lane: ProcessingLane.long, done: 12, total: 400),
      kind: SourceKind.document,
    );

    expect(find.text(es.processingRecognizingPages(12, 400)), findsOneWidget);
  });

  testWidgets('un audio o un video en el carril largo dice que se está '
      'transcribiendo', (tester) async {
    await pump(
      tester,
      const ProcessingProgress(lane: ProcessingLane.long, done: 1, total: 4),
      kind: SourceKind.video,
    );

    expect(find.text(es.processingTranscribing(25)), findsOneWidget);
  });

  testWidgets('cualquier otro trabajo dice el porcentaje', (tester) async {
    await pump(
      tester,
      const ProcessingProgress(done: 1, total: 4),
      kind: SourceKind.webPage,
    );

    expect(find.text(es.processingProgressLabel(25)), findsOneWidget);
  });

  testWidgets('esperando turno lo dice, sin avance', (tester) async {
    await pump(
      tester,
      const ProcessingProgress(lane: ProcessingLane.waitingForLong),
      kind: SourceKind.document,
    );

    expect(find.text(es.processingWaitingForLongDetail), findsOneWidget);
  });
}
