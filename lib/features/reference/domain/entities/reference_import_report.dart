import 'package:meta/meta.dart';

/// Una entrada del archivo que no se pudo importar, y por qué —F15, D15.3:
/// «una entrada que no se entiende se reporta y se salta, nunca se guarda a
/// medias»—.
@immutable
class ReferenceImportSkip {
  const ReferenceImportSkip({required this.key, required this.reason});

  /// La clave de cita, o el identificador que traía la entrada —lo que haya
  /// para que la persona sepa CUÁL fue, dentro de un archivo de miles—.
  final String key;

  final String reason;
}

/// El resultado de importar un archivo entero (F15, D15.3): cuántas
/// entradas se crearon, se completaron, ya estaban idénticas, ganaron un
/// adjunto, o se saltaron y por qué.
@immutable
class ReferenceImportReport {
  const ReferenceImportReport({
    this.created = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.attached = 0,
    this.possibleDuplicates = 0,
    this.skipped = const [],
  });

  final int created;
  final int updated;
  final int unchanged;

  /// Cuántas ganaron el PDF que traía su propio `file`/`L1` (D14).
  final int attached;

  /// Cuántas propuestas de posible duplicado se mandaron a F7 (D9).
  final int possibleDuplicates;

  final List<ReferenceImportSkip> skipped;

  /// Cuántas entradas traía el archivo en total, entendidas o no.
  int get total => created + updated + unchanged + skipped.length;

  ReferenceImportReport operator +(ReferenceImportReport other) =>
      ReferenceImportReport(
        created: created + other.created,
        updated: updated + other.updated,
        unchanged: unchanged + other.unchanged,
        attached: attached + other.attached,
        possibleDuplicates: possibleDuplicates + other.possibleDuplicates,
        skipped: [...skipped, ...other.skipped],
      );
}
