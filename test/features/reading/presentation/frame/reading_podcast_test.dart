import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/podcast/podcast_kind.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../creations/presentation/repasar_harness.dart';

/// La ficha «Podcast» de la fila de IA del marco de lectura (F47, paso 1)
/// abre la hoja del podcast (paso 6a) sobre lo que se lee, en la app de
/// verdad con su router: el texto de un documento procesado.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;

  setUp(() async {
    harness = await RepasarHarness.create(specs: [podcastKindSpec()]);
    await harness.processed('p-1', 'Éxodo — Comentario');
    await harness.processed('p-2', 'Génesis');
  });

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('desde el texto de un documento procesado, «Podcast» abre su '
      'hoja sobre ese documento, y lo pedido va a la cola con él', (
    tester,
  ) async {
    await harness.openRepasar(
      tester,
      location: RoutePaths.extractReading(StudyCreationKind.fullText, ['p-2']),
    );
    expect(find.byKey(const Key('reading-frame')), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('reading-ai-podcast')));
    expect(find.text(es.f47P6SheetTitle), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('creation-generate-now')));
    final request = harness.queue.requests.single;
    expect(request.kind, StudyCreationKind.podcast);
    expect(request.scope, const CreationScope.document('p-2'));
    expect(request.sourceIds, ['p-2']);
  });
}
