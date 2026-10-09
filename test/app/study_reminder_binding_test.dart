import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/app/study_reminder_binding.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/presentation/providers/study_reminder_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../support/fake_study_reminder.dart';
import '../support/library_harness.dart';

/// El aviso diario enchufado a la app (F31, ola 2): se reprograma al abrir,
/// cuenta las tarjetas y lleva a Repasar al tocar la notificación.
void main() {
  var now = DateTime(2026, 9, 11, 10);
  late FakeStudyReminder reminder;
  late FakeSettings settings;
  late LibraryHarness harness;
  late String itemId;

  Future<void> setUpWith({bool supported = true}) async {
    now = DateTime(2026, 9, 11, 10);
    reminder = FakeStudyReminder(supported: supported, permission: true);
    settings = FakeSettings();
    harness = await LibraryHarness.create(
      extraOverrides: [
        clockProvider.overrideWithValue(() => now),
        studyReminderProvider.overrideWithValue(reminder),
        studyReminderSettingsProvider.overrideWithValue(settings),
      ],
    );
    await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
    itemId =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!
            .single
            .id;
  }

  tearDown(() async => reminder.openController.close());

  Future<void> addCard(String front) async {
    await harness.container
        .read(flashcardRepositoryProvider)
        .create(itemId: itemId, front: front, back: 'R');
  }

  /// La app como la arma `App`: el router y el aviso por encima.
  Future<void> pumpApp(WidgetTester tester, {bool unlocked = true}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (unlocked) {
      harness.container
          .read(vaultSessionControllerProvider.notifier)
          .markUnlocked();
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(goRouterProvider);
            return StudyReminderBinding(
              router: router,
              child: MaterialApp.router(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String path() => harness.container
      .read(goRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;

  group('al abrir la app', () {
    testWidgets('vuelve a programar el aviso si estaba prendido y se perdió', (
      tester,
    ) async {
      await setUpWith();
      settings
        ..enabled = true
        ..time = const ReminderTime(19, 30);
      await pumpApp(tester);

      expect(reminder.scheduleCalls, [const ReminderTime(19, 30)]);
    });

    testWidgets('apagado, no programa nada', (tester) async {
      await setUpWith();
      await pumpApp(tester);

      expect(reminder.scheduleCalls, isEmpty);
    });
  });

  group('cuántas tarjetas le cuenta', () {
    testWidgets('las que hay para estudiar, y la actualiza cuando cambia', (
      tester,
    ) async {
      await setUpWith();
      await addCard('¿Uno?');
      await addCard('¿Dos?');
      await pumpApp(tester);
      expect(reminder.counts.last, 2);

      await addCard('¿Tres?');
      await tester.pumpAndSettle();

      expect(reminder.counts.last, 3);
    });

    testWidgets('respeta los límites del día', (tester) async {
      await setUpWith();
      await harness.container
          .read(studyLimitsProvider.notifier)
          .setNewPerDay(1);
      await addCard('¿Uno?');
      await addCard('¿Dos?');
      await pumpApp(tester);

      expect(reminder.counts.last, 1);
    });

    testWidgets('sin nada para estudiar le cuenta cero (el aviso de ese día '
        'no se muestra)', (tester) async {
      await setUpWith();
      await pumpApp(tester);

      expect(reminder.counts.last, 0);
    });

    testWidgets('cuenta lo que vence hasta la hora del aviso, no solo lo que '
        'vence ahora', (tester) async {
      await setUpWith();
      // Son las 21:00 y el aviso es a las 20:00: el próximo suena mañana. Una
      // tarjeta que vence mañana a las 12:00 no vence hoy, pero cuando suene
      // el aviso ya habrá vencido.
      now = DateTime(2026, 9, 11, 21);
      await addCard('¿Mañana?');
      final db = harness.database;
      await db
          .update(db.flashcards)
          .write(
            FlashcardsCompanion(
              dueAt: Value(DateTime(2026, 9, 12, 12)),
              intervalDays: const Value(3),
              repetitions: const Value(2),
              lastReviewedAt: Value(DateTime(2026, 9, 9, 12)),
            ),
          );
      await pumpApp(tester);

      // Lo de hoy no la cuenta (es lo que muestra la insignia)…
      final badge = harness.container.listen(
        studyDueTodayCountProvider,
        (_, _) {},
      );
      addTearDown(badge.close);
      await tester.pumpAndSettle();
      expect(badge.read().valueOrNull, 0);
      // …pero el aviso de mañana a las 20:00 sí.
      expect(reminder.counts.last, 1);
    });

    testWidgets('con otra hora del aviso, cuenta hasta esa hora', (
      tester,
    ) async {
      await setUpWith();
      now = DateTime(2026, 9, 11, 10);
      settings.time = const ReminderTime(8, 0);
      await addCard('¿Hoy?');
      final db = harness.database;
      // Vence mañana a las 7:00: el aviso de las 8:00 de mañana ya la ve.
      await db
          .update(db.flashcards)
          .write(
            FlashcardsCompanion(
              dueAt: Value(DateTime(2026, 9, 12, 7)),
              intervalDays: const Value(3),
              repetitions: const Value(2),
              lastReviewedAt: Value(DateTime(2026, 9, 9, 7)),
            ),
          );
      await pumpApp(tester);

      expect(reminder.counts.last, 1);
    });

    testWidgets('si se cambia la hora del aviso, vuelve a contar hasta la '
        'nueva', (tester) async {
      await setUpWith();
      await addCard('¿Mañana?');
      final db = harness.database;
      // Vence mañana a las 7:00: el aviso de las 20:00 de hoy no la ve.
      await db
          .update(db.flashcards)
          .write(
            FlashcardsCompanion(
              dueAt: Value(DateTime(2026, 9, 12, 7)),
              intervalDays: const Value(3),
              repetitions: const Value(2),
              lastReviewedAt: Value(DateTime(2026, 9, 9, 7)),
            ),
          );
      await pumpApp(tester);
      expect(reminder.counts.last, 0);

      // Pasa el aviso a las 8:00: el próximo suena mañana, con ella vencida.
      await harness.container
          .read(studyReminderStateProvider.notifier)
          .changeTime(const ReminderTime(8, 0));
      await tester.pumpAndSettle();

      expect(reminder.counts.last, 1);
    });

    testWidgets('con la bóveda cerrada no cuenta nada', (tester) async {
      await setUpWith();
      await addCard('¿Uno?');
      await pumpApp(tester, unlocked: false);
      expect(reminder.counts, isEmpty);

      harness.container
          .read(vaultSessionControllerProvider.notifier)
          .markUnlocked();
      await tester.pumpAndSettle();

      expect(reminder.counts.last, 1);
    });

    testWidgets('donde no hay aviso (escritorio) no cuenta nada', (
      tester,
    ) async {
      await setUpWith(supported: false);
      await addCard('¿Uno?');
      await pumpApp(tester);

      expect(reminder.counts, isEmpty);
    });
  });

  group('al tocar la notificación', () {
    testWidgets('con la app abierta lleva a Repasar, cada vez', (tester) async {
      await setUpWith();
      await pumpApp(tester);
      expect(path(), isNot(RoutePaths.review));

      reminder.openController.add(null);
      await tester.pumpAndSettle();
      expect(path(), RoutePaths.review);

      harness.container.read(goRouterProvider).go(RoutePaths.library);
      await tester.pumpAndSettle();
      expect(path(), RoutePaths.library);

      reminder.openController.add(null);
      await tester.pumpAndSettle();
      expect(path(), RoutePaths.review);
    });

    testWidgets('arrancando desde cero lleva a Repasar', (tester) async {
      await setUpWith();
      reminder.pendingOpen = true;

      await pumpApp(tester);

      expect(path(), RoutePaths.review);
      // Un solo pedido por toque: no vuelve a ir.
      harness.container.read(goRouterProvider).go(RoutePaths.library);
      await tester.pumpAndSettle();
      expect(path(), RoutePaths.library);
    });

    testWidgets('con la bóveda cerrada espera: al abrirla va a Repasar y no '
        'a la biblioteca', (tester) async {
      await setUpWith();
      reminder.pendingOpen = true;
      await pumpApp(tester, unlocked: false);
      expect(path(), isNot(RoutePaths.review));

      harness.container
          .read(vaultSessionControllerProvider.notifier)
          .markUnlocked();
      await tester.pumpAndSettle();

      expect(path(), RoutePaths.review);
    });
  });
}
