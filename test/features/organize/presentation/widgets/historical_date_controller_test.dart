import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/organize/presentation/widgets/historical_date_form.dart';

void main() {
  late HistoricalDateController controller;

  setUp(() => controller = HistoricalDateController());
  tearDown(() => controller.dispose());

  void typeYear(String text) => controller.yearController.text = text;
  void typeDay(String text) => controller.dayController.text = text;

  group('el año', () {
    test('sin nada escrito no hay fecha y tampoco error', () {
      expect(controller.date, isNull);
      expect(controller.year, isNull);
      expect(controller.hasYearError, isFalse);
    });

    test('un año válido da la fecha, con precisión de año por defecto', () {
      typeYear('476');

      expect(
        controller.date,
        const HistoricalDate(year: 476, precision: DatePrecision.year),
      );
    });

    test('los espacios alrededor no cuentan', () {
      typeYear('  476 ');

      expect(controller.year, 476);
    });

    test('el año cero no existe: es un error y no hay fecha', () {
      typeYear('0');

      expect(controller.hasYearError, isTrue);
      expect(controller.date, isNull);
    });

    test('lo que no es un número es un error', () {
      typeYear('abc');

      expect(controller.hasYearError, isTrue);
      expect(controller.date, isNull);
    });

    test('a.C. marca la fecha como anterior a la era común', () {
      typeYear('44');
      controller.isBce = true;

      final date = controller.date!;

      expect(date.isBce, isTrue);
      expect(date.year, 44);
      expect(date.astronomicalYear, -43);
    });
  });

  group('la precisión decide qué se guarda', () {
    test('día usa mes y día', () {
      typeYear('1969');
      controller
        ..precision = DatePrecision.day
        ..month = 7;
      typeDay('20');

      expect(
        controller.date,
        const HistoricalDate(
          year: 1969,
          precision: DatePrecision.day,
          month: 7,
          day: 20,
        ),
      );
    });

    test('mes usa el mes pero no el día, aunque el día siga escrito', () {
      typeYear('1969');
      controller
        ..precision = DatePrecision.month
        ..month = 7;
      typeDay('20');

      final date = controller.date!;

      expect(date.month, 7);
      expect(date.day, isNull);
    });

    test('año, década y siglo no llevan mes ni día', () {
      typeYear('1920');
      controller.month = 5;
      typeDay('9');

      for (final precision in [
        DatePrecision.year,
        DatePrecision.decade,
        DatePrecision.century,
      ]) {
        controller.precision = precision;
        final date = controller.date!;

        expect(date.precision, precision);
        expect(date.month, isNull, reason: precision.name);
        expect(date.day, isNull, reason: precision.name);
      }
    });

    test('qué campos usa cada precisión', () {
      controller.precision = DatePrecision.day;
      expect((controller.usesMonth, controller.usesDay), (true, true));

      controller.precision = DatePrecision.month;
      expect((controller.usesMonth, controller.usesDay), (true, false));

      controller.precision = DatePrecision.year;
      expect((controller.usesMonth, controller.usesDay), (false, false));
    });
  });

  group('el día', () {
    setUp(() {
      typeYear('2023');
      controller.precision = DatePrecision.day;
    });

    test('un día que el mes no tiene es un error y no hay fecha', () {
      controller.month = 4; // abril: 30 días
      typeDay('31');

      expect(controller.hasDayError, isTrue);
      expect(controller.maxDay, 30);
      expect(controller.date, isNull);
    });

    test('al cambiar de mes el mismo día pasa a ser válido', () {
      controller.month = 4;
      typeDay('31');
      expect(controller.date, isNull);

      controller.month = 5;

      expect(controller.hasDayError, isFalse);
      expect(controller.date?.day, 31);
    });

    test('el día cero o vacío no sirve, pero vacío no se marca como error', () {
      typeDay('0');
      expect(controller.hasDayError, isTrue);
      expect(controller.date, isNull);

      typeDay('');
      expect(controller.hasDayError, isFalse);
      expect(controller.date, isNull);
    });

    test('el error del día solo importa con precisión de día', () {
      controller.month = 4;
      typeDay('31');
      controller.precision = DatePrecision.month;

      expect(controller.hasDayError, isFalse);
      expect(controller.date, isNotNull);
    });

    test('el 29 de febrero existe en un año bisiesto y no en uno común', () {
      controller.month = 2;
      typeDay('29');

      typeYear('2024');
      expect(controller.date?.day, 29);

      typeYear('2023');
      expect(controller.date, isNull);
      expect(controller.maxDay, 28);
    });

    test('los años a.C. usan el calendario proléptico: 1 a.C. es bisiesto '
        'y 2 a.C. no', () {
      controller
        ..isBce = true
        ..month = 2;
      typeDay('29');

      typeYear('1'); // 1 a.C. es el año astronómico 0: bisiesto
      expect(controller.date?.day, 29);

      typeYear('2'); // 2 a.C. es el -1: común
      expect(controller.date, isNull);

      typeYear('5'); // 5 a.C. es el -4: bisiesto
      expect(controller.date?.day, 29);
    });

    test('sin año escrito, el máximo es el de un año común', () {
      typeYear('');
      controller.month = 2;

      expect(controller.maxDay, 28);
    });
  });

  group('aproximada', () {
    test('circa se guarda en la fecha', () {
      typeYear('476');
      controller.isCirca = true;

      expect(controller.date?.isCirca, isTrue);
    });
  });

  group('avisos', () {
    test('cada cambio avisa, y repetir el mismo valor no', () {
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..isBce = true
        ..isBce = true
        ..precision = DatePrecision.month
        ..precision = DatePrecision.month
        ..month = 3
        ..month = 3
        ..isCirca = true
        ..isCirca = true
        ..yearController.text = '44';

      // Cuatro cambios reales más el texto del año.
      expect(notifications, 5);
    });
  });
}
