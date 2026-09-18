import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';

part 'historical_date.freezed.dart';

/// Un día concreto en el mapa de un rango. `month`/`day` son siempre 1 en
/// el extremo inferior de un [DatePrecision.year]/[DatePrecision.decade]/
/// [DatePrecision.century], y el último día del mes/año en el superior —
/// ver [HistoricalDate.rangeStart]/[HistoricalDate.rangeEnd].
typedef DatePoint = ({int year, int month, int day});

/// Una fecha histórica, con la precisión y la incertidumbre con las que
/// se conoce el hecho —no la fecha en que se capturó la fuente que lo
/// cuenta—.
///
/// [year] es siempre positivo: "lo que el usuario tipeó" ("44" para "44
/// a.C."), no el año astronómico de almacenamiento. Ese año astronómico
/// —[astronomicalYear]— es la representación que viaja a la base
/// (`PropertyValues.dateFromYear`/`dateToYear`): 1 d.C. → 1, 1 a.C. → 0,
/// 44 a.C. → -43. Firmado y monótono con el tiempo real, para que
/// `ORDER BY` y las comparaciones de rango crucen el cero sin ningún
/// caso especial para a.C./d.C.
@freezed
sealed class HistoricalDate with _$HistoricalDate {
  const factory HistoricalDate({
    required int year,
    required DatePrecision precision,
    int? month,
    int? day,
    @Default(false) bool isBce,
    @Default(false) bool isCirca,
  }) = _HistoricalDate;

  const HistoricalDate._();

  /// El inverso de [astronomicalYear]: reconstruye una [HistoricalDate] a
  /// partir de lo que quedó guardado en `PropertyValues.dateFromYear` (o
  /// `dateToYear`, son el mismo año astronómico en cualquiera de los dos
  /// extremos salvo por `month`/`day`).
  factory HistoricalDate.fromAstronomicalYear(
    int astronomicalYear, {
    required DatePrecision precision,
    int? month,
    int? day,
    bool isCirca = false,
  }) {
    final isBce = astronomicalYear <= 0;
    return HistoricalDate(
      year: isBce ? 1 - astronomicalYear : astronomicalYear,
      precision: precision,
      month: month,
      day: day,
      isBce: isBce,
      isCirca: isCirca,
    );
  }

  int get astronomicalYear => isBce ? 1 - year : year;

  /// El primer día que cubre esta fecha, según [precision]. Para
  /// [DatePrecision.day] es el propio día; para el resto, el primero del
  /// mes/año que corresponda.
  DatePoint get rangeStart => switch (precision) {
    DatePrecision.day => (year: astronomicalYear, month: month!, day: day!),
    DatePrecision.month => (year: astronomicalYear, month: month!, day: 1),
    DatePrecision.year ||
    DatePrecision.decade ||
    DatePrecision.century => (year: astronomicalYear, month: 1, day: 1),
  };

  /// El último día que cubre esta fecha, según [precision]. `decade` y
  /// `century` suman 9 y 99 años respectivamente al año de inicio: es
  /// uniforme cruzando el cero porque [astronomicalYear] ya es monótono
  /// con el tiempo real —340 a.C. en década da el rango [-339, -330], que
  /// en fechas de calendario son los años 340 a 331 a.C., el rango
  /// correcto sin ningún caso especial para a.C.
  DatePoint get rangeEnd => switch (precision) {
    DatePrecision.day => (year: astronomicalYear, month: month!, day: day!),
    DatePrecision.month => (
      year: astronomicalYear,
      month: month!,
      day: _daysInMonth(astronomicalYear, month!),
    ),
    DatePrecision.year => (year: astronomicalYear, month: 12, day: 31),
    DatePrecision.decade => (year: astronomicalYear + 9, month: 12, day: 31),
    DatePrecision.century => (year: astronomicalYear + 99, month: 12, day: 31),
  };

  /// El texto legible de esta fecha, derivado solo de sus datos —dos
  /// [HistoricalDate] con los mismos campos siempre dan el mismo label,
  /// sin importar el orden en que se construyeron—. Es lo que
  /// `getOrCreateHistoricalPropertyValue` usa como `PropertyValues.value`
  /// para el get-or-create.
  ///
  /// `decade`/`century` se expresan como el rango de años que cubren en
  /// vez de "década de 1920"/"Siglo XX": el año que se tipea para esas
  /// precisiones es el primero del tramo de diez o cien años, no un
  /// número de siglo/década con nombre propio —no hay forma de
  /// convertirlo a "Siglo IV a.C." sin asumir que ese tramo arranca justo
  /// en un límite de siglo canónico, algo que acá no se puede dar por
  /// sentado—.
  String get label {
    final circa = isCirca ? 'circa ' : '';
    return switch (precision) {
      DatePrecision.day =>
        '$circa$day de ${_monthNames[month! - 1]} de '
            '${_yearLabel(astronomicalYear)}',
      DatePrecision.month =>
        '$circa${_monthNames[month! - 1]} de '
            '${_yearLabel(astronomicalYear)}',
      DatePrecision.year => '$circa${_yearLabel(astronomicalYear)}',
      DatePrecision.decade || DatePrecision.century =>
        '$circa${_yearLabel(rangeStart.year)} – ${_yearLabel(rangeEnd.year)}',
    };
  }
}

const _monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "44 a.C." o "1969" —sin "d.C.": no hace falta desambiguar lo que ya es
/// la convención implícita.
String _yearLabel(int astronomicalYear) {
  final asCalendarYear = HistoricalDate.fromAstronomicalYear(
    astronomicalYear,
    precision: DatePrecision.year,
  );
  return asCalendarYear.isBce
      ? '${asCalendarYear.year} a.C.'
      : '${asCalendarYear.year}';
}

/// Calendario gregoriano proléptico —la misma convención con la que
/// `DateTime` de Dart cuenta años antes de su propia época, aplicada acá
/// a mano para no depender de que años tan alejados de hoy se comporten
/// igual en todas las plataformas (la web incluida).
bool _isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

int _daysInMonth(int year, int month) {
  const daysByMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _isLeapYear(year)) return 29;
  return daysByMonth[month - 1];
}
