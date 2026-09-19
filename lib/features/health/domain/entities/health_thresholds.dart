/// Por encima de esta cantidad de elementos pendientes en la Bandeja, se está
/// capturando más de lo que se digiere.
///
/// El encargo pide que sea un umbral "sostenido", pero la Bandeja no guarda
/// historial de cuántos había cada día: no hay de dónde medir la
/// sostenibilidad. Es un umbral sobre el conteo de ahora, y se dice así.
const kInboxWarningThreshold = 50;

/// Cuánto hacia atrás cuenta "esta semana" para las notas que crecieron.
const kGrowthWindow = Duration(days: 7);

/// Desde cuántas notas atómicas empieza a importar que haya pocas vivas. Con
/// menos, una bóveda joven que todavía no construyó nada no es una señal.
const kFragmentWarningMinAtomic = 20;

/// Cuántas atómicas por cada nota viva se toleran antes de avisar que se están
/// acumulando fragmentos sin construir entendimiento.
const kFragmentWarningRatio = 5;
