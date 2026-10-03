import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/presentation/screens/capture_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/sample_files.dart';

void main() {
  final es = AppLocalizationsEs();

  CapturedFile pdf({String name = 'La tesis de Ana.pdf'}) => CapturedFile(
    name: name,
    bytes: Uint8List.fromList(utf8.encode('%PDF-1.7 el contenido')),
  );

  Future<void> pumpCapture(WidgetTester tester, LibraryHarness harness) async {
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.pushTo(RoutePaths.capture);
    await tester.pumpAndSettle();
  }

  /// Elige el tipo "Libro o documento". Eso ya dispara el selector de
  /// archivos por su cuenta —ver `_selectKind` en `capture_screen.dart`—, así
  /// que no hace falta tocar ningún botón aparte para el primer intento.
  Future<void> chooseBookType(WidgetTester tester) async {
    final finder = find.text(es.captureTypeBook);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('elegir un archivo', () {
    testWidgets('el nombre, el formato y el peso quedan a la vista', (
      tester,
    ) async {
      // Lo del formato no es decoracion: es el aviso temprano de que un .zip
      // se va a guardar pero no va a dar texto, y de que un .docx renombrado
      // a .txt igual se reconocio bien.
      final harness = await LibraryHarness.create(chosenFile: pdf());
      await pumpCapture(tester, harness);

      await chooseBookType(tester);

      expect(find.text('La tesis de Ana.pdf'), findsOneWidget);
      expect(find.textContaining('PDF'), findsWidgets);
      expect(harness.fileChooser.timesOpened, 1);
    });

    testWidgets('cancelar no deja nada elegido ni muestra un error', (
      tester,
    ) async {
      // Abrir el selector por accidente pasa todo el tiempo: cancelar es la
      // respuesta mas comun, no un fallo.
      final harness = await LibraryHarness.create();
      await pumpCapture(tester, harness);

      await chooseBookType(tester);

      expect(harness.fileChooser.timesOpened, 1);
      expect(find.text(es.captureChooseFileAction), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('la falta de permiso SI se avisa', (tester) async {
      // Pide una accion distinta de cancelar —ir a los ajustes del sistema—
      // y sin el aviso el boton pareceria roto.
      final harness = await LibraryHarness.create(
        fileChooserError: const FileAccessDeniedException(),
      );
      await pumpCapture(tester, harness);

      await chooseBookType(tester);

      expect(find.text(es.captureFileAccessDenied), findsOneWidget);
    });

    testWidgets('se puede quitar y volver a elegir otro', (tester) async {
      final harness = await LibraryHarness.create(chosenFile: pdf());
      await pumpCapture(tester, harness);
      await chooseBookType(tester);

      await tester.tap(find.byTooltip(es.captureFileRemove));
      await tester.pumpAndSettle();

      expect(find.text('La tesis de Ana.pdf'), findsNothing);
      expect(find.text(es.captureChooseFileAction), findsOneWidget);
    });
  });

  group('guardar un archivo', () {
    testWidgets('queda en la biblioteca con su procedencia', (tester) async {
      final harness = await LibraryHarness.create(chosenFile: pdf());
      await pumpCapture(tester, harness);
      await chooseBookType(tester);

      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryScreen), findsOneWidget);

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;

      expect(items, hasLength(1));
      expect(items.single.title, 'La tesis de Ana');
      expect(items.single.source.kind, SourceKind.document);
      // El archivo ES la fuente: sin la copia guardada no habria a que
      // volver.
      expect(items.single.source.originalFilePath, isNotNull);
    });

    testWidgets('entra en la cola para que le saquen el texto', (tester) async {
      final harness = await LibraryHarness.create(chosenFile: pdf());
      await pumpCapture(tester, harness);
      await chooseBookType(tester);

      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, hasLength(1));
    });

    testWidgets('un titulo escrito a mano gana sobre el nombre del archivo', (
      tester,
    ) async {
      final harness = await LibraryHarness.create(
        chosenFile: pdf(name: 'descarga (3).pdf'),
      );
      await pumpCapture(tester, harness);
      await chooseBookType(tester);

      await tester.enterText(
        find.widgetWithText(TextField, es.captureOptionalTitleLabel),
        'La tesis que me paso Ana',
      );
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;

      expect(items.single.title, 'La tesis que me paso Ana');
    });

    testWidgets('un archivo vacio se rechaza con un aviso', (tester) async {
      // Pasa cuando el sistema entrega una ruta que ya caduco.
      final harness = await LibraryHarness.create(
        chosenFile: CapturedFile(name: 'vacio.pdf', bytes: Uint8List(0)),
      );
      await pumpCapture(tester, harness);
      await chooseBookType(tester);

      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(find.byType(CaptureScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('un libro en EPUB se reconoce como tal', (tester) async {
      final harness = await LibraryHarness.create(
        chosenFile: CapturedFile(name: 'libro.epub', bytes: buildEpub()),
      );
      await pumpCapture(tester, harness);

      await chooseBookType(tester);

      expect(find.textContaining('EPUB'), findsWidgets);
    });
  });
}
