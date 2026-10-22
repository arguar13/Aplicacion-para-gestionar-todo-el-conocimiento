import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/domain/services/file_viewer_resolver.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/embedded_file_viewer.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Siempre el mismo visor, sin tocar ningún archivo.
class _FixedResolver implements FileViewerResolver {
  _FixedResolver(this.viewer);

  final ResolvedViewer viewer;

  @override
  Future<ResolvedViewer> resolve(KnowledgeItem item) async => viewer;
}

KnowledgeItem _item(SourceKind kind) => KnowledgeItem(
  id: 'item-1',
  title: 'Un documento',
  source: Source(
    id: 'src-1',
    kind: kind,
    capturedAt: DateTime(2026, 10),
    originalFilePath: 'src-1.docx',
  ),
  processingState: ProcessingState.ready,
  createdAt: DateTime(2026, 10),
  updatedAt: DateTime(2026, 10),
);

/// En un documento para leer, el botón de pantalla completa va grande,
/// semitransparente y en el centro, con «Leer como libro» (F35); en una
/// foto queda chico en la esquina.
void main() {
  final es = AppLocalizationsEs();
  final bookButton = find.byKey(const Key('embedded-viewer-read-as-book'));

  Future<void> pump(
    WidgetTester tester, {
    required ResolvedViewer viewer,
    SourceKind kind = SourceKind.document,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // El lector de documentos recuerda el tamaño de letra elegido.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fileViewerResolverProvider.overrideWithValue(_FixedResolver(viewer)),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: EmbeddedFileViewer(item: _item(kind)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const document = TextResolvedViewer(
    '# Capítulo 1\n\nEra una vez un documento largo.',
  );

  testWidgets('un documento muestra «Leer como libro» en el centro del '
      'visor, con las flechas grandes', (tester) async {
    await pump(tester, viewer: document);

    expect(bookButton, findsOneWidget);
    expect(
      find.descendant(of: bookButton, matching: find.text(es.detailReadAsBook)),
      findsOneWidget,
    );
    final arrows = tester.widget<Icon>(
      find.descendant(
        of: bookButton,
        matching: find.byIcon(Icons.open_in_full),
      ),
    );
    expect(arrows.size, greaterThanOrEqualTo(32));

    final frame = find.byType(EmbeddedFileViewer);
    final center = tester.getCenter(bookButton);
    final frameCenter = tester.getCenter(frame);
    expect(center.dx, closeTo(frameCenter.dx, 1));
    expect(center.dy, closeTo(frameCenter.dy, 1));

    // Ni la esquina de antes: un solo botón de expandir.
    expect(find.byIcon(Icons.open_in_full), findsOneWidget);
  });

  testWidgets('el botón es semitransparente: el documento se ve debajo', (
    tester,
  ) async {
    await pump(tester, viewer: document);

    final alpha = tester.widget<Material>(bookButton).color!.a;
    expect(alpha, greaterThan(0));
    expect(alpha, lessThan(0.6));
  });

  testWidgets('tocarlo abre el documento a pantalla completa, como libro', (
    tester,
  ) async {
    await pump(tester, viewer: document);

    await tester.tap(bookButton);
    await tester.pumpAndSettle();

    expect(find.byType(DocumentReaderScreen), findsOneWidget);
  });

  testWidgets('un PDF también lo muestra en el centro', (tester) async {
    await pump(tester, viewer: const PdfResolvedViewer('/no/existe.pdf'));

    expect(bookButton, findsOneWidget);
  });

  testWidgets('una foto deja el botón chico en la esquina, sin «Leer como '
      'libro»', (tester) async {
    await pump(
      tester,
      viewer: const ImageResolvedViewer('/no/existe.jpg'),
      kind: SourceKind.image,
    );

    expect(bookButton, findsNothing);
    expect(find.text(es.detailReadAsBook), findsNothing);
    final corner = find.byIcon(Icons.open_in_full);
    expect(corner, findsOneWidget);
    final frame = tester.getRect(find.byType(EmbeddedFileViewer));
    final button = tester.getCenter(corner);
    expect(button.dx, greaterThan(frame.right - 48));
    expect(button.dy, lessThan(frame.top + 48));
  });
}
