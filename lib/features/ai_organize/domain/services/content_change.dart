import 'package:sinapsis/core/domain/services/dedup_fingerprint.dart';

/// Cuántos de los 64 bits de la huella (`simhashOf`, la de los
/// casi-duplicados de la decisión 40) tienen que haber cambiado para que una
/// nota ya organizada se vuelva a organizar (F27): que cambió de contenido, no
/// de largo.
///
/// Medido con textos de 40 a 2000 palabras, 40 de cada uno (distancia mínima,
/// mediana y máxima):
///
/// | cambio                                  | mín | med | máx |
/// |-----------------------------------------|-----|-----|-----|
/// | una coma, una mayúscula                 |   0 |   0 |   0 |
/// | una palabra (en 40 palabras)            |   2 |   8 |  14 |
/// | una palabra (en 150 o más)              |   0 | 1–4 |   8 |
/// | un párrafo nuevo del 30 %               |   3 |  10 |  20 |
/// | la mitad reescrita                      |  15 |  21 |  31 |
/// | otro texto del mismo largo              |  22 |  32 |  41 |
///
/// Con 16, un retoque —una coma, una palabra, un dato corregido— nunca
/// alcanza, y una nota reescrita, aunque tenga el mismo largo, siempre: lo que
/// la medida por el largo no veía. Lo que se agrega sin tocar lo demás cuenta
/// cuando llega a ser como lo que había (duplicar la nota da unos 16): un
/// párrafo suelto no vale otra tanda de tarjetas y vínculos.
///
/// En una nota de pocas palabras cada una pesa mucho —la huella se arma de
/// tríos de palabras, y una nota de dos tiene uno solo—: ahí agregar una
/// palabra ya es cambiarla.
const kNoteRegrowHammingBits = 16;

/// La huella de [text] para comparar su contenido: la misma de los
/// casi-duplicados, sobre el texto normalizado (sin mayúsculas, puntuación
/// ni espacios de más).
String contentSimhashOf(String text) => simhashOf(normalizeForDedup(text));

/// Si el contenido con huella [now] cambió lo suficiente respecto del que
/// tenía huella [before] como para volver a organizarlo.
bool contentChangedMuch(String before, String now) =>
    hammingDistance(before, now) >= kNoteRegrowHammingBits;
