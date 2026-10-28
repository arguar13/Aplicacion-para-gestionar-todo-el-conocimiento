import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/presentation/processed_routes.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';

import '../../../support/item_rows.dart';
import '../../../support/library_harness.dart';
import 'processed_ui_fixture.dart';

class _MockProcessedRepository extends Mock implements ProcessedRepository {}

/// Abrir un elemento por su id (F41, paso 2): un documento procesado que llega
/// por `RoutePaths.itemDetail` —desde la búsqueda, el chat, la papelera o el
/// Mapa— abre SU pantalla, y no el detalle de una nota vacía. Se decide en un
/// solo lugar, la ruta del detalle.
void main() {
  group('con el router de verdad', () {
    late LibraryHarness harness;

    setUp(() async {
      harness = await LibraryHarness.create();
      await harness.saveTextSource('roma', title: 'Roma');
    });

    testWidgets('el detalle de un documento procesado abre su pantalla', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await pumpApp(tester, harness);

      await pushAndSettle(tester, harness, RoutePaths.itemDetail(id));

      expect(tester.takeException(), isNull);
      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
      expect(find.byType(ItemDetailScreen), findsNothing);
      final screen = tester.widget<ProcessedDocumentScreen>(
        find.byType(ProcessedDocumentScreen),
      );
      expect(screen.documentId, id);
    });

    testWidgets('también desde una pantalla que está encima del shell, y '
        '«atrás» vuelve a ella', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.trash);

      await pushAndSettle(tester, harness, RoutePaths.itemDetail(id));
      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(ProcessedDocumentScreen), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('uno en la papelera abre su pantalla, que lo dice', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await trashItemRows(harness.database, id);
      await pumpApp(tester, harness);

      await pushAndSettle(tester, harness, RoutePaths.itemDetail(id));

      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
    });

    testWidgets('la fuente sigue abriendo su detalle de siempre', (
      tester,
    ) async {
      await harness.processTextAndNotes('roma');
      await pumpApp(tester, harness);

      await pushAndSettle(tester, harness, RoutePaths.itemDetail('roma'));

      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(find.byType(ProcessedDocumentScreen), findsNothing);
    });
  });

  group('processedDocumentRedirect', () {
    late _MockProcessedRepository repository;

    setUp(() => repository = _MockProcessedRepository());

    test('lleva a la pantalla del procesado si es uno, vivo o en la '
        'papelera', () async {
      for (final status in [
        ProcessedDocumentStatus.active,
        ProcessedDocumentStatus.trashed,
      ]) {
        when(
          () => repository.statusOf('p'),
        ).thenAnswer((_) async => right(status));
        expect(
          await processedDocumentRedirect(repository, 'p'),
          RoutePaths.processedDocument('p'),
        );
      }
    });

    test('deja seguir al detalle si no es un procesado', () async {
      when(
        () => repository.statusOf('x'),
      ).thenAnswer((_) async => right(ProcessedDocumentStatus.absent));
      expect(await processedDocumentRedirect(repository, 'x'), isNull);
    });

    test(
      'si la base falla, abre el detalle igual: mejor eso que nada',
      () async {
        when(() => repository.statusOf('x')).thenAnswer(
          (_) async => left(const Failure.unexpected(message: 'se cayó')),
        );
        expect(await processedDocumentRedirect(repository, 'x'), isNull);
      },
    );
  });
}
