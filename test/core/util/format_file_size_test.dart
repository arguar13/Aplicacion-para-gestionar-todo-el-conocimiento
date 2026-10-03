import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/format_file_size.dart';

/// El tamaño de un archivo, como lo lee una persona en el idioma de la app.
void main() {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;

  test('nadie lee "3.613.707 bytes"', () {
    expect(formatFileSize(512, 'es'), '512 B');
    expect(formatFileSize(40 * 1024, 'es'), '40 kB');
    expect(formatFileSize(3 * mb, 'es'), '3,0 MB');
    expect(formatFileSize(2 * gb, 'es'), '2,0 GB');
  });

  test('en español el decimal es una coma', () {
    expect(formatFileSize((19.1 * mb).round(), 'es'), '19,1 MB');
    expect(formatFileSize((3.7 * gb).round(), 'es'), '3,7 GB');
  });

  test('en inglés el decimal es un punto', () {
    expect(formatFileSize((19.1 * mb).round(), 'en'), '19.1 MB');
    expect(formatFileSize((3.7 * gb).round(), 'en'), '3.7 GB');
    expect(formatFileSize(512, 'en'), '512 B');
    expect(formatFileSize(40 * 1024, 'en'), '40 kB');
  });

  test('un idioma con región se escribe como su idioma', () {
    // Si la app llega a distinguir regiones, el decimal sigue siendo el
    // de su idioma.
    expect(formatFileSize((19.1 * mb).round(), 'es_AR'), '19,1 MB');
    expect(formatFileSize((19.1 * mb).round(), 'en_US'), '19.1 MB');
  });

  test('los bytes y los kilobytes van sin decimales', () {
    // "512,0 B" se lee peor que "512 B".
    expect(formatFileSize(1536, 'es'), '2 kB');
    expect(formatFileSize(0, 'es'), '0 B');
  });

  test('desde los megabytes, un decimal redondeado', () {
    expect(formatFileSize((1.96 * mb).round(), 'es'), '2,0 MB');
    expect(formatFileSize((1.94 * mb).round(), 'en'), '1.9 MB');
  });
}
