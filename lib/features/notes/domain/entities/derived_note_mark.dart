/// La marca de procedencia de una nota generada (F16, D3): qué modelo la
/// escribió, cuándo, y si el usuario ya la tocó después de nacer.
class DerivedNoteMark {
  const DerivedNoteMark({
    required this.model,
    required this.generatedAt,
    required this.edited,
  });

  final String model;
  final DateTime generatedAt;

  /// Si el usuario ya editó el contenido después de generarse —«pasa a ser
  /// suya»—.
  final bool edited;
}
