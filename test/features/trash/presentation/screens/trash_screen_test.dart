import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/repositories/study_creation_repository.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/trash/presentation/screens/trash_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La pantalla de la papelera (F11), contra una base real: lo que el usuario
/// borró, con cómo recuperarlo y cómo borrarlo de verdad.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  LibraryRepository repository() =>
      harness.container.read(libraryRepositoryProvider);

  AppDatabase db() => harness.database;

  Future<Map<String, String>> idsByTitle() async => {
    for (final item in (await repository().list(
      const LibraryQuery(),
    )).getRight().toNullable()!)
      item.title: item.id,
  };

  /// Guarda [titles] y SOLO esos los manda a la papelera; devuelve sus
  /// identificadores por título.
  Future<Map<String, String>> trashed(List<String> titles) async {
    final before = await idsByTitle();
    for (final title in titles) {
      await harness.capture(title);
    }
    final mine = {
      for (final entry in (await idsByTitle()).entries)
        if (!before.containsKey(entry.key)) entry.key: entry.value,
    };
    await repository().deleteMany(mine.values.toList());
    return mine;
  }

  Future<void> pumpTrash(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const TrashScreen()));
    await tester.pumpAndSettle();
  }

  Future<List<KnowledgeEntryRow>> rows() =>
      db().select(db().knowledgeEntries).get();

  group('la papelera vacía', () {
    testWidgets('lo explica y no ofrece vaciarla', (tester) async {
      await pumpTrash(tester);

      expect(find.text(es.trashTitle), findsOneWidget);
      expect(find.text(es.trashEmptyTitle), findsOneWidget);
      expect(find.text(es.trashEmptyBody), findsOneWidget);
      expect(find.byTooltip(es.trashEmptyAction), findsNothing);
    });
  });

  group('lo que hay en ella', () {
    testWidgets('lista cada elemento con cuándo se borró, y lo que hace la '
        'papelera', (tester) async {
      await trashed(['Un artículo sobre Roma']);

      await pumpTrash(tester);

      expect(find.text('Un artículo sobre Roma'), findsOneWidget);
      expect(find.textContaining('Borrado el'), findsOneWidget);
      expect(find.text(es.trashHint), findsOneWidget);
      expect(find.byTooltip(es.trashRestore), findsOneWidget);
      expect(find.byTooltip(es.trashDeleteForever), findsOneWidget);
      expect(find.byTooltip(es.trashEmptyAction), findsOneWidget);
    });

    testWidgets('lo vivo no aparece', (tester) async {
      await harness.capture('Sigue en la biblioteca');
      await trashed(['Se fue a la papelera']);

      await pumpTrash(tester);

      expect(find.text('Se fue a la papelera'), findsOneWidget);
      expect(find.text('Sigue en la biblioteca'), findsNothing);
    });
  });

  group('restaurar', () {
    testWidgets('lo devuelve a la biblioteca y avisa', (tester) async {
      final ids = await trashed(['Para restaurar']);
      await pumpTrash(tester);

      await tester.tap(find.byTooltip(es.trashRestore));
      await tester.pumpAndSettle();

      expect(find.text(es.trashEmptyTitle), findsOneWidget);
      expect(find.text(es.trashRestored), findsOneWidget);
      final listed = (await repository().list(
        const LibraryQuery(),
      )).getRight().toNullable()!;
      expect(listed.map((i) => i.id), [ids['Para restaurar']]);
    });
  });

  group('borrar para siempre', () {
    testWidgets('pide confirmación y, cancelada, no borra nada', (
      tester,
    ) async {
      await trashed(['Se queda']);
      await pumpTrash(tester);

      await tester.tap(find.byTooltip(es.trashDeleteForever));
      await tester.pumpAndSettle();

      expect(
        find.text(es.trashDeleteForeverConfirm('Se queda')),
        findsOneWidget,
      );

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(find.text('Se queda'), findsOneWidget);
      expect(await rows(), hasLength(1));
    });

    testWidgets('confirmado, lo borra de verdad y avisa', (tester) async {
      await trashed(['Para borrar', 'Para conservar']);
      await pumpTrash(tester);

      await tester.tap(find.byTooltip(es.trashDeleteForever).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.trashDeleteForever).last);
      await tester.pumpAndSettle();

      expect(find.text(es.trashDeletedForever), findsOneWidget);
      final left = await rows();
      expect(left, hasLength(1));
    });
  });

  group('vaciar la papelera', () {
    testWidgets('pide confirmación diciendo cuántos son', (tester) async {
      await trashed(['Uno', 'Dos']);
      await pumpTrash(tester);

      await tester.tap(find.byTooltip(es.trashEmptyAction));
      await tester.pumpAndSettle();

      expect(find.text(es.trashEmptyConfirm(2)), findsOneWidget);
    });

    testWidgets('cancelada, no borra nada', (tester) async {
      await trashed(['Uno', 'Dos']);
      await pumpTrash(tester);

      await tester.tap(find.byTooltip(es.trashEmptyAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await rows(), hasLength(2));
    });

    testWidgets('confirmado, borra todo lo que hay en ella y nada más', (
      tester,
    ) async {
      await trashed(['Uno', 'Dos']);
      await harness.capture('Vivo');
      await pumpTrash(tester);

      await tester.tap(find.byTooltip(es.trashEmptyAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.trashEmptyAction).last);
      await tester.pumpAndSettle();

      expect(find.text(es.trashEmptied), findsOneWidget);
      expect(find.text(es.trashEmptyTitle), findsOneWidget);
      final left = await rows();
      expect(left.map((r) => r.title), ['Vivo']);
    });
  });

  group('lo creado en la papelera (F43)', () {
    StudyCreationRepository creations() =>
        harness.container.read(studyCreationRepositoryProvider);

    /// Una creación lista con [title], mandada a la papelera.
    Future<String> trashedCreation(String title) async {
      final created = (await creations().create(
        const CreationRequest(
          kind: StudyCreationKind.mindMap,
          scope: CreationScope.allProcessed(),
          sourceIds: ['doc'],
        ),
      )).getRight().toNullable()!;
      await creations().complete(created.id, title: title, content: '{}');
      await creations().trash(created.id);
      return created.id;
    }

    Future<StudyCreation?> stored(String id) async =>
        (await creations().find(id)).getRight().toNullable();

    testWidgets('va en su sección, con su tipo y cuándo se borró', (
      tester,
    ) async {
      await trashed(['Un artículo']);
      await trashedCreation('Éxodo: Liberación y Alianza');

      await pumpTrash(tester);

      expect(find.text('Un artículo'), findsOneWidget);
      expect(find.text(es.f43DataTrashCreationsTitle), findsOneWidget);
      expect(find.text('Éxodo: Liberación y Alianza'), findsOneWidget);
      expect(
        find.textContaining(es.f43DataKindMindMap),
        findsOneWidget,
        reason: 'el tipo, junto a cuándo se borró',
      );
      expect(find.byTooltip(es.trashRestore), findsNWidgets(2));
    });

    testWidgets('sola, la papelera no se ve vacía, y restaurarla la saca', (
      tester,
    ) async {
      final id = await trashedCreation('Para restaurar');
      await pumpTrash(tester);
      expect(find.text(es.trashEmptyTitle), findsNothing);

      await tester.tap(find.byTooltip(es.trashRestore));
      await tester.pumpAndSettle();

      expect(find.text(es.f43DataTrashRestored), findsOneWidget);
      expect(find.text(es.trashEmptyTitle), findsOneWidget);
      expect((await stored(id))!.isTrashed, isFalse);
    });

    testWidgets('borrarla para siempre pide confirmación con su título', (
      tester,
    ) async {
      final id = await trashedCreation('Para borrar');
      await pumpTrash(tester);

      await tester.tap(find.byTooltip(es.trashDeleteForever));
      await tester.pumpAndSettle();
      expect(
        find.text(es.f43DataTrashDeleteForeverConfirm('Para borrar')),
        findsOneWidget,
      );
      await tester.tap(find.text(es.trashDeleteForever).last);
      await tester.pumpAndSettle();

      expect(await stored(id), isNull);
      expect(find.text(es.trashEmptyTitle), findsOneWidget);
    });

    testWidgets('vaciar la papelera se lleva los elementos y las creaciones, '
        'y lo dice', (tester) async {
      await trashed(['Uno']);
      final id = await trashedCreation('Una creación');
      await pumpTrash(tester);

      await tester.tap(find.byTooltip(es.trashEmptyAction));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '${es.trashEmptyConfirm(1)} ${es.f43DataTrashEmptyAlsoCreations(1)}',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(es.trashEmptyAction).last);
      await tester.pumpAndSettle();

      expect(find.text(es.trashEmptyTitle), findsOneWidget);
      expect(await rows(), isEmpty);
      expect(await stored(id), isNull);
    });

    testWidgets('con solo creaciones, la pregunta habla de ellas', (
      tester,
    ) async {
      await trashedCreation('Una');
      await trashedCreation('Otra');
      await pumpTrash(tester);

      await tester.tap(find.byTooltip(es.trashEmptyAction));
      await tester.pumpAndSettle();

      expect(
        find.text(es.f43DataTrashEmptyCreationsConfirm(2)),
        findsOneWidget,
      );
    });

    testWidgets('a lo ancho de un teléfono y con letra grande no se desborda', (
      tester,
    ) async {
      await trashed(['Un artículo con un título bastante largo para la fila']);
      await trashedCreation(
        'Una creación con un título larguísimo que no entra en una línea',
      );
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness.wrap(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: TrashScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(es.f43DataTrashCreationsTitle), findsOneWidget);
    });
  });
}
