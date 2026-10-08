import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/domain/entities/source_extent.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pending_facts.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Los datos de la tarjeta de la Bandeja (F30, decisión 68): autor, fecha,
/// sitio, páginas o duración e idioma; solo los que se saben.
void main() {
  final es = AppLocalizationsEs();
  final captured = DateTime(2026, 10, 1, 9);

  setUpAll(() => initializeDateFormatting('es'));

  Source source({
    String? url,
    String? author,
    DateTime? published,
    String? language,
  }) => Source(
    id: 's',
    kind: SourceKind.webPage,
    capturedAt: captured,
    url: url,
    authorName: author,
    publishedAt: published,
    language: language,
  );

  List<String> texts(Source source, [SourceExtent? extent]) => [
    for (final fact in pendingFactsOf(
      source,
      extent ?? SourceExtent.none,
      es,
      'es',
    ))
      fact.text,
  ];

  test('autor, fecha, sitio, páginas e idioma, en ese orden', () {
    final facts = pendingFactsOf(
      source(
        url: 'https://www.ejemplo.org/articulos/roma',
        author: '  Mary Beard ',
        published: DateTime(2019, 3, 14),
        language: 'en',
      ),
      const SourceExtent(pages: 248),
      es,
      'es',
    );

    expect(
      [for (final f in facts) f.text],
      ['Mary Beard', '14 mar 2019', 'ejemplo.org', '248 páginas', 'English'],
    );
    // Cada uno se anuncia con su rótulo, no solo con su valor.
    expect(facts.first.semantics, '${es.inboxFactAuthor}: Mary Beard');
    expect(facts.last.semantics, '${es.inboxFactLanguage}: English');
  });

  test('solo los que se saben: lo que falta no se rellena', () {
    expect(texts(source()), isEmpty);
    expect(texts(source(author: '   ')), isEmpty);
    expect(texts(source(url: 'https://ejemplo.org/a')), ['ejemplo.org']);
  });

  group('el sitio', () {
    test('sin el «www.» y sin el camino', () {
      expect(siteOf('https://www.nytimes.com/2026/a?x=1'), 'nytimes.com');
      expect(siteOf('https://es.wikipedia.org/wiki/Roma'), 'es.wikipedia.org');
    });

    test('un archivo local o una nota no tienen sitio', () {
      expect(siteOf(null), isNull);
      expect(siteOf(''), isNull);
      expect(siteOf('no es una dirección'), isNull);
    });
  });

  group('la extensión', () {
    test('las páginas, en singular y en plural', () {
      expect(extentText(const SourceExtent(pages: 1), es), '1 página');
      expect(extentText(const SourceExtent(pages: 12), es), '12 páginas');
    });

    test('la duración, en minutos o en horas y minutos', () {
      String? of(Duration d) => extentText(SourceExtent(duration: d), es);

      expect(of(const Duration(seconds: 20)), '1 min');
      expect(of(const Duration(minutes: 7, seconds: 59)), '7 min');
      expect(of(const Duration(minutes: 60)), '1 h 0 min');
      expect(of(const Duration(hours: 1, minutes: 12)), '1 h 12 min');
    });

    test('sin ninguna de las dos no se dice nada; las páginas mandan', () {
      expect(extentText(SourceExtent.none, es), isNull);
      expect(
        extentText(
          const SourceExtent(pages: 3, duration: Duration(minutes: 5)),
          es,
        ),
        '3 páginas',
      );
    });
  });

  test('un audio muestra lo que dura y su idioma, nunca un reproductor', () {
    final facts = pendingFactsOf(
      source(language: 'es'),
      const SourceExtent(duration: Duration(minutes: 42)),
      es,
      'es',
    );

    expect([for (final f in facts) f.text], ['42 min', 'Español']);
  });
}
