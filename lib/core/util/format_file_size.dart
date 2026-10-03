import 'package:intl/intl.dart';

/// El tamaño de un archivo, en la unidad que le sirve a una persona y con
/// los números del idioma en que la lee.
///
/// Nadie lee "3.613.707 bytes". Se usan potencias de 1024 —que es como miden
/// los sistemas de archivos— y un solo decimal a partir de los megabytes:
/// más precisión no cambia ninguna decisión.
///
/// `locale` es el idioma de la app: el `localeName` de `AppLocalizations`,
/// que es el de la frase donde va el tamaño. El decimal es una coma en
/// español —«19,1 MB»— y un punto en inglés —«19.1 MB»—. `toStringAsFixed`
/// siempre escribe un punto, así que en español quedaba un número mal
/// escrito en cada tamaño de la app.
String formatFileSize(int bytes, String locale) {
  const unidades = ['B', 'kB', 'MB', 'GB'];

  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < unidades.length - 1) {
    value /= 1024;
    unit++;
  }

  // Los bytes y los kilobytes sin decimales: "512 B" y "40 kB" se leen mejor
  // que "512,0 B".
  final rounded = unit >= 2
      ? NumberFormat('0.0', locale).format(value)
      : value.round().toString();
  return '$rounded ${unidades[unit]}';
}
