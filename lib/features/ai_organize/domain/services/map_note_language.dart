/// En qué idioma escribe la IA los textos fijos de una nota mapa (F27, el
/// Atlas): el título, los encabezados del índice y cuántos elementos quedaron
/// afuera.
///
/// Es el idioma de la app en el momento de escribirla —`AutoAtlasStep` lo
/// recibe de `effectiveLocaleProvider`—, no el de quien la lee después: una
/// nota es contenido de la bóveda, no interfaz, y no cambia de idioma sola.
/// Si la IA la actualiza porque entró material nuevo, reescribe el índice en
/// el idioma de ese momento; el título no, porque los `[[enlaces]]` de otras
/// notas lo nombran.
///
/// No vive en los `.arb`: la IA escribe desde la cola, sin `BuildContext`, y
/// estos textos son parte de la nota, no de una pantalla. Es una tabla tipada
/// y chica: cada idioma tiene que decirlo todo, y un idioma nuevo que se
/// olvide de algo no compila —los `switch` son exhaustivos—.
///
/// La introducción la escribe el modelo, que hoy responde siempre en español,
/// igual que en el resto de lo que genera (`GemmaChatModel`).
enum MapNoteLanguage {
  es,
  en;

  /// El de [languageCode]; inglés para cualquier otro, como la app: es el
  /// idioma base al que cae `effectiveLocaleProvider`.
  static MapNoteLanguage of(String languageCode) =>
      MapNoteLanguage.values.asNameMap()[languageCode] ?? MapNoteLanguage.en;

  /// El título de la nota mapa del tema [topic].
  String title(String topic) => switch (this) {
    es => 'Mapa de $topic',
    en => 'Map of $topic',
  };

  /// Lo que el índice lista sin subtemas: primero las notas…
  String get notesHeading => switch (this) {
    es => 'Notas',
    en => 'Notes',
  };

  /// …y después las fuentes.
  String get sourcesHeading => switch (this) {
    es => 'Fuentes',
    en => 'Sources',
  };

  /// Lo que va directo en el tema cuando tiene subtemas.
  String get generalHeading => switch (this) {
    es => 'General',
    en => 'General',
  };

  /// Cuántos elementos del tema no entraron en el índice ([count] > 0).
  String omitted(int count) => switch (this) {
    es when count == 1 => 'Hay 1 elemento más en este tema.',
    es => 'Hay $count elementos más en este tema.',
    en when count == 1 => 'There is 1 more item in this topic.',
    en => 'There are $count more items in this topic.',
  };
}
