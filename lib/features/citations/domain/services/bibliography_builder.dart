import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/citation_names.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';

/// Arma la bibliografía de un conjunto de fuentes (F15): las ordena como lo
/// pide el estilo, distingue con una letra las obras del mismo autor y del
/// mismo año, numera las entradas de IEEE y da forma a cada una.
///
/// Es una función pura: quien la llama ya sabe cuáles son las fuentes —un
/// espacio, una rama del Atlas, una nota, una selección— y las trae con lo que
/// hace falta para citarlas.
///
/// Orden, como lo hacen las guías:
/// - alfabético por el apellido —y después el nombre— de cada persona que
///   figura de autor, sin distinguir mayúsculas ni acentos; una obra con menos
///   autores va antes que otra que empieza igual —«Smith» antes de «Smith y
///   Jones»—;
/// - en un estilo autor-fecha, las obras de un mismo autor van por año, con las
///   que no tienen fecha primero, y las de la misma fecha por título; en los
///   demás, por título;
/// - una obra sin autor va al final, por título: entre las demás empezaría con
///   un hueco y se perdería. Lo mismo una fuente cuyo año nadie cargó, dentro
///   de las de su autor.
///
/// Cada fuente entra una vez, aunque esté repetida en [sources].
Bibliography buildBibliography(
  Iterable<BibliographySource> sources, {
  required ReferenceStyle style,
  CitationLanguage language = CitationLanguage.es,
}) {
  final unique = <String, BibliographySource>{};
  for (final source in sources) {
    unique.putIfAbsent(source.itemId, () => source);
  }

  final authorDate = style.isAuthorDate;
  final keyed = [
    for (final source in unique.values) _Keyed(source, _SortKey.of(source)),
  ]..sort((a, b) => a.key.compareTo(b.key, authorDate: authorDate));

  final suffixes = authorDate ? _yearSuffixes(keyed) : const <String, String>{};

  final entries = <BibliographyEntry>[];
  for (var i = 0; i < keyed.length; i++) {
    final source = keyed[i].source;
    final number = style.isNumbered ? i + 1 : null;
    final suffix = suffixes[source.itemId];
    entries.add(
      BibliographyEntry(
        itemId: source.itemId,
        number: number,
        yearSuffix: suffix,
        citation: style.format(
          CitationForm.reference,
          source.source,
          CitationContext(
            language: language,
            number: number,
            yearSuffix: suffix,
          ),
        ),
      ),
    );
  }

  return Bibliography(
    styleId: style.id,
    title: style.listTitle(language),
    language: language,
    entries: entries,
  );
}

/// La letra de cada obra que comparte autor y año con otra: «a», «b», «c»…, en
/// el orden en que quedaron —el de su título—. Solo las de año conocido: una
/// obra sin fecha o de fecha desconocida no se distingue con una letra.
Map<String, String> _yearSuffixes(List<_Keyed> sorted) {
  final result = <String, String>{};
  var start = 0;
  while (start < sorted.length) {
    var end = start + 1;
    while (end < sorted.length &&
        sorted[end].key.sameAuthorsAndYear(sorted[start].key)) {
      end++;
    }
    if (end - start > 1 && sorted[start].key.year != null) {
      for (var i = start; i < end; i++) {
        result[sorted[i].source.itemId] = _letters(i - start);
      }
    }
    start = end;
  }
  return result;
}

/// «a» a «z» y, pasadas veintiséis, «aa», «ab»…
String _letters(int index) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz';
  var n = index;
  final buffer = StringBuffer();
  do {
    buffer.write(alphabet[n % 26]);
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return buffer.toString().split('').reversed.join();
}

class _Keyed {
  _Keyed(this.source, this.key);

  final BibliographySource source;
  final _SortKey key;
}

/// Lo que ordena una entrada: quién la escribió, cuándo y cómo se titula, todo
/// sin mayúsculas ni acentos.
class _SortKey {
  _SortKey({
    required this.names,
    required this.role,
    required this.year,
    required this.undated,
    required this.title,
    required this.itemId,
  });

  factory _SortKey.of(BibliographySource entry) {
    final source = entry.source;
    final lead = leadPeopleOf(source);
    final date = source.date;
    return _SortKey(
      names: [
        for (final name in lead.names)
          _sortText('${name.family}, ${name.given}'),
      ],
      role: lead.role.name,
      year: date.year,
      undated: date.isUndated,
      title: _titleKey(source.title),
      itemId: entry.itemId,
    );
  }

  /// Los autores, uno por uno, ya normalizados. Vacío si la obra no tiene.
  final List<String> names;

  /// El rol con que figuran, para no confundir «Franco, editor» con «Franco,
  /// autor».
  final String role;

  /// El año, o `null` si es desconocido o la obra no tiene fecha.
  final int? year;

  /// Si la obra no tiene fecha —a diferencia de una fecha desconocida—.
  final bool undated;

  final String title;

  /// Para que dos obras iguales queden siempre en el mismo orden.
  final String itemId;

  bool get anonymous => names.isEmpty;

  /// Si [other] tiene los mismos autores, con el mismo rol, y el mismo año.
  bool sameAuthorsAndYear(_SortKey other) =>
      role == other.role &&
      year == other.year &&
      !anonymous &&
      _sameList(names, other.names);

  int compareTo(_SortKey other, {required bool authorDate}) {
    if (anonymous != other.anonymous) return anonymous ? 1 : -1;

    if (!anonymous) {
      final byNames = _compareLists(names, other.names);
      if (byNames != 0) return byNames;
      final byRole = role.compareTo(other.role);
      if (byRole != 0) return byRole;
      if (authorDate) {
        final byDate = _dateRank.compareTo(other._dateRank);
        if (byDate != 0) return byDate;
        final ownYear = year;
        final otherYear = other.year;
        if (ownYear != null && otherYear != null && ownYear != otherYear) {
          return ownYear.compareTo(otherYear);
        }
      }
    }

    final byTitle = title.compareTo(other.title);
    if (byTitle != 0) return byTitle;
    return itemId.compareTo(other.itemId);
  }

  /// Sin fecha, primero; con año, por año; de fecha desconocida, al final.
  int get _dateRank => undated ? 0 : (year != null ? 1 : 2);
}

int _compareLists(List<String> a, List<String> b) {
  final shared = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shared; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length && _compareLists(a, b) == 0;

/// Los artículos que no cuentan al ordenar por título: «The», «El»…
const _leadingArticles = {
  'a',
  'an',
  'the',
  'el',
  'la',
  'los',
  'las',
  'un',
  'una',
  'unos',
  'unas',
};

/// El texto para ordenar: sin mayúsculas ni acentos, y con la «ñ» y la «ç»
/// donde el alfabeto las pone —«ñ» entre «n» y «o»— y no al final, que es
/// donde las deja el orden de los caracteres. Se escriben como su letra y el
/// último carácter posible: va después de cualquier otra cosa que siga a esa
/// letra y antes de la letra que viene.
String _sortText(String text) =>
    normalizeVocabularyLabel(text).replaceAll('ñ', 'n￿').replaceAll('ç', 'c￿');

/// El título para ordenar: como [_sortText] y sin el artículo del principio.
String _titleKey(String title) {
  final normalized = _sortText(title);
  final space = normalized.indexOf(' ');
  if (space > 0 && _leadingArticles.contains(normalized.substring(0, space))) {
    return normalized.substring(space + 1);
  }
  return normalized;
}
