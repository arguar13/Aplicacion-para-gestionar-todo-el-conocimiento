/// El tamaño de un archivo, en la unidad que le sirve a una persona.
///
/// Nadie lee "3.613.707 bytes". Se usan potencias de 1024 —que es como miden
/// los sistemas de archivos— y un solo decimal a partir de los megabytes:
/// más precisión no cambia ninguna decisión.
String formatFileSize(int bytes) {
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
      ? value.toStringAsFixed(1)
      : value.round().toString();
  return '$rounded ${unidades[unit]}';
}
