/// Qué tan cerca está un candidato a duplicado del elemento semilla — F7,
/// deduplicación.
///
/// Vive en `core` y no en `features/duplicates`, igual que `RelationKind`
/// para F5: tanto `DuplicateCandidateSelector` como `Suggestion.duplicate`
/// necesitan el mismo vocabulario, y `Suggestion` —en `core`— no puede
/// depender de una `feature` sin invertir la dependencia.
enum DuplicateMatchKind {
  /// `dedupHash` igual: mismo texto normalizado, byte a byte.
  exact,

  /// Distancia de Hamming del `simhash` dentro del umbral, pero
  /// `dedupHash` distinto — casi-duplicado, no exacto.
  near,

  /// Mismo título (sin distinguir mayúsculas ni acentos), mismo año y mismo
  /// primer autor —F15, D9—: la coincidencia que propone una importación de
  /// referencias sin texto que comparar, así que ni `dedupHash` ni `simhash`
  /// sirven acá.
  bibliographic,
}
