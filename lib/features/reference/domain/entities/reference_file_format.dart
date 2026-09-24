/// El formato de un archivo bibliográfico que la app entiende (F15): entra
/// con `ImportReferencesFileUseCase`, sale con `ExportReferencesUseCase`.
enum ReferenceFileFormat {
  bibtex,
  ris;

  /// La extensión con la que se sugiere guardar el archivo, con el punto —la
  /// misma que `ImportReferencesFileUseCase._findBibliographyFile` reconoce
  /// al importar.
  String get fileExtension => switch (this) {
    ReferenceFileFormat.bibtex => '.bib',
    ReferenceFileFormat.ris => '.ris',
  };
}
