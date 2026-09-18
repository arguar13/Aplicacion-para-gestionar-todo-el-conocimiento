/// Las dos clases de objeto que puede ser un elemento del modelo de
/// conocimiento: lo capturado del exterior, o lo que el usuario construye.
///
/// La distinción importa porque los dos tienen reglas y ciclos de vida
/// opuestos —ver [source]/[note]— y hasta ahora vivían mezclados en una
/// sola tabla. Ver la decisión de arquitectura sobre el modelo Fuente/Nota
/// en docs/arquitectura.md.
enum ItemKind {
  /// Una fuente: algo capturado del exterior, con procedencia. Inmutable y
  /// append-only —su texto nunca se edita ni se reescribe— y crece
  /// linealmente sin techo.
  source,

  /// Una nota: algo que el usuario construye. No tiene procedencia propia
  /// —tiene citas a fuentes—, es mutable y se refina con el tiempo.
  note,
}
