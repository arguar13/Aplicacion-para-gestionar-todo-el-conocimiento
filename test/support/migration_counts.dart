/// Los conteos de una bóveda migrada hasta la última versión, sin la categoría
/// de sistema «Autor» que la migración a v22 le agrega (F15).
///
/// Las pruebas de migración de versiones anteriores comparan cuántas filas
/// había en cada tabla antes y después, y migran hasta el FINAL: una bóveda de
/// v16 termina en la última versión, y ahí `property_definitions` trae una
/// categoría que la de antes no tenía. Lo que esas pruebas afirman —que la
/// migración no pierde ni inventa nada de lo que el usuario creó— sigue siendo
/// cierto; solo hay que descontar lo que la app siembra por su cuenta.
///
/// [counts] es el resultado de contar las filas de cada tabla, por nombre.
Map<String, int> withoutAuthorCategory(Map<String, int> counts) => {
  for (final entry in counts.entries)
    entry.key: entry.key == 'property_definitions'
        ? entry.value - 1
        : entry.value,
};
