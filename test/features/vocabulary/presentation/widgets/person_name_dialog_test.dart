import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/person_name_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// El diálogo del nombre de una persona (F15): apellido y nombre por separado,
/// con cómo va a quedar guardada.
void main() {
  final es = AppLocalizationsEs();

  /// Lo que el diálogo devolvió al cerrarse; `null` si se canceló o todavía
  /// está abierto.
  PersonName? picked;

  /// Abre el diálogo desde un botón, con [initial] si se pide.
  Future<void> openDialog(WidgetTester tester, {PersonName? initial}) async {
    picked = null;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await askPersonName(
              context,
              title: es.vocabularyAddPersonTitle,
              initial: initial,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, es.personDialogSave));
    await tester.pumpAndSettle();
  }

  group('los campos', () {
    testWidgets('el apellido, el nombre y el sufijo, y el título pedido', (
      tester,
    ) async {
      await openDialog(tester);

      expect(find.text(es.vocabularyAddPersonTitle), findsOneWidget);
      expect(field(es.personFamilyLabel), findsOneWidget);
      expect(field(es.personGivenLabel), findsOneWidget);
      expect(field(es.personSuffixLabel), findsOneWidget);
      expect(find.text(es.personIsInstitutionLabel), findsOneWidget);
    });

    testWidgets('arrancan con lo que la persona ya tiene', (tester) async {
      await openDialog(
        tester,
        initial: const PersonName(
          family: 'King',
          given: 'Martin Luther',
          suffix: 'Jr.',
        ),
      );

      String textOf(String label) =>
          tester.widget<TextField>(field(label)).controller!.text;
      expect(textOf(es.personFamilyLabel), 'King');
      expect(textOf(es.personGivenLabel), 'Martin Luther');
      expect(textOf(es.personSuffixLabel), 'Jr.');
    });

    testWidgets('una institución arranca marcada y sin nombre de pila', (
      tester,
    ) async {
      await openDialog(
        tester,
        initial: const PersonName.institution('Real Academia Española'),
      );

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(field(es.personGivenLabel), findsNothing);
    });
  });

  group('guardar', () {
    testWidgets('sin apellido no se puede', (tester) async {
      await openDialog(tester);

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, es.personDialogSave),
      );

      expect(button.onPressed, isNull);
    });

    testWidgets('con el apellido y el nombre, devuelve la persona sin espacios '
        'de más', (tester) async {
      await openDialog(tester);

      await tester.enterText(field(es.personFamilyLabel), '  García Márquez ');
      await tester.enterText(field(es.personGivenLabel), ' Gabriel');
      await tester.pumpAndSettle();
      await save(tester);

      expect(
        picked,
        const PersonName(family: 'García Márquez', given: 'Gabriel'),
      );
    });

    testWidgets('el sufijo viaja', (tester) async {
      await openDialog(tester);

      await tester.enterText(field(es.personFamilyLabel), 'King');
      await tester.enterText(field(es.personGivenLabel), 'Martin Luther');
      await tester.enterText(field(es.personSuffixLabel), 'Jr.');
      await tester.pumpAndSettle();
      await save(tester);

      expect(picked!.label, 'King, Martin Luther Jr.');
      expect(picked!.suffix, 'Jr.');
    });

    testWidgets('Enter en el apellido también guarda', (tester) async {
      await openDialog(tester);

      await tester.enterText(field(es.personFamilyLabel), 'Platón');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(picked, const PersonName(family: 'Platón'));
    });

    testWidgets('cancelar no devuelve nada', (tester) async {
      await openDialog(tester);
      await tester.enterText(field(es.personFamilyLabel), 'Borges');

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(picked, isNull);
      expect(find.text(es.vocabularyAddPersonTitle), findsNothing);
    });
  });

  group('la vista previa', () {
    testWidgets('dice cómo se guarda: «Apellido, Nombre»', (tester) async {
      await openDialog(tester);

      await tester.enterText(field(es.personFamilyLabel), 'García Márquez');
      await tester.enterText(field(es.personGivenLabel), 'Gabriel');
      await tester.pumpAndSettle();

      expect(
        find.text(es.personLabelPreview('García Márquez, Gabriel')),
        findsOneWidget,
      );
    });

    testWidgets('no aparece mientras no hay apellido', (tester) async {
      await openDialog(tester);

      expect(find.textContaining('Se guarda como'), findsNothing);
    });
  });

  group('una institución', () {
    testWidgets('no lleva nombre de pila ni sufijo, y se guarda entera', (
      tester,
    ) async {
      await openDialog(tester);
      await tester.enterText(
        field(es.personFamilyLabel),
        'Real Academia Española',
      );
      await tester.enterText(field(es.personGivenLabel), 'Se borra');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Los campos que no aplican desaparecen.
      expect(field(es.personGivenLabel), findsNothing);
      expect(field(es.personSuffixLabel), findsNothing);
      await save(tester);
      expect(picked!.isInstitution, isTrue);
      expect(picked!.given, isEmpty);
      expect(picked!.label, 'Real Academia Española');
    });
  });
}
