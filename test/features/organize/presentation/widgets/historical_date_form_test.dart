import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/features/organize/presentation/widgets/historical_date_form.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();
  late HistoricalDateController controller;

  setUp(() => controller = HistoricalDateController());
  tearDown(() => controller.dispose());

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: HistoricalDateForm(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> choosePrecision(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el año con su era, las precisiones y la casilla de '
      'aproximada', (tester) async {
    await pumpForm(tester);

    expect(field(es.datePickerYear), findsOneWidget);
    expect(find.text(es.datePickerEraCe), findsOneWidget);
    expect(find.text(es.datePickerEraBce), findsOneWidget);
    for (final label in [
      es.datePickerPrecisionDay,
      es.datePickerPrecisionMonth,
      es.datePickerPrecisionYear,
      es.datePickerPrecisionDecade,
      es.datePickerPrecisionCentury,
    ]) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    expect(find.text(es.datePickerCirca), findsOneWidget);
  });

  testWidgets('por defecto es de año: sin mes ni día', (tester) async {
    await pumpForm(tester);

    expect(controller.precision, DatePrecision.year);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(field(es.datePickerDay), findsNothing);
  });

  testWidgets('sin nada escrito no hay vista previa ni error', (tester) async {
    await pumpForm(tester);

    expect(find.textContaining('Se guardará como'), findsNothing);
    expect(find.text(es.datePickerYearInvalid), findsNothing);
  });

  testWidgets('escribir un año muestra cómo va a quedar guardado', (
    tester,
  ) async {
    await pumpForm(tester);

    await tester.enterText(field(es.datePickerYear), '476');
    await tester.pump();

    expect(find.text(es.datePickerPreview('476')), findsOneWidget);
    expect(controller.date?.year, 476);
  });

  testWidgets('a.C. lo dice en la vista previa', (tester) async {
    await pumpForm(tester);

    await tester.enterText(field(es.datePickerYear), '44');
    await tester.tap(find.text(es.datePickerEraBce));
    await tester.pumpAndSettle();

    expect(find.text(es.datePickerPreview('44 a.C.')), findsOneWidget);
    expect(controller.isBce, isTrue);
  });

  testWidgets('aproximada agrega "circa" a la vista previa', (tester) async {
    await pumpForm(tester);

    await tester.enterText(field(es.datePickerYear), '476');
    await tester.tap(find.text(es.datePickerCirca));
    await tester.pumpAndSettle();

    expect(find.text(es.datePickerPreview('circa 476')), findsOneWidget);
    expect(controller.isCirca, isTrue);
  });

  testWidgets('el campo del año solo acepta dígitos', (tester) async {
    await pumpForm(tester);

    await tester.enterText(field(es.datePickerYear), 'a4-4b');
    await tester.pump();

    expect(controller.yearController.text, '44');
  });

  testWidgets('el año cero se marca como error y no hay vista previa', (
    tester,
  ) async {
    await pumpForm(tester);

    await tester.enterText(field(es.datePickerYear), '0');
    await tester.pump();

    expect(find.text(es.datePickerYearInvalid), findsOneWidget);
    expect(find.textContaining('Se guardará como'), findsNothing);
    expect(controller.date, isNull);
  });

  group('según la precisión', () {
    testWidgets('mes pide el mes y no el día', (tester) async {
      await pumpForm(tester);

      await choosePrecision(tester, es.datePickerPrecisionMonth);

      expect(find.byType(DropdownButton<int>), findsOneWidget);
      expect(field(es.datePickerDay), findsNothing);
    });

    testWidgets('día pide el mes y el día', (tester) async {
      await pumpForm(tester);

      await choosePrecision(tester, es.datePickerPrecisionDay);

      expect(find.byType(DropdownButton<int>), findsOneWidget);
      expect(field(es.datePickerDay), findsOneWidget);
    });

    testWidgets('volver a año esconde mes y día', (tester) async {
      await pumpForm(tester);
      await choosePrecision(tester, es.datePickerPrecisionDay);

      await choosePrecision(tester, es.datePickerPrecisionYear);

      expect(field(es.datePickerDay), findsNothing);
    });

    testWidgets('década y siglo explican que el año es el primero del tramo', (
      tester,
    ) async {
      await pumpForm(tester);

      await choosePrecision(tester, es.datePickerPrecisionDecade);
      expect(find.text(es.datePickerPeriodHintDecade), findsOneWidget);

      await choosePrecision(tester, es.datePickerPrecisionCentury);
      expect(find.text(es.datePickerPeriodHintCentury), findsOneWidget);
      expect(find.text(es.datePickerPeriodHintDecade), findsNothing);

      await choosePrecision(tester, es.datePickerPrecisionYear);
      expect(find.text(es.datePickerPeriodHintCentury), findsNothing);
    });

    testWidgets('una década se muestra como el tramo que cubre', (
      tester,
    ) async {
      await pumpForm(tester);

      await tester.enterText(field(es.datePickerYear), '1920');
      await choosePrecision(tester, es.datePickerPrecisionDecade);

      expect(find.text(es.datePickerPreview('1920 – 1929')), findsOneWidget);
    });
  });

  group('mes y día', () {
    Future<void> chooseMonth(WidgetTester tester, String name) async {
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('el mes se elige por su nombre, en el idioma de la app', (
      tester,
    ) async {
      await pumpForm(tester);
      await choosePrecision(tester, es.datePickerPrecisionMonth);

      // Empieza en enero.
      expect(find.text('Enero'), findsOneWidget);

      await chooseMonth(tester, 'Julio');

      expect(controller.month, 7);
    });

    testWidgets('una fecha completa muestra su vista previa', (tester) async {
      await pumpForm(tester);
      await tester.enterText(field(es.datePickerYear), '1969');
      await choosePrecision(tester, es.datePickerPrecisionDay);
      await chooseMonth(tester, 'Julio');
      await tester.enterText(field(es.datePickerDay), '20');
      await tester.pump();

      expect(
        find.text(es.datePickerPreview('20 de julio de 1969')),
        findsOneWidget,
      );
    });

    testWidgets('un día que el mes no tiene dice cuál es el máximo', (
      tester,
    ) async {
      await pumpForm(tester);
      await tester.enterText(field(es.datePickerYear), '2023');
      await choosePrecision(tester, es.datePickerPrecisionDay);
      await chooseMonth(tester, 'Abril');

      await tester.enterText(field(es.datePickerDay), '31');
      await tester.pump();

      expect(find.text(es.datePickerDayInvalid(30)), findsOneWidget);
      expect(controller.date, isNull);
      expect(find.textContaining('Se guardará como'), findsNothing);
    });

    testWidgets('febrero acepta el 29 solo en año bisiesto', (tester) async {
      await pumpForm(tester);
      await tester.enterText(field(es.datePickerYear), '2024');
      await choosePrecision(tester, es.datePickerPrecisionDay);
      await chooseMonth(tester, 'Febrero');
      await tester.enterText(field(es.datePickerDay), '29');
      await tester.pump();
      expect(find.text(es.datePickerDayInvalid(29)), findsNothing);
      expect(controller.date?.day, 29);

      await tester.enterText(field(es.datePickerYear), '2023');
      await tester.pump();

      expect(find.text(es.datePickerDayInvalid(28)), findsOneWidget);
    });
  });

  testWidgets('en una pantalla angosta no se desborda', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpForm(tester);
    await choosePrecision(tester, es.datePickerPrecisionDay);
    await tester.enterText(field(es.datePickerDay), '99');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
