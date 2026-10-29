import 'package:sinapsis/core/domain/entities/processed_section.dart';

/// Cuánto trabajó la persona un documento procesado (F41, paso 6): lo que el
/// Atlas y el tablero del Mapa cuentan de cada uno.
///
/// Desde F41 el Atlas, el Mapa y la Línea de tiempo leen solo lo procesado,
/// así que la escalera de antes —fuentes, fragmentos, notas vivas— ya no
/// describe lo que hay. Esta sale de las partes que la persona eligió al
/// triar, de menos a más suyo: el texto copiado tal cual, lo que destiló de
/// él —el resumen o la síntesis—, los pasajes que cortó a mano y lo que
/// escribió ella misma. Un documento cuenta en el escalón MÁS ALTO que
/// alcanza: uno con notas y resumen es «con notas».
///
/// Van de menos a más, así que `index` sirve para comparar.
enum ProcessedDepth {
  /// Solo el texto —lo que deja «Pasar todo sin modificar»—, o nada todavía.
  textOnly,

  /// Con el resumen o la síntesis: la persona eligió qué se queda.
  summarized,

  /// Con fragmentos cortados a mano del original.
  cut,

  /// Con notas propias: lo que la persona escribió.
  annotated;

  /// Las secciones que suben a un documento a este escalón; vacío en el
  /// primero, al que llega cualquier documento.
  Set<ProcessedSection> get sections => switch (this) {
    textOnly => const {},
    summarized => const {ProcessedSection.summary, ProcessedSection.synthesis},
    cut => const {ProcessedSection.fragments},
    annotated => const {ProcessedSection.notes},
  };
}
