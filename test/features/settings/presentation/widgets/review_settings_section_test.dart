import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/settings/presentation/widgets/review_settings_section.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/presentation/providers/study_reminder_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_study_reminder.dart';
import '../../../../support/library_harness.dart';

class _MockExport extends Mock implements ExportFlashcardsToAnkiUseCase {}

class _CountingReminder extends FakeStudyReminder {
  _CountingReminder({super.supported, super.permission});

  int openedSettings = 0;

  @override
  Future<bool> openNotificationSettings() async {
    openedSettings++;
    return true;
  }
}

/// La sección «Repasar» de Ajustes (F31, decisión 73): el aviso diario, los
/// límites por día y el camino a Anki.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late _CountingReminder reminder;
  late _MockExport export;

  setUpAll(() => registerFallbackValue(const ExportFlashcardsToAnkiParams()));

  Future<void> start(
    WidgetTester tester, {
    bool supported = true,
    bool permission = false,
  }) async {
    reminder = _CountingReminder(supported: supported, permission: permission);
    export = _MockExport();
    when(() => export(any())).thenAnswer((_) async => right(unit));
    harness = await LibraryHarness.create(
      extraOverrides: [
        studyReminderProvider.overrideWithValue(reminder),
        exportFlashcardsToAnkiUseCaseProvider.overrideWithValue(export),
      ],
    );
    tester.view
      ..physicalSize = const Size(900, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(
        const Scaffold(
          body: SingleChildScrollView(child: ReviewSettingsSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder switchFinder() =>
      find.byKey(const Key('review-settings-reminder-switch'));

  StudyLimits limits() => harness.container.read(studyLimitsProvider);

  group('aviso diario', () {
    testWidgets('sin soporte (escritorio, web) no se ofrece', (tester) async {
      await start(tester, supported: false);

      expect(switchFinder(), findsNothing);
      expect(find.text(es.reviewSettingsReminderTitle), findsNothing);
      // Lo demás sigue.
      expect(find.text(es.reviewSettingsNewLimit), findsOneWidget);
      expect(find.text(es.reviewSettingsExportAnki), findsOneWidget);
    });

    testWidgets('arranca apagado, sin pedir el permiso', (tester) async {
      await start(tester);

      expect(find.text(es.reviewSettingsReminderTitle), findsOneWidget);
      expect(tester.widget<SwitchListTile>(switchFinder()).value, isFalse);
      expect(
        find.byKey(const Key('review-settings-reminder-time')),
        findsNothing,
      );
      expect(reminder.permissionRequests, 0);
      expect(reminder.scheduled, isNull);
    });

    testWidgets('prenderlo pide el permiso, lo programa a las 20:00 y muestra '
        'la hora, el permiso y el aviso de batería', (tester) async {
      await start(tester);

      await tester.tap(switchFinder());
      await tester.pumpAndSettle();

      expect(reminder.permissionRequests, 1);
      expect(reminder.scheduled, ReminderTime.standard);
      expect(tester.widget<SwitchListTile>(switchFinder()).value, isTrue);
      expect(
        find.byKey(const Key('review-settings-reminder-time')),
        findsOneWidget,
      );
      expect(find.text(es.reviewSettingsPermissionOk), findsOneWidget);
      expect(find.text(es.reviewSettingsReminderBattery), findsOneWidget);
    });

    testWidgets('si el sistema no da el permiso, no se prende y manda a los '
        'ajustes del sistema', (tester) async {
      await start(tester);
      reminder.grantsWhenAsked = false;

      await tester.tap(switchFinder());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(switchFinder()).value, isFalse);
      expect(reminder.scheduled, isNull);
      expect(find.text(es.reviewSettingsPermissionMissing), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('review-settings-open-system-settings')),
      );
      await tester.pumpAndSettle();
      expect(reminder.openedSettings, 1);
    });

    testWidgets('si el permiso se quitó con el aviso prendido, lo avisa', (
      tester,
    ) async {
      await start(tester, permission: true);
      await tester.tap(switchFinder());
      await tester.pumpAndSettle();
      expect(find.text(es.reviewSettingsPermissionOk), findsOneWidget);

      reminder.permission = false;
      await harness.container
          .read(studyReminderStateProvider.notifier)
          .refresh();
      await tester.pumpAndSettle();

      expect(find.text(es.reviewSettingsPermissionMissing), findsOneWidget);
      expect(
        find.byKey(const Key('review-settings-open-system-settings')),
        findsOneWidget,
      );
    });

    testWidgets('elegir la hora la reprograma', (tester) async {
      await start(tester, permission: true);
      await tester.tap(switchFinder());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('review-settings-reminder-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '7');
      await tester.enterText(fields.at(1), '45');
      await tester.tap(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextButton),
            )
            .last,
      );
      await tester.pumpAndSettle();

      // El selector de las pruebas es de 12 horas y arrancó en la tarde: las
      // 7 siguen siendo de la tarde.
      expect(reminder.scheduled, const ReminderTime(19, 45));
    });

    testWidgets('apagarlo cancela la alarma', (tester) async {
      await start(tester, permission: true);
      await tester.tap(switchFinder());
      await tester.pumpAndSettle();

      await tester.tap(switchFinder());
      await tester.pumpAndSettle();

      expect(reminder.cancelCalls, 1);
      expect(reminder.scheduled, isNull);
      expect(tester.widget<SwitchListTile>(switchFinder()).value, isFalse);
      expect(find.byKey(const Key('review-settings-battery')), findsNothing);
    });
  });

  group('límites por día', () {
    testWidgets('arrancan en 20 nuevas y 200 repasos', (tester) async {
      await start(tester, supported: false);

      expect(find.text(es.reviewSettingsLimitValue(20)), findsOneWidget);
      expect(
        find.textContaining(es.reviewSettingsLimitValue(200)),
        findsOneWidget,
      );
    });

    testWidgets('se elige un valor y queda guardado', (tester) async {
      await start(tester, supported: false);

      await tester.tap(find.byKey(const Key('review-settings-new-limit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-limit-choice-10')));
      await tester.pumpAndSettle();

      expect(limits().newPerDay, 10);
      expect(limits().reviewsPerDay, 200);
      expect(find.text(es.reviewSettingsLimitValue(10)), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-settings-review-limit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-limit-choice-500')));
      await tester.pumpAndSettle();
      expect(limits().reviewsPerDay, 500);
    });

    testWidgets('«Sin límite» es el tope más alto', (tester) async {
      await start(tester, supported: false);

      await tester.tap(find.byKey(const Key('review-settings-new-limit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-limit-choice-9999')));
      await tester.pumpAndSettle();

      expect(limits().newPerDay, StudyLimits.maxPerDay);
      expect(find.text(es.reviewSettingsNoLimit), findsOneWidget);
    });

    testWidgets('un valor guardado que no está entre las opciones sigue '
        'apareciendo', (tester) async {
      await start(tester, supported: false);
      await harness.container
          .read(studyLimitsProvider.notifier)
          .setNewPerDay(37);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('review-settings-new-limit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review-limit-choice-37')), findsOneWidget);
    });
  });

  group('Anki', () {
    testWidgets('exportar pregunta qué y en qué formato, y exporta', (
      tester,
    ) async {
      await start(tester, supported: false);

      await tester.tap(find.byKey(const Key('review-settings-export-anki')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-settings-export-all')));
      await tester.tap(
        find.byKey(const Key('review-settings-export-format-tsv')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-settings-export-confirm')));
      await tester.pumpAndSettle();

      final params =
          verify(() => export(captureAny())).captured.single
              as ExportFlashcardsToAnkiParams;
      expect(params.exportAll, isTrue);
      expect(params.format, AnkiExportFormat.tsv);
    });

    testWidgets('cancelar la exportación no exporta nada', (tester) async {
      await start(tester, supported: false);

      await tester.tap(find.byKey(const Key('review-settings-export-anki')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      verifyNever(() => export(any()));
    });

    testWidgets('si exportar falla, lo dice', (tester) async {
      await start(tester, supported: false);
      when(() => export(any())).thenAnswer(
        (_) async => left(const Failure.exportFailed(message: 'sin disco')),
      );

      await tester.tap(find.byKey(const Key('review-settings-export-anki')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-settings-export-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('importar lleva a la pantalla de importar de Anki', (
      tester,
    ) async {
      await start(tester, supported: false);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();

      final tile = find.byKey(const Key('review-settings-import-anki'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.text(es.ankiImportTitle), findsOneWidget);
    });
  });
}
