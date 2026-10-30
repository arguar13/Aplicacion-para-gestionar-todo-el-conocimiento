import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/domain/services/file_viewer_resolver.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/image_viewer_screen.dart';
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
/// foto, el mismo, con «Ampliar» (F45, paso 3).
void main() {
  final es = AppLocalizationsEs();
  final bookButton = find.byKey(const Key('embedded-viewer-read-as-book'));

  Future<void> pump(
    WidgetTester tester, {
    required ResolvedViewer viewer,
    SourceKind kind = SourceKind.document,
    Size size = const Size(400, 900),
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = size;
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
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
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

  testWidgets('una página web lo muestra en el centro, con «Ver la página» '
      '(pedido del usuario)', (tester) async {
    await pump(
      tester,
      viewer: const WebPageResolvedViewer('/no/existe.html'),
      kind: SourceKind.webPage,
    );

    expect(bookButton, findsOneWidget);
    expect(
      find.descendant(
        of: bookButton,
        matching: find.text(es.detailViewWebPage),
      ),
      findsOneWidget,
    );
    expect(find.text(es.detailReadAsBook), findsNothing);
  });

  group('una foto (F45, paso 3)', () {
    const photo = ImageResolvedViewer('/no/existe.jpg');

    testWidgets('lleva «Ampliar» en el centro, con la píldora de «Leer como '
        'libro», y nada en la esquina', (tester) async {
      await pump(tester, viewer: photo, kind: SourceKind.image);

      expect(bookButton, findsOneWidget);
      expect(
        find.descendant(of: bookButton, matching: find.text(es.f45S3Enlarge)),
        findsOneWidget,
      );
      expect(find.text(es.detailReadAsBook), findsNothing);
      // Un solo botón de expandir: el del centro.
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);

      final center = tester.getCenter(bookButton);
      final frameCenter = tester.getCenter(find.byType(EmbeddedFileViewer));
      expect(center.dx, closeTo(frameCenter.dx, 1));
      expect(center.dy, closeTo(frameCenter.dy, 1));
    });

    testWidgets('tocar «Ampliar» abre la foto a pantalla completa', (
      tester,
    ) async {
      await pump(tester, viewer: photo, kind: SourceKind.image);

      await tester.tap(find.text(es.f45S3Enlarge));
      await tester.pumpAndSettle();

      expect(find.byType(ImageViewerScreen), findsOneWidget);
    });

    testWidgets('el lector de pantalla lo anuncia como el botón «Ampliar»', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, viewer: photo, kind: SourceKind.image);

      expect(
        tester.getSemantics(find.text(es.f45S3Enlarge)),
        isSemantics(
          label: es.f45S3Enlarge,
          tooltip: es.detailExpandViewer,
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('entra en 360 dp con la letra al doble, en '
          '${themeMode.name}', (tester) async {
        await pump(
          tester,
          viewer: photo,
          kind: SourceKind.image,
          size: const Size(360, 780),
          textScale: 2,
          themeMode: themeMode,
        );

        expect(tester.takeException(), isNull);
        final frame = tester.getRect(find.byType(EmbeddedFileViewer));
        final pill = tester.getRect(bookButton);
        expect(frame.contains(pill.topLeft), isTrue);
        expect(frame.contains(pill.bottomRight), isTrue);
        // El texto blanco sobre el fondo oscuro, también en el tema oscuro.
        final text = tester.widget<Text>(find.text(es.f45S3Enlarge));
        expect(text.style?.color, Colors.white);
      });
    }
  });
}
