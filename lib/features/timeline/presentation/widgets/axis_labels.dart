import 'package:intl/intl.dart';
import 'package:sinapsis/features/timeline/domain/services/axis_scale.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El texto de una marca del eje.
///
/// Los años d.C. van solos ("476") y los a.C. con su era ("44 a.C."): el eje
/// guarda el año astronómico, y solo acá se traduce a lo que se lee. Las marcas
/// de mes llevan además el mes abreviado en el idioma de la app.
String axisTickLabel(
  AppLocalizations l10n,
  String locale,
  AxisUnit unit,
  AxisTick tick,
) {
  final year = _yearText(l10n, tick.year);
  if (unit == AxisUnit.years) return year;

  // Se formatea un año cualquiera (2000): solo importa el mes, y `DateFormat`
  // no sabe de años a.C.
  final month = DateFormat.MMM(locale).format(DateTime(2000, tick.month));
  return '$month $year';
}

/// El año astronómico [astronomicalYear] como se lee: 0 es "1 a.C.", -43 es
/// "44 a.C.".
String _yearText(AppLocalizations l10n, int astronomicalYear) {
  return astronomicalYear <= 0
      ? l10n.timelineYearBce(1 - astronomicalYear)
      : '$astronomicalYear';
}
