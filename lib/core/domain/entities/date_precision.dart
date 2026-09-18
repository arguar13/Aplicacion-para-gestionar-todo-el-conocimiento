/// Qué tan precisa es una fecha histórica.
///
/// No todo lo que se sabe de un hecho tiene fecha exacta: "cayó Roma en el
/// 476" es una precisión de año, "el Imperio Romano de Occidente" es una
/// precisión de siglo. Forzar un día completo a algo que solo se sabe por
/// siglo perdería la honestidad de la fuente, no la ganaría.
enum DatePrecision { day, month, year, decade, century }
