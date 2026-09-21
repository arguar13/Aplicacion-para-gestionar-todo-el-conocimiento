/// El nivel más hondo que admite la jerarquía de un vocabulario (F13).
///
/// `PropertyValue.depth` cuenta desde 0 —un valor sin padre—, así que con este
/// tope el árbol tiene CINCO niveles: «Roma» (0), «Roma republicana» (1),
/// «Reformas de los Gracos» (2), y dos más. Más hondo no se lee: un árbol que
/// necesita seis niveles pide ser dos categorías.
///
/// Lo hace cumplir la base misma —una restricción `CHECK` sobre `depth`— y no
/// solo la pantalla: mover una rama que pasaría de este nivel revierte toda la
/// transacción.
const kVocabularyMaxDepth = 4;
