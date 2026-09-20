import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/vault/domain/entities/merge_conflict.dart';
import 'package:sinapsis/features/vault/domain/repositories/merge_conflict_repository.dart';
import 'package:sinapsis/features/vault/presentation/providers/merge_conflict_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/merge_conflicts_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// La pantalla de los cambios para revisar (F11): las dos versiones de lo que
/// se cambió en las dos bóvedas, con cuál está en uso y cómo quedarse con una.
class _FakeRepository implements MergeConflictRepository {
  final controller = StreamController<List<MergeConflict>>.broadcast();
  final resolved = <(String, MergeConflictChoice)>[];
  Either<Failure, Unit> result = right(unit);

  @override
  Stream<List<MergeConflict>> watchPending() => controller.stream;

  @override
  Future<Either<Failure, Unit>> resolve(
    String conflictId,
    MergeConflictChoice choice,
  ) async {
    resolved.add((conflictId, choice));
    return result;
  }
}

void main() {
  final es = AppLocalizationsEs();
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());
  tearDown(() => repository.controller.close());

  final at = DateTime(2026, 9, 20, 12);

  MergeConflict conflict({
    String id = 'c1',
    String title = 'La república romana',
    String field = 'title',
    MergeConflictKind kind = MergeConflictKind.field,
    MergeConflictVersion? local,
    MergeConflictVersion? incoming,
    bool inTrash = false,
  }) => MergeConflict(
    id: id,
    itemId: 'a',
    itemTitle: title,
    fieldName: field,
    kind: kind,
    local:
        local ??
        MergeConflictVersion(
          text: 'De tel',
          deviceId: 'telefono-uuid-1',
          at: at,
        ),
    incoming:
        incoming ??
        MergeConflictVersion(
          text: 'De pc',
          deviceId: 'computadora-uuid',
          at: at,
          inUse: true,
        ),
    detectedAt: at,
    itemInTrash: inTrash,
  );

  Future<void> pumpScreen(
    WidgetTester tester,
    List<MergeConflict> conflicts,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mergeConflictRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MergeConflictsScreen(),
        ),
      ),
    );
    repository.controller.add(conflicts);
    await tester.pumpAndSettle();
  }

  group('sin nada para revisar', () {
    testWidgets('lo dice, y explica cuándo aparecerá algo', (tester) async {
      await pumpScreen(tester, const []);

      expect(find.text(es.conflictsTitle), findsOneWidget);
      expect(find.text(es.conflictsEmptyTitle), findsOneWidget);
      expect(find.text(es.conflictsEmptyBody), findsOneWidget);
    });
  });

  group('un conflicto', () {
    testWidgets('el elemento, el campo y las dos versiones', (tester) async {
      await pumpScreen(tester, [conflict()]);

      expect(find.text(es.conflictsIntro), findsOneWidget);
      expect(find.text('La república romana'), findsOneWidget);
      expect(find.text(es.conflictsFieldTitle), findsOneWidget);
      expect(find.text(es.conflictsSideLocal), findsOneWidget);
      expect(find.text(es.conflictsSideIncoming), findsOneWidget);
      expect(find.text('De tel'), findsOneWidget);
      expect(find.text('De pc'), findsOneWidget);
      // Quién la escribió: los primeros caracteres de su identificador.
      expect(find.textContaining('telefono'), findsOneWidget);
      expect(find.textContaining('computad'), findsOneWidget);
    });

    testWidgets('marca cuál está en uso y ofrece conservarla, o usar la otra', (
      tester,
    ) async {
      await pumpScreen(tester, [conflict()]);

      expect(find.text(es.conflictsInUse), findsOneWidget);
      expect(find.text(es.conflictsKeepThis), findsOneWidget);
      expect(find.text(es.conflictsUseThis), findsOneWidget);
    });

    testWidgets('elegir la de acá', (tester) async {
      await pumpScreen(tester, [conflict()]);

      await tester.tap(find.text(es.conflictsUseThis));
      await tester.pumpAndSettle();

      expect(repository.resolved, [('c1', MergeConflictChoice.keepLocal)]);
      expect(find.text(es.conflictsResolved), findsOneWidget);
    });

    testWidgets('elegir la de la otra copia', (tester) async {
      await pumpScreen(tester, [conflict()]);

      await tester.tap(find.text(es.conflictsKeepThis));
      await tester.pumpAndSettle();

      expect(repository.resolved, [('c1', MergeConflictChoice.useIncoming)]);
    });

    testWidgets('si no se pudo guardar, lo dice y no da nada por hecho', (
      tester,
    ) async {
      repository.result = left(const Failure.unexpected(message: 'x'));
      await pumpScreen(tester, [conflict()]);

      await tester.tap(find.text(es.conflictsKeepThis));
      await tester.pumpAndSettle();

      expect(find.text(es.globalErrorUnexpected), findsOneWidget);
      expect(find.text(es.conflictsResolved), findsNothing);
    });

    testWidgets('al resolverlo desaparece de la lista', (tester) async {
      await pumpScreen(tester, [conflict(), conflict(id: 'c2', title: 'Otro')]);
      expect(find.text('Otro'), findsOneWidget);

      repository.controller.add([conflict()]);
      await tester.pumpAndSettle();

      expect(find.text('Otro'), findsNothing);
      expect(find.text('La república romana'), findsOneWidget);
    });

    testWidgets('un elemento en la papelera lo avisa', (tester) async {
      await pumpScreen(tester, [conflict(inTrash: true)]);

      expect(find.text(es.conflictsItemInTrash), findsOneWidget);
    });
  });

  group('«guardar las dos»', () {
    testWidgets('solo en un texto libre', (tester) async {
      await pumpScreen(tester, [conflict(field: 'notes')]);

      expect(find.text(es.conflictsKeepBoth), findsOneWidget);

      await tester.tap(find.text(es.conflictsKeepBoth));
      await tester.pumpAndSettle();

      expect(repository.resolved, [('c1', MergeConflictChoice.keepBoth)]);
    });

    testWidgets('no en un título', (tester) async {
      await pumpScreen(tester, [conflict()]);

      expect(find.text(es.conflictsKeepBoth), findsNothing);
    });
  });

  group('cómo se lee cada valor', () {
    testWidgets('un espacio, por su nombre', (tester) async {
      await pumpScreen(tester, [
        conflict(
          field: 'spaceId',
          local: const MergeConflictVersion(
            text: 'sp-a',
            spaceName: 'Historia',
          ),
          incoming: const MergeConflictVersion(
            text: 'sp-b',
            spaceName: 'Física',
            inUse: true,
          ),
        ),
      ]);

      expect(find.text(es.conflictsFieldSpace), findsOneWidget);
      expect(find.text('Historia'), findsOneWidget);
      expect(find.text('Física'), findsOneWidget);
    });

    testWidgets('la papelera: «en la papelera desde» o «en la biblioteca»', (
      tester,
    ) async {
      await pumpScreen(tester, [
        conflict(
          field: 'deletedAt',
          local: MergeConflictVersion(
            text: '1789000000',
            date: DateTime(2026, 9, 5),
          ),
          incoming: const MergeConflictVersion(inUse: true),
        ),
      ]);

      expect(find.text(es.conflictsFieldDeleted), findsOneWidget);
      expect(find.text(es.conflictsInTrash('2026-09-05')), findsOneWidget);
      expect(find.text(es.conflictsInLibrary), findsOneWidget);
    });

    testWidgets('el estado y el tipo de nota, con su nombre', (tester) async {
      await pumpScreen(tester, [
        conflict(
          field: 'state',
          local: const MergeConflictVersion(text: 'triaged'),
          incoming: const MergeConflictVersion(text: 'discarded', inUse: true),
        ),
        conflict(
          id: 'c2',
          field: 'noteKind',
          local: const MergeConflictVersion(text: 'atomic'),
          incoming: const MergeConflictVersion(text: 'map', inUse: true),
        ),
      ]);

      expect(find.text(es.conflictsStateTriaged), findsOneWidget);
      expect(find.text(es.conflictsStateDiscarded), findsOneWidget);
      expect(find.text(es.noteKindAtomic), findsOneWidget);
      expect(find.text(es.noteKindMap), findsOneWidget);
    });

    testWidgets('un campo vacío', (tester) async {
      await pumpScreen(tester, [
        conflict(
          field: 'subtitle',
          local: const MergeConflictVersion(),
          incoming: const MergeConflictVersion(
            text: 'Un subtítulo',
            inUse: true,
          ),
        ),
      ]);

      expect(find.text(es.conflictsEmptyValue), findsOneWidget);
    });
  });

  group('el texto de una forma', () {
    testWidgets(
      'cada versión con lo que pesa, y el recorte con puntos suspensivos',
      (tester) async {
        await pumpScreen(tester, [
          conflict(
            kind: MergeConflictKind.text,
            field: 'rendition:rend-a',
            local: const MergeConflictVersion(
              text: 'Texto de acá.',
              length: 13,
              inUse: true,
            ),
            incoming: MergeConflictVersion(text: 'x' * 600, length: 5000),
          ),
        ]);

        expect(find.text(es.conflictsFieldText), findsOneWidget);
        expect(find.text('Texto de acá.'), findsOneWidget);
        expect(find.text(es.conflictsTextLength(13)), findsOneWidget);
        expect(find.text(es.conflictsTextLength(5000)), findsOneWidget);
        expect(find.text('${'x' * 600}…'), findsOneWidget);
      },
    );

    testWidgets('una versión que ya no está no se puede elegir', (
      tester,
    ) async {
      await pumpScreen(tester, [
        conflict(
          kind: MergeConflictKind.text,
          field: 'rendition:rend-a',
          local: const MergeConflictVersion(
            text: 'Texto.',
            length: 6,
            inUse: true,
          ),
          incoming: const MergeConflictVersion(),
        ),
      ]);

      expect(find.text(es.conflictsGone), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, es.conflictsUseThis),
      );
      expect(button.onPressed, isNull);
    });
  });
}
