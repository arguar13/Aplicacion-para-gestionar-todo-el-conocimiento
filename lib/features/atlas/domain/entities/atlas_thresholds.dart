/// Desde cuántas fuentes, sin ninguna nota viva en toda la rama, un tema se
/// avisa como un vacío (F13, D7): hay material de sobra y nadie escribió nada
/// propio con él.
const kAtlasManySources = 5;

/// Cuánto sin que se toque nada de una rama para avisarla como abandonada:
/// seis meses.
///
/// «Tocar» es que cambie —o entre— cualquiera de sus elementos: el Atlas mira
/// la fecha de actualización más reciente de la rama entera. Un mes de 30,4
/// días, redondeado: es un umbral de aviso, no un plazo.
const kAtlasStaleAfter = Duration(days: 183);
