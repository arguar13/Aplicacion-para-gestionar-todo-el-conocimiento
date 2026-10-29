/// Las diez tarjetas de crear de Repasar (F43, punto 4 del plan), en el orden
/// de la grilla: las tres de extraer juntas, después las siete de la IA.
///
/// [storageKey] es lo que se guarda en `study_creations.kind`: estable, no el
/// `name` de Dart —renombrar un caso no puede dejar huérfanas las creaciones
/// guardadas—. Uno que esta versión no conoce ([fromStorageKey] da `null`) es
/// de una app más nueva que llegó por la unión de bóvedas: se conserva y no se
/// muestra.
enum StudyCreationKind {
  /// «Extraer texto completo»: el texto procesado entero, con las palabras
  /// clave en rosa.
  fullText('full_text'),

  /// «Extraer resumen»: las oraciones que marcó el resumen, en orden.
  summary('summary'),

  /// «Extraer síntesis»: lo mismo con la síntesis.
  synthesis('synthesis'),

  /// Diapositivas con su diseño; en «Del presentador», con notas.
  presentation('presentation'),

  /// Un árbol de ideas que se abre y se cierra.
  mindMap('mind_map'),

  /// Un informe con secciones; el interactivo, con preguntas en cada una.
  report('report'),

  /// Un mazo de tarjetas didácticas, que por defecto suma al repaso.
  flashcards('flashcards'),

  /// Un cuestionario con la explicación de cada opción.
  quiz('quiz'),

  /// Una lámina con título, bloques, íconos, cifras y colores.
  infographic('infographic'),

  /// Una tabla de datos.
  dataTable('data_table');

  const StudyCreationKind(this.storageKey);

  /// Lo que se guarda en la base.
  final String storageKey;

  /// Si es una de las tres de extraer (decisión E): una **vista viva** sobre el
  /// resumen, la síntesis y las palabras clave del procesado. No le pide nada a
  /// la IA ni guarda contenido: crearla deja lista su fila enseguida, y lo que
  /// muestra cambia si el documento cambia.
  bool get isLiveView => switch (this) {
    fullText || summary || synthesis => true,
    presentation ||
    mindMap ||
    report ||
    flashcards ||
    quiz ||
    infographic ||
    dataTable => false,
  };

  /// Si la escribe la IA: todas menos las de extraer.
  bool get usesAi => !isLiveView;

  /// El tipo de [key], o `null` si esta versión no lo conoce.
  static StudyCreationKind? fromStorageKey(String key) {
    for (final kind in values) {
      if (kind.storageKey == key) return kind;
    }
    return null;
  }
}
