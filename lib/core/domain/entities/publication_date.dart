import 'package:meta/meta.dart';

/// Con qué exactitud se sabe cuándo se publicó una obra.
///
/// Un libro trae un año; un artículo de diario, un día; y hay obras que no
/// tienen fecha en absoluto. Guardar siempre un día completo obligaría a
/// inventar el mes y el día de casi todo, y una cita con un «1 de enero» que
/// nadie escribió sería una cita falsa.
enum PublicationPrecision {
  /// Solo se sabe el año.
  year,

  /// Se sabe el año y el mes.
  month,

  /// Se sabe el día.
  day,

  /// La obra no tiene fecha: las normas piden «s. f.» (sin fecha). No es lo
  /// mismo que no saberla: ver [PublicationDate.isUnknown].
  undated,
}

/// Cuándo se publicó una obra, con la exactitud con que se sabe.
///
/// Junta lo que se guarda en dos lugares —`Source.publishedAt`, la fecha, y la
/// precisión de la referencia— para que quien cita no tenga que combinarlos:
///
/// - **desconocida** ([isUnknown]): nadie la cargó. La cita la marca como un
///   hueco, no como «sin fecha»;
/// - **sin fecha** ([isUndated]): alguien dijo que la obra no la tiene, y la
///   cita lo escribe como lo escribe cada norma;
/// - **conocida**: con su año, y con su mes y su día si la precisión llega.
@immutable
class PublicationDate {
  /// La fecha [date] con la [precision] con que se sabe.
  const PublicationDate({this.date, this.precision});

  /// Nadie cargó la fecha.
  const PublicationDate.unknown() : date = null, precision = null;

  /// La obra no tiene fecha.
  const PublicationDate.undated()
    : date = null,
      precision = PublicationPrecision.undated;

  /// Solo se sabe el [year].
  PublicationDate.ofYear(int year)
    : date = DateTime(year),
      precision = PublicationPrecision.year;

  /// Se sabe el [year] y el [month].
  PublicationDate.ofMonth(int year, int month)
    : date = DateTime(year, month),
      precision = PublicationPrecision.month;

  /// Se sabe el día completo.
  PublicationDate.ofDay(int year, int month, int day)
    : date = DateTime(year, month, day),
      precision = PublicationPrecision.day;

  /// Arma la fecha desde lo que se guarda: `Source.publishedAt` y la
  /// precisión de la referencia.
  ///
  /// Una fecha guardada sin precisión —lo que capturan una página web o
  /// YouTube, que traen el día— es una fecha de día completo. Una precisión
  /// «sin fecha» gana sobre cualquier fecha: es lo que alguien decidió.
  factory PublicationDate.fromStored(
    DateTime? publishedAt,
    PublicationPrecision? precision,
  ) {
    if (precision == PublicationPrecision.undated) {
      return const PublicationDate.undated();
    }
    if (publishedAt == null) return const PublicationDate.unknown();
    return PublicationDate(
      date: publishedAt,
      precision: precision ?? PublicationPrecision.day,
    );
  }

  /// La fecha, si se conoce. Solo el año, y el mes y el día si la precisión
  /// llega, dicen algo: lo demás es lo que quedó al armar el `DateTime`.
  final DateTime? date;

  /// Con qué exactitud se sabe. `null` si la fecha es desconocida.
  final PublicationPrecision? precision;

  /// Si nadie la cargó: es un dato que falta.
  bool get isUnknown =>
      date == null && precision != PublicationPrecision.undated;

  /// Si la obra no tiene fecha.
  bool get isUndated => precision == PublicationPrecision.undated;

  /// El año, o `null` si no se conoce.
  int? get year => date?.year;

  /// El mes (1 a 12), o `null` si la precisión no llega al mes.
  int? get month => switch (precision) {
    PublicationPrecision.month || PublicationPrecision.day => date?.month,
    _ => null,
  };

  /// El día del mes, o `null` si la precisión no llega al día.
  int? get day => precision == PublicationPrecision.day ? date?.day : null;

  @override
  bool operator ==(Object other) =>
      other is PublicationDate &&
      other.precision == precision &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(precision, year, month, day);

  @override
  String toString() {
    if (isUndated) return 'PublicationDate(sin fecha)';
    if (isUnknown) return 'PublicationDate(desconocida)';
    return 'PublicationDate($year-${month ?? '-'}-${day ?? '-'})';
  }
}
