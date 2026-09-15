/// En qué formato se redacta una cita.
///
/// Las tres que cubre la mayoría de los trabajos académicos y de
/// divulgación en español y en inglés. Ninguna estilo IEEE ni Vancouver a
/// propósito: son de uso casi exclusivo de ingeniería y medicina
/// respectivamente, y sumarlas antes de que alguien las pida sería
/// complejidad sin un caso de uso real detrás.
enum CitationStyle {
  apa,
  mla,
  chicago,
}

// Nota: BibTeX no tiene "estilo APA" o "estilo MLA" —el estilo final lo
// decide quien procesa el `.bib` después, no quien lo genera—, así que
// este enum solo importa para la cita en texto, no para la exportación a
// BibTeX.
