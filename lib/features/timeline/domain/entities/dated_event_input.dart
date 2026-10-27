import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';

part 'dated_event_input.freezed.dart';

/// Lo que hace falta para poner un hecho fechado (F40): el título, la fecha,
/// el fin si es un tramo y la cita. Lo arma quien lo pone —la persona desde la
/// línea de tiempo o desde la barrita de resaltar, la IA desde lo que leyó del
/// texto—; el repositorio le agrega el origen, la pasada y las horas.
@freezed
sealed class DatedEventInput with _$DatedEventInput {
  const factory DatedEventInput({
    required String title,
    required HistoricalDate date,

    /// Cuándo termina, si es un tramo. No puede terminar antes de que
    /// termine [date].
    HistoricalDate? end,

    /// El texto del que sale la cita; sin él no hay posición.
    String? renditionId,
    int? startOffset,
    int? endOffset,
    String? excerpt,
  }) = _DatedEventInput;

  const DatedEventInput._();

  /// Por qué esto no se puede guardar, o `null` si está bien. Es lo mismo que
  /// después hace cumplir la base con sus `CHECK`, dicho para quien lo
  /// escribió. El texto es para diagnóstico y registros: quien se lo muestra a
  /// una persona usa [problemKind] y lo dice en su idioma.
  String? get problem => problemKind?.message;

  /// Si [title] sirve de título: lo que el formulario pregunta antes de tener
  /// la fecha completa, con la misma regla con que después se valida todo.
  static DatedEventProblem? titleProblem(String title) =>
      title.trim().isEmpty ? DatedEventProblem.titleMissing : null;

  /// Lo primero que impide guardar esto, o `null` si está bien. Es lo que le
  /// sirve al formulario para decir **dónde** está el problema (el título, el
  /// fin) y en el idioma de la app.
  DatedEventProblem? get problemKind {
    final titleProblem = DatedEventInput.titleProblem(title);
    if (titleProblem != null) return titleProblem;
    final dateProblem = _dateProblem(date);
    if (dateProblem != null) return dateProblem;
    if (end case final end?) {
      final endProblem = _dateProblem(end);
      if (endProblem != null) return endProblem;
      // Un tramo no termina antes de que termine su inicio: «agosto de 1914
      // a 1914» está bien, «1918 a 1914» no.
      if (_compare(end.rangeEnd, date.rangeEnd) < 0) {
        return DatedEventProblem.endsBeforeStart;
      }
    }
    final start = startOffset;
    final stop = endOffset;
    if ((start == null) != (stop == null)) {
      return DatedEventProblem.quoteHalfPositioned;
    }
    if (start != null && stop != null) {
      if (renditionId == null) return DatedEventProblem.quoteWithoutText;
      if (start < 0 || stop <= start) {
        return DatedEventProblem.quoteNotARange;
      }
      if ((excerpt ?? '').trim().isEmpty) {
        return DatedEventProblem.quoteWithoutFragment;
      }
    }
    return null;
  }
}

/// Qué impide guardar un [DatedEventInput] (F40). Cada uno trae su texto de
/// diagnóstico en [message]; lo que se le muestra a una persona se traduce
/// aparte, según el lugar donde se dice.
enum DatedEventProblem {
  titleMissing('El hecho necesita un título.'),
  yearNotPositive('El año tiene que ser positivo.'),
  monthOutOfRange('El mes tiene que estar entre 1 y 12.'),
  dayNotInMonth('Ese día no existe en ese mes.'),
  endsBeforeStart('El hecho no puede terminar antes de empezar.'),
  quoteHalfPositioned('La cita necesita dónde empieza y dónde termina.'),
  quoteWithoutText('La posición de la cita necesita el texto del que sale.'),
  quoteNotARange('La posición de la cita no es un tramo del texto.'),
  quoteWithoutFragment('La cita necesita el fragmento del texto.');

  const DatedEventProblem(this.message);

  final String message;
}

/// Por qué [date] no es una fecha: un año que no existe, un mes de más, un día
/// que el mes no tiene, o la falta del mes o del día que su precisión pide.
DatedEventProblem? _dateProblem(HistoricalDate date) {
  if (date.year < 1) return DatedEventProblem.yearNotPositive;
  final usesMonth =
      date.precision == DatePrecision.day ||
      date.precision == DatePrecision.month;
  final month = date.month;
  if (usesMonth && (month == null || month < 1 || month > 12)) {
    return DatedEventProblem.monthOutOfRange;
  }
  if (date.precision == DatePrecision.day) {
    final day = date.day;
    if (day == null ||
        day < 1 ||
        day > daysInMonth(date.astronomicalYear, month!)) {
      return DatedEventProblem.dayNotInMonth;
    }
  }
  return null;
}

int _compare(DatePoint a, DatePoint b) {
  final byYear = a.year.compareTo(b.year);
  if (byYear != 0) return byYear;
  final byMonth = a.month.compareTo(b.month);
  return byMonth != 0 ? byMonth : a.day.compareTo(b.day);
}
