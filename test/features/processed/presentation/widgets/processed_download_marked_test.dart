import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/presentation/providers/marked_download_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_view_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_download_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../processed_ui_fixture.dart';

/// «Descargar con lo marcado» (F38; F45, paso 3): el «Descargar» de la tarjeta
/// «Estudiar el documento» de la Biblioteca, que salió, está en el «Más» del
/// documento procesado, sobre la copia de su original, con la misma hoja.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  const text = 'La república romana cayó. César cruzó el Rubicón.';

  ProcessedOriginal copyOf(String documentId) => ProcessedOriginal(
    documentId: documentId,
    renditionId: 'copia-$documentId',
    relativePath: 'originales/$documentId/original/roma.pdf',
    kind: RenditionKind.pdf,
    sizeBytes: 2048,
    copiedAt: DateTime(2026, 10, 28),
    sourceFilePath: 'originales/roma/roma.pdf',
  );

  final option = find.byKey(const Key('processed-more-downloadMarkedOriginal'));

  /// El documento de «roma» con su copia, cuyo texto se corresponde con el de
  /// la fuente si [matches], en un formato que se sabe marcar si [format].
  Future<String> open(
    WidgetTester tester, {
    bool withCopy = true,
    bool matches = true,
    MarkedDocumentFormat? format = MarkedDocumentFormat.pdf,
  }) async {
    harness = await LibraryHarness.create(
      extraOverrides: [
        processedOriginalProvider.overrideWith(
          (ref, id) => Stream.value(withCopy ? copyOf(id) : null),
        ),
        processedOriginalMarksProvider.overrideWith(
          (ref, id) => Stream.value(null),
        ),
        processedOriginalViewProvider.overrideWith(
          (ref, key) async => (
            path: '/no/existe.pdf',
            exists: true,
            text: matches
                ? (
                    itemId: key.documentId,
                    renditionId: processedOriginalStudyKeyFor(key.documentId),
                    content: text,
                    markdown: false,
                  )
                : null,
          ),
        ),
        markedDownloadFormatProvider.overrideWith(
          (ref, request) async => format,
        ),
      ],
    );
    await harness.saveTextSource('roma', title: 'Roma');
    final id = await harness.processTextAndNotes('roma');
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
    expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('processed-more')));
    await tester.pumpAndSettle();
    return id;
  }

  testWidgets('con la copia marcable, «Más» lo ofrece con lo que hace, y abre '
      'la hoja de siempre sobre la copia', (tester) async {
    final id = await open(tester);

    expect(option, findsOneWidget);
    expect(find.text(es.f45S3DownloadMarked), findsOneWidget);
    expect(find.text(es.f45S3DownloadMarkedHint), findsOneWidget);

    await tester.tap(option);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('study-download-sheet')), findsOneWidget);
    final sheet = tester.widget<StudyDownloadSheet>(
      find.byType(StudyDownloadSheet),
    );
    // Lo que baja es la copia, con lo marcado del procesado.
    expect(
      sheet.item.source.originalFilePath,
      'originales/$id/original/roma.pdf',
    );
    expect(sheet.item.title, 'Roma');
    expect(sheet.text.renditionId, processedOriginalStudyKeyFor(id));
    expect(sheet.format, MarkedDocumentFormat.pdf);
  });

  testWidgets('sin copia no se ofrece', (tester) async {
    await open(tester, withCopy: false);

    expect(option, findsNothing);
  });

  testWidgets('si el texto de la fuente cambió desde la copia, tampoco: no '
      'hay dónde poner lo marcado', (tester) async {
    await open(tester, matches: false);

    expect(option, findsNothing);
  });

  testWidgets('si el formato no se sabe marcar, tampoco', (tester) async {
    await open(tester, format: null);

    expect(option, findsNothing);
  });
}
