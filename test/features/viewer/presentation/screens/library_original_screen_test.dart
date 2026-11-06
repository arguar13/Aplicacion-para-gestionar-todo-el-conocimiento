import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_view.dart';
import 'package:sinapsis/features/viewer/presentation/screens/library_original_screen.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';

import '../../../../support/library_harness.dart';
import '../../../processed/presentation/processed_ui_fixture.dart';

/// El original de un elemento de la Biblioteca con su propia dirección (F46,
/// paso 5c): lo que abre «Abrir en el original» del Índice sin copia en
/// Procesado. Es el mismo original que «Ver la página» abre desde el detalle,
/// y además se abre en un lugar.
void main() {
  late LibraryHarness harness;

  setUp(() async => harness = await LibraryHarness.create());

  testWidgets('una página web: la dirección lleva el título, y la página '
      'archivada se abre en él, en el original de siempre', (tester) async {
    await harness.saveTextSource(
      'pagina',
      title: 'Una página',
      originalName: 'pagina.html',
    );
    await pumpApp(tester, harness);
    await pushAndSettle(
      tester,
      harness,
      RoutePaths.libraryOriginal(
        'pagina',
        heading: 'Las guerras púnicas',
        occurrence: 1,
      ),
    );

    final screen = tester.widget<LibraryOriginalScreen>(
      find.byType(LibraryOriginalScreen),
    );
    expect(screen.itemId, 'pagina');
    expect(screen.heading, (title: 'Las guerras púnicas', occurrence: 1));
    expect(find.byType(OriginalScreen), findsOneWidget);
    final view = tester.widget<OriginalView>(find.byType(OriginalView));
    expect(view.format, OriginalFormat.page);
    expect(view.initialPage, isNull);
    expect(
      tester.widget<WebPageViewerView>(find.byType(WebPageViewerView)).heading,
      (title: 'Las guerras púnicas', occurrence: 1),
    );

    // Sin lugar, desde arriba.
    await pushAndSettle(tester, harness, RoutePaths.libraryOriginal('pagina'));
    final plain = tester.widget<LibraryOriginalScreen>(
      find.byType(LibraryOriginalScreen).last,
    );
    expect(plain.page, isNull);
    expect(plain.heading, isNull);
  });

  testWidgets('la página de un PDF va en la dirección', (tester) async {
    await pumpApp(tester, harness);
    await pushAndSettle(
      tester,
      harness,
      RoutePaths.libraryOriginal('libro', page: 12),
    );
    final screen = tester.widget<LibraryOriginalScreen>(
      find.byType(LibraryOriginalScreen),
    );
    expect(screen.page, 12);
    expect(screen.heading, isNull);
  });

  testWidgets('un elemento que ya no está, o sin un original que se lea, lo '
      'dice', (tester) async {
    await harness.saveTextSource('audio', kind: SourceKind.audio);
    await pumpApp(tester, harness);

    await pushAndSettle(tester, harness, RoutePaths.libraryOriginal('nada'));
    expect(find.byKey(const Key('library-original-missing')), findsOneWidget);

    await pushAndSettle(tester, harness, RoutePaths.libraryOriginal('audio'));
    expect(
      find.byKey(const Key('library-original-missing'), skipOffstage: false),
      findsNWidgets(2),
    );
    expect(find.byType(OriginalScreen), findsNothing);
  });
}
