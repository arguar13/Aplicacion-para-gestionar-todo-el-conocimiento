/// Quién hizo un vínculo o una tarjeta (F27): la persona o la IA.
///
/// No es una marca de calidad sino de procedencia, como `ItemPropertyOrigin`
/// para las propiedades: dice qué se puede deshacer de un saque —lo que sigue
/// siendo de la IA— y qué no se toca nunca —lo de la persona—.
///
/// Lo que la IA hizo y la persona después editó pasa a ser [user]: editarlo es
/// adoptarlo, y «deshacer todo» no se lleva lo que alguien ya hizo suyo.
enum ContentOrigin {
  /// Lo hizo la persona, o lo adoptó al editarlo. Todo lo de antes de F27.
  user,

  /// Lo aplicó la IA sola, en una pasada (`ai_runs`) que se puede deshacer.
  ai,
}
