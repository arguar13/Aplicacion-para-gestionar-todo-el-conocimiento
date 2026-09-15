import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/domain/services/bibtex_formatter.dart';

void main() {
  KnowledgeItem buildItem({
    String title = 'Un artículo cualquiera',
    SourceKind kind = SourceKind.webPage,
    String? authorName,
    String? url,
    DateTime? publishedAt,
    DateTime? capturedAt,
    DateTime? updatedAt,
  }) {
    final captured = capturedAt ?? DateTime(2026, 9, 14);
    return KnowledgeItem(
      id: 'item-1',
      title: title,
      source: Source(
        id: 'source-1',
        kind: kind,
        capturedAt: captured,
        authorName: authorName,
        url: url,
        publishedAt: publishedAt,
      ),
      processingState: ProcessingState.ready,
      createdAt: captured,
      updatedAt: updatedAt ?? captured,
    );
  }

  test('con un enlace, la entrada es @online', () {
    final item = buildItem(url: 'https://ejemplo.org/articulo');

    expect(formatBibtex(item), startsWith('@online{'));
  });

  test('sin ningún enlace, la entrada es @misc', () {
    final item = buildItem(kind: SourceKind.manualNote);

    expect(formatBibtex(item), startsWith('@misc{'));
  });

  test('trae título, autor, año y URL como campos', () {
    final item = buildItem(
      title: 'Un artículo con título',
      authorName: 'Autora Ejemplo',
      url: 'https://ejemplo.org/articulo',
      publishedAt: DateTime(2020),
    );

    final bibtex = formatBibtex(item);

    expect(bibtex, contains('title = {Un artículo con título}'));
    expect(bibtex, contains('author = {Autora Ejemplo}'));
    expect(bibtex, contains('year = {2020}'));
    expect(bibtex, contains('url = {https://ejemplo.org/articulo}'));
  });

  test('la clave se arma con el apellido... o la primera palabra del '
      'autor, más el año, sin acentos ni espacios', () {
    final item = buildItem(
      authorName: 'María Ñáñez',
      publishedAt: DateTime(2021),
    );

    final bibtex = formatBibtex(item);

    expect(bibtex, startsWith('@misc{maria2021,'));
  });

  test('sin autor, la clave usa la primera palabra del título', () {
    final item = buildItem(
      title: 'Fotosíntesis y metabolismo',
      publishedAt: DateTime(2019),
    );

    final bibtex = formatBibtex(item);

    expect(bibtex, startsWith('@misc{fotosintesis2019,'));
  });

  test('sin fecha de publicación, la clave usa el año de captura', () {
    // capturedAt por defecto ya es 2026: alcanza para probar que la clave
    // cae en ese año cuando no hay fecha de publicación.
    final item = buildItem(authorName: 'Alguien');

    final bibtex = formatBibtex(item);

    expect(bibtex, startsWith('@misc{alguien2026,'));
  });

  test('sin año de publicación, no hay campo "year"', () {
    final item = buildItem(authorName: 'Alguien');

    expect(formatBibtex(item), isNot(contains('year =')));
  });

  test('el tipo de fuente queda anotado en la nota', () {
    final item = buildItem(kind: SourceKind.youtube, authorName: 'Canal');

    expect(formatBibtex(item), contains('note = {Video de YouTube}'));
  });

  test('una llave dentro de un valor se escapa, no corta el campo', () {
    final item = buildItem(title: 'Un título con {llaves}');

    expect(
      formatBibtex(item),
      contains(r'title = {Un título con \{llaves\}}'),
    );
  });
}
