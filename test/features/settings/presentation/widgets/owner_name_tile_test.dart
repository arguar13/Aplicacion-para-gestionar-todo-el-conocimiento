import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/settings/presentation/providers/owner_name.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// «Cómo te llamo», en Ajustes (F42).
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings-owner-name')));
    await tester.pumpAndSettle();
  }

  testWidgets('va primero, en «Vos», y sin nombre dice para qué sirve', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text(es.settingsYouSection), findsOneWidget);
    expect(find.text(es.ownerNameTitle), findsOneWidget);
    expect(find.text(es.ownerNameEmpty), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(es.settingsYouSection)).dy,
      lessThan(tester.getTopLeft(find.text(es.settingsAppearanceSection)).dy),
    );
  });

  testWidgets('ponerlo lo guarda en el teléfono y lo muestra', (tester) async {
    await pumpSettings(tester);
    await openDialog(tester);

    expect(find.text(es.ownerNameDialogPrivacy), findsOneWidget);
    // Sin nombre no hay nada que quitar.
    expect(find.byKey(const Key('owner-name-remove')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('owner-name-field')),
      ' Armando ',
    );
    await tester.tap(find.byKey(const Key('owner-name-save')));
    await tester.pumpAndSettle();

    expect(find.text('Armando'), findsOneWidget);
    expect(
      harness.container
          .read(sharedPreferencesProvider)
          .getString(OwnerNameNotifier.prefsKey),
      'Armando',
    );
  });

  testWidgets('Enter también lo guarda', (tester) async {
    await pumpSettings(tester);
    await openDialog(tester);

    await tester.enterText(find.byKey(const Key('owner-name-field')), 'Ana');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(harness.container.read(ownerNameProvider), 'Ana');
  });

  testWidgets('«Quitar» lo borra y cancelar no cambia nada', (tester) async {
    await harness.container.read(ownerNameProvider.notifier).rename('Ana');
    await pumpSettings(tester);

    await openDialog(tester);
    await tester.enterText(find.byKey(const Key('owner-name-field')), 'Otro');
    await tester.tap(find.text(es.commonCancel));
    await tester.pumpAndSettle();
    expect(harness.container.read(ownerNameProvider), 'Ana');

    await openDialog(tester);
    await tester.tap(find.byKey(const Key('owner-name-remove')));
    await tester.pumpAndSettle();

    expect(harness.container.read(ownerNameProvider), isNull);
    expect(find.text(es.ownerNameEmpty), findsOneWidget);
  });
}
