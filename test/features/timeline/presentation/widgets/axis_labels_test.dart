import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sinapsis/features/timeline/domain/services/axis_scale.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/axis_labels.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();
  final en = AppLocalizationsEn();

  setUpAll(() async {
    await initializeDateFormatting('es');
    await initializeDateFormatting('en');
  });

  AxisTick tick(int year, [int month = 1]) =>
      (position: year.toDouble(), year: year, month: month);

  group('años', () {
    test('los d.C. van solos', () {
      expect(axisTickLabel(es, 'es', AxisUnit.years, tick(476)), '476');
      expect(axisTickLabel(es, 'es', AxisUnit.years, tick(1)), '1');
    });

    test('los a.C. llevan la era: el año astronómico 0 es "1 a.C."', () {
      expect(axisTickLabel(es, 'es', AxisUnit.years, tick(0)), '1 a.C.');
      expect(axisTickLabel(es, 'es', AxisUnit.years, tick(-43)), '44 a.C.');
      expect(axisTickLabel(es, 'es', AxisUnit.years, tick(-99)), '100 a.C.');
    });

    test('en inglés la era es BC', () {
      expect(axisTickLabel(en, 'en', AxisUnit.years, tick(-43)), '44 BC');
      expect(axisTickLabel(en, 'en', AxisUnit.years, tick(476)), '476');
    });

    test('las marcas de una escala que cruza el cero se leen en orden', () {
      final scale = axisScale(from: -250, to: 250);

      final labels = [
        for (final t in scale.ticks) axisTickLabel(es, 'es', scale.unit, t),
      ];

      expect(labels, ['200 a.C.', '100 a.C.', '1', '100', '200']);
    });
  });

  group('meses', () {
    test('llevan el mes abreviado en el idioma de la app', () {
      final july = tick(1969, 7);

      expect(axisTickLabel(es, 'es', AxisUnit.months, july), 'jul 1969');
      expect(axisTickLabel(en, 'en', AxisUnit.months, july), 'Jul 1969');
    });

    test('también en a.C.', () {
      expect(
        axisTickLabel(es, 'es', AxisUnit.months, tick(-43, 3)),
        'mar 44 a.C.',
      );
    });
  });
}
