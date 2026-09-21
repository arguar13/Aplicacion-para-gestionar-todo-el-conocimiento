import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';

/// Las palabras y las fechas con que un estilo escribe una cita, en español y
/// en inglés (F15): «y» o «and», «Ed.», «pp.», «s. f.» o «n.d.», «En» o «In»,
/// los meses.
///
/// Son datos puros y no cadenas de los ARB porque los usa el dominio, que no
/// tiene contexto ni idioma de interfaz: una cita se puede pedir en un idioma
/// distinto del de la app —una referencia en inglés en un trabajo en
/// español—, y los estilos son funciones puras que no saben de pantallas.
class CitationTerms {
  const CitationTerms({
    required this.and,
    required this.ampersand,
    required this.serialComma,
    required this.dayFirst,
    required this.etAl,
    required this.editor,
    required this.editors,
    required this.translator,
    required this.translators,
    required this.director,
    required this.directors,
    required this.page,
    required this.pages,
    required this.noDate,
    required this.inWord,
    required this.editionAbbr,
    required this.missing,
    required this.thesis,
    required this.video,
    required this.documentary,
    required this.months,
    required this.monthsShort,
    required this.monthsIeee,
    required this.quoteOpen,
    required this.quoteClose,
    required this.quotePunctuationInside,
    required this.translatedBy,
    required this.editedBy,
    required this.editorRole,
    required this.editorsRole,
    required this.directorRole,
    required this.directorsRole,
    required this.volumeAbbr,
    required this.numberAbbr,
    required this.accessed,
    required this.ieeeAccessed,
    required this.ieeeOnline,
    required this.gapLabels,
    required this.ordinal,
    required this.longDate,
    required this.retrieved,
  });

  /// El idioma pedido.
  factory CitationTerms.of(CitationLanguage language) => switch (language) {
    CitationLanguage.es => es,
    CitationLanguage.en => en,
  };

  static const es = CitationTerms(
    and: 'y',
    ampersand: 'y',
    serialComma: false,
    dayFirst: true,
    etAl: 'et al.',
    editor: 'Ed.',
    editors: 'Eds.',
    translator: 'Trad.',
    translators: 'Trads.',
    director: 'Dir.',
    directors: 'Dirs.',
    page: 'p.',
    pages: 'pp.',
    noDate: 's. f.',
    inWord: 'En',
    editionAbbr: 'ed.',
    missing: 'falta',
    thesis: 'Tesis',
    video: 'Video',
    documentary: 'Documental',
    months: [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ],
    monthsShort: _spanishMonthsShort,
    monthsIeee: _spanishMonthsShort,
    quoteOpen: '«',
    quoteClose: '»',
    quotePunctuationInside: false,
    translatedBy: 'traducción de',
    editedBy: 'edición de',
    editorRole: 'ed.',
    editorsRole: 'eds.',
    directorRole: 'dir.',
    directorsRole: 'dirs.',
    volumeAbbr: 'vol.',
    numberAbbr: 'núm.',
    accessed: 'Consultado el',
    ieeeAccessed: 'Consultado:',
    ieeeOnline: '[En línea]. Disponible en:',
    gapLabels: {
      CitationGap.author: 'autor',
      CitationGap.title: 'título',
      CitationGap.year: 'año',
      CitationGap.publisher: 'editorial',
      CitationGap.container: 'publicado en',
      CitationGap.volume: 'volumen',
      CitationGap.link: 'enlace',
      CitationGap.type: 'tipo de obra',
      CitationGap.accessed: 'fecha de consulta',
    },
    ordinal: _spanishOrdinal,
    longDate: _spanishLongDate,
    retrieved: _spanishRetrieved,
  );

  static const en = CitationTerms(
    and: 'and',
    ampersand: '&',
    serialComma: true,
    dayFirst: false,
    etAl: 'et al.',
    editor: 'Ed.',
    editors: 'Eds.',
    translator: 'Trans.',
    translators: 'Trans.',
    director: 'Director',
    directors: 'Directors',
    page: 'p.',
    pages: 'pp.',
    noDate: 'n.d.',
    inWord: 'In',
    editionAbbr: 'ed.',
    missing: 'missing',
    thesis: 'Thesis',
    video: 'Video',
    documentary: 'Documentary',
    months: [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ],
    monthsShort: [
      'Jan.',
      'Feb.',
      'Mar.',
      'Apr.',
      'May',
      'June',
      'July',
      'Aug.',
      'Sept.',
      'Oct.',
      'Nov.',
      'Dec.',
    ],
    monthsIeee: [
      'Jan.',
      'Feb.',
      'Mar.',
      'Apr.',
      'May',
      'Jun.',
      'Jul.',
      'Aug.',
      'Sep.',
      'Oct.',
      'Nov.',
      'Dec.',
    ],
    quoteOpen: '“',
    quoteClose: '”',
    quotePunctuationInside: true,
    translatedBy: 'translated by',
    editedBy: 'edited by',
    editorRole: 'editor',
    editorsRole: 'editors',
    directorRole: 'director',
    directorsRole: 'directors',
    volumeAbbr: 'vol.',
    numberAbbr: 'no.',
    accessed: 'Accessed',
    ieeeAccessed: 'Accessed:',
    ieeeOnline: '[Online]. Available:',
    gapLabels: {
      CitationGap.author: 'author',
      CitationGap.title: 'title',
      CitationGap.year: 'year',
      CitationGap.publisher: 'publisher',
      CitationGap.container: 'published in',
      CitationGap.volume: 'volume',
      CitationGap.link: 'link',
      CitationGap.type: 'type of work',
      CitationGap.accessed: 'access date',
    },
    ordinal: _englishOrdinal,
    longDate: _englishLongDate,
    retrieved: _englishRetrieved,
  );

  /// «y» / «and»: la conjunción de una lista de nombres.
  final String and;

  /// Lo que APA escribe antes del último autor: «y» en español, «&» en inglés.
  final String ampersand;

  /// Si una lista lleva coma antes de la conjunción: «A, B, & C» en inglés,
  /// «A, B y C» en español —donde la coma antes de «y» no se escribe—.
  final bool serialComma;

  /// Si en una fecha el día va antes que el mes —«15 de marzo»— y no después
  /// —«March 15»—.
  final bool dayFirst;

  /// «et al.»: cuando son demasiados nombres para escribirlos todos.
  final String etAl;

  /// «Ed.» y «Eds.».
  final String editor;
  final String editors;

  /// «Trad.» y «Trads.».
  final String translator;
  final String translators;

  /// «Dir.» y «Dirs.».
  final String director;
  final String directors;

  /// «p.» y «pp.».
  final String page;
  final String pages;

  /// «s. f.» / «n.d.»: la obra no tiene fecha.
  final String noDate;

  /// «En» / «In»: el libro que contiene un capítulo.
  final String inWord;

  /// «ed.».
  final String editionAbbr;

  /// «falta» / «missing»: lo que va antes del dato en un hueco.
  final String missing;

  /// El nombre de una tesis, para el corchete que la describe.
  final String thesis;

  /// «Video» y «Documental»: cómo se describe una obra audiovisual.
  final String video;
  final String documentary;

  /// Los doce meses, con su nombre completo.
  final List<String> months;

  /// Los meses abreviados como los escribe MLA: «mar.», «Sept.».
  final List<String> monthsShort;

  /// Los meses abreviados como los escribe IEEE: «mar.», «Sep.».
  final List<String> monthsIeee;

  /// Las comillas de un título: «“Title”» en inglés, ««Título»» en español.
  final String quoteOpen;
  final String quoteClose;

  /// Si el punto o la coma que siguen a un título entrecomillado van adentro
  /// de las comillas —«“Title.”», como en inglés— o afuera —«Título».—, como
  /// en español.
  final bool quotePunctuationInside;

  /// «traducción de» / «translated by» y «edición de» / «edited by»: cómo MLA
  /// nombra a quien colaboró en una obra que no es suya. Van en minúscula; el
  /// estilo las capitaliza cuando empiezan un elemento.
  final String translatedBy;
  final String editedBy;

  /// El rol escrito después de un nombre, como lo hace MLA: «Smith, John,
  /// editor.». En español se abrevia —«ed.», «dir.»— y no hay que elegir
  /// género.
  final String editorRole;
  final String editorsRole;
  final String directorRole;
  final String directorsRole;

  /// «vol.» y «núm.» / «no.».
  final String volumeAbbr;
  final String numberAbbr;

  /// «Consultado el» / «Accessed»: lo que MLA escribe antes de la fecha en que
  /// se miró una página web.
  final String accessed;

  /// «Consultado:» / «Accessed:» y `[En línea]. Disponible en:` /
  /// `[Online]. Available:`: lo que IEEE escribe antes de la fecha de consulta
  /// y antes del enlace.
  final String ieeeAccessed;
  final String ieeeOnline;

  /// Cómo se llama cada dato que puede faltar.
  final Map<CitationGap, String> gapLabels;

  /// «2.ª» / «2nd».
  final String Function(int number) ordinal;

  /// «5 de septiembre de 2026» / «September 5, 2026».
  final String Function(CitationTerms terms, DateTime date) longDate;

  /// «Recuperado el 5 de septiembre de 2026, de {url}» / «Retrieved September
  /// 5, 2026, from {url}».
  final String Function(CitationTerms terms, DateTime date, String url)
  retrieved;

  /// El hueco que dice que falta [gap], en este idioma: «[falta: año]».
  GapRun gap(CitationGap gap) =>
      GapRun(field: gap, text: '[$missing: ${gapLabels[gap]}]');

  /// El nombre del mes [month] (1 a 12).
  String monthName(int month) => months[month - 1];

  /// La fecha como la escribe MLA: «5 mar. 2020», «mar. 2020», «2020». El día
  /// va antes que el mes en los dos idiomas.
  String mlaDate(int year, {int? month, int? day}) {
    if (month == null) return '$year';
    final name = monthsShort[month - 1];
    return day == null ? '$name $year' : '$day $name $year';
  }

  /// La fecha como la escribe IEEE: «Mar. 5, 2020», «Mar. 2020», «2020» en
  /// inglés; «5 mar. 2020» en español.
  String ieeeDate(int year, {int? month, int? day}) {
    if (month == null) return '$year';
    final name = monthsIeee[month - 1];
    if (day == null) return '$name $year';
    return dayFirst ? '$day $name $year' : '$name $day, $year';
  }

  /// La fecha que APA escribe entre paréntesis después del año: «2019, 15 de
  /// marzo» / «2019, March 15». Solo el año, o el año y el mes, si no se sabe
  /// más.
  String apaDate(int year, {int? month, int? day}) {
    if (month == null) return '$year';
    final name = monthName(month);
    if (day == null) return '$year, $name';
    return dayFirst ? '$year, $day de $name' : '$year, $name $day';
  }
}

const _spanishMonthsShort = [
  'ene.',
  'feb.',
  'mar.',
  'abr.',
  'mayo',
  'jun.',
  'jul.',
  'ago.',
  'sept.',
  'oct.',
  'nov.',
  'dic.',
];

String _spanishOrdinal(int number) => '$number.ª';

String _englishOrdinal(int number) {
  final lastTwo = number % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return '${number}th';
  return switch (number % 10) {
    1 => '${number}st',
    2 => '${number}nd',
    3 => '${number}rd',
    _ => '${number}th',
  };
}

String _spanishLongDate(CitationTerms terms, DateTime date) =>
    '${date.day} de ${terms.monthName(date.month)} de ${date.year}';

String _englishLongDate(CitationTerms terms, DateTime date) =>
    '${terms.monthName(date.month)} ${date.day}, ${date.year}';

String _spanishRetrieved(CitationTerms terms, DateTime date, String url) =>
    'Recuperado el ${terms.longDate(terms, date)}, de $url';

String _englishRetrieved(CitationTerms terms, DateTime date, String url) =>
    'Retrieved ${terms.longDate(terms, date)}, from $url';
