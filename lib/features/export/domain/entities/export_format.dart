/// A qué formato se puede exportar un elemento.
enum ExportFormat {
  /// Con una cabecera YAML de procedencia. El formato de intercambio del
  /// proyecto: lo leen Obsidian, Logseq, Notion y cualquier editor.
  markdown,

  /// Sin marcado, para cuando solo importa poder pegar el contenido en
  /// cualquier lado sin símbolos de por medio.
  plainText,

  /// Para leer o imprimir fuera de la app.
  pdf;

  /// La extensión con la que se sugiere guardar el archivo, sin el punto.
  String get fileExtension => switch (this) {
    ExportFormat.markdown => 'md',
    ExportFormat.plainText => 'txt',
    ExportFormat.pdf => 'pdf',
  };
}
