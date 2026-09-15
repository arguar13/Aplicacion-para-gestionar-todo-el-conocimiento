/// A qué formato se puede exportar un elemento.
enum ExportFormat {
  /// Con una cabecera YAML de procedencia. El formato de intercambio del
  /// proyecto: lo leen Obsidian, Logseq, Notion y cualquier editor.
  markdown,

  /// Sin marcado, para cuando solo importa poder pegar el contenido en
  /// cualquier lado sin símbolos de por medio.
  plainText,

  /// Para leer o imprimir fuera de la app.
  pdf,

  /// La entrada de referencia bibliográfica, para llevarla a Zotero, LaTeX
  /// o cualquier gestor de citas que entienda el formato estándar.
  bibtex,

  /// Para abrir y seguir editando en Word, LibreOffice Writer o similares.
  docx;

  /// La extensión con la que se sugiere guardar el archivo, sin el punto.
  String get fileExtension => switch (this) {
    ExportFormat.markdown => 'md',
    ExportFormat.plainText => 'txt',
    ExportFormat.pdf => 'pdf',
    ExportFormat.bibtex => 'bib',
    ExportFormat.docx => 'docx',
  };
}
