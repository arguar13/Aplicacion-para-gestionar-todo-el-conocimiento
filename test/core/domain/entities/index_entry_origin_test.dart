import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_indexer.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';

/// El origen con que se guarda una entrada del Índice (F46, v51): cada origen
/// de un título que lee el paso 1 se guarda con su mismo nombre, y el Índice
/// agrega solo las imágenes. Un origen nuevo del lector sin su lugar en la
/// base no compilaría en `indexEntryOriginOf`; esto dice además que el nombre
/// guardado es el mismo.
void main() {
  test('cada origen de un título se guarda con su mismo nombre', () {
    for (final origin in ProcessedHeadingOrigin.values) {
      expect(indexEntryOriginOf(origin).name, origin.name);
    }
  });

  test('lo único que agrega el Índice son las imágenes', () {
    expect(
      {for (final origin in IndexEntryOrigin.values) origin.name}.difference({
        for (final origin in ProcessedHeadingOrigin.values) origin.name,
      }),
      {IndexEntryOrigin.image.name},
    );
  });

  test('capítulos son los marcadores y los títulos, no «Texto completo» ni '
      'las imágenes', () {
    expect(
      {
        for (final origin in IndexEntryOrigin.values)
          if (origin.isChapter) origin,
      },
      {
        IndexEntryOrigin.bookmark,
        IndexEntryOrigin.textHeading,
        IndexEntryOrigin.aiTitle,
      },
    );
  });
}
