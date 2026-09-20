import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
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
}
