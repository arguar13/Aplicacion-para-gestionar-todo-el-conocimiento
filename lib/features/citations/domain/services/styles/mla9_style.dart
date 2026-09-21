import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/citation_builder.dart';
import 'package:sinapsis/features/citations/domain/services/citation_names.dart';
import 'package:sinapsis/features/citations/domain/services/citation_terms.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';

/// MLA 9.ª edición (F15): la entrada de la lista de obras citadas y la cita en
/// el texto, para los ocho tipos de obra.
///
/// Una entrada de MLA es una serie de elementos —el autor, el título de la obra
/// y, dentro de su «contenedor», quien colaboró, la edición, el volumen, la
/// editorial, la fecha y el lugar— que se separan con comas y se cierran con un
/// punto. Lo que el manual pide y la fuente no tiene se escribe como un hueco;
/// lo que deja opcional y falta no se marca.
///
/// Decisiones, dichas para poder objetarlas:
/// - Una obra sin autor marca el hueco de autor: MLA empezaría por el título,
///   pero acá casi siempre es que todavía no se cargó.
/// - Las páginas van con guion —«pp. 45-67»— y completas, sin acortar el
///   segundo número.
/// - Un libro, un capítulo y una tesis citan solo el año, y una revista con
///   volumen también; lo demás, hasta donde se sabe la fecha.
/// - Una dirección se escribe sin «https://»; un DOI sí, porque es un enlace.
/// - La fecha de consulta —«Accessed 5 Sept. 2026»— se escribe si alguien la
///   cargó y, en una obra de la web que no dice cuándo se publicó, con la de
///   captura: es el caso en que MLA la recomienda.
/// - En español la coma que separa un nombre invertido del que sigue se
///   conserva antes de «y» —«García, Ana, y Luis Paz»—, como en la estructura
///   de MLA.
///
/// Lo que esta versión no hace: no empieza por el título una obra cuyo autor
/// es también su editorial, no dice «uploaded by» en un video y una tesis se
/// describe como «tesis» a secas, sin el grado.
class Mla9Style implements ReferenceStyle {
  const Mla9Style();

  @override
  String get id => 'mla9';

  @override
  String get name => 'MLA 9';

  @override
  Set<CitationForm> get forms => const {
    CitationForm.reference,
    CitationForm.inText,
  };

  @override
  bool get isNumbered => false;

  @override
  Citation format(
    CitationForm form,
    CitationSource source,
    CitationContext context,
  ) => switch (form) {
    CitationForm.reference => _reference(source, context),
    CitationForm.inText => _inText(source, context),
    CitationForm.note || CitationForm.shortNote => const Citation.empty(),
  };

  // -------------------------------------------------------------------------
  // La entrada de la lista de obras citadas
  // -------------------------------------------------------------------------

  Citation _reference(CitationSource source, CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms);

    _writeAuthors(builder, source, terms);
    builder.space();

    switch (source.type) {
      case ReferenceType.book:
        _book(builder, source, terms);
      case ReferenceType.chapter:
        _chapter(builder, source, terms);
      case ReferenceType.article:
        _article(builder, source, terms);
      case ReferenceType.thesis:
        _thesis(builder, source, terms);
      case ReferenceType.primarySource || ReferenceType.other:
        _standalone(builder, source, terms, markType: false);
      case ReferenceType.documentary:
        _audiovisual(builder, source, terms);
      case ReferenceType.website:
        _webPage(builder, source, terms, quoteWithoutSite: false);
      case ReferenceType.onlinePublication:
        _webPage(builder, source, terms, quoteWithoutSite: true);
      case null:
        // Sin tipo no se sabe qué forma darle: la más general y el hueco.
        _standalone(builder, source, terms, markType: true);
    }
    return builder.build();
  }

  /// El autor de la entrada, con el punto que lo cierra: «García Márquez,
  /// Gabriel.», dos con «y» —«García, Ana, y Luis Paz»—, tres o más con «et
  /// al.», y el rol si la obra se cita por sus editores o su director.
  void _writeAuthors(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final lead = leadPeopleOf(source);
    if (lead.isEmpty) {
      builder
        ..gap(CitationGap.author)
        ..period();
      return;
    }

    final names = lead.names;
    final String text;
    if (names.length == 1) {
      text = invertedName(names.single);
    } else if (names.length == 2) {
      final second = names.last.displayName;
      final and = conjunctionBefore(terms.and, second);
      text = '${invertedName(names.first)}, $and $second';
    } else {
      text = '${invertedName(names.first)}, ${terms.etAl}';
    }
    builder.plain(text);

    final many = names.length > 1;
    switch (lead.role) {
      case ContributorRole.editor:
        builder.plain(', ${many ? terms.editorsRole : terms.editorRole}');
      case ContributorRole.director:
        builder.plain(', ${many ? terms.directorsRole : terms.directorRole}');
      case ContributorRole.author || ContributorRole.translator:
        break;
    }
    builder.period();
  }

  // Un libro: *Título*. Traducción de X, 2.ª ed., vol. 2, Editorial, 1967.
  void _book(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    _writeTitle(builder, source, quoted: false);
    _writeElements(builder, [
      ..._collaborators(source, terms),
      ?_editionPart(reference, terms),
      ?_volumePart(reference, terms),
      ?_publisherPart(source, terms, required: true),
      _datePart(source, terms, full: false),
      ?_linkPart(source, terms),
    ], sentenceStart: true);
    _writeAccess(builder, source, terms);
  }

  // Un capítulo: «Título». *Libro*, edición de X, Editorial, 1969, pp. 1-2.
  void _chapter(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    final container = reference.containerTitle;
    _writeTitle(builder, source, quoted: true);
    _writeElements(builder, [
      _containerPart(terms, container),
      ..._collaborators(source, terms),
      ?_editionPart(reference, terms),
      ?_volumePart(reference, terms),
      ?_publisherPart(source, terms, required: true),
      _datePart(source, terms, full: false),
      ?_pagesPart(reference.pages, terms),
      ?_linkPart(source, terms),
    ]);
    _writeAccess(builder, source, terms);
  }

  // Un artículo: «Título». *Revista*, vol. 8, núm. 3, 2019, pp. 207-217.
  void _article(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    final journal = reference.containerTitle;
    _writeTitle(builder, source, quoted: true);
    _writeElements(builder, [
      _containerPart(terms, journal),
      ?_volumePart(reference, terms),
      ?_issuePart(reference, terms),
      // Una revista con volumen se cita por el año; una sin volumen —una
      // revista de kiosco, un diario— por su fecha.
      _datePart(source, terms, full: reference.volume == null),
      ?_pagesPart(reference.pages, terms),
      ?_linkPart(source, terms),
    ]);
    _writeAccess(builder, source, terms);
  }

  // Una tesis: «Título». 2014. Universidad, tesis.
  void _thesis(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    _writeTitle(builder, source, quoted: true);
    builder
      ..space()
      ..append(_datePart(source, terms, full: false).citation)
      ..period();
    _writeElements(builder, [
      ?_publisherPart(source, terms, required: true),
      _textPart(terms.thesis.toLowerCase()),
      ?_linkPart(source, terms),
    ]);
    _writeAccess(builder, source, terms);
  }

  // Una fuente primaria o cualquier otra obra: *Título*. Editorial, 1493.
  void _standalone(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool markType,
  }) {
    final reference = source.reference;
    _writeTitle(builder, source, quoted: false, markType: markType);
    _writeElements(builder, [
      ..._collaborators(source, terms),
      ?_editionPart(reference, terms),
      ?_volumePart(reference, terms),
      ?_publisherPart(source, terms, required: false),
      _datePart(source, terms, full: true),
      ?_linkPart(source, terms),
    ], sentenceStart: true);
    _writeAccess(builder, source, terms);
  }

  // Un documental: *Título*. Productora, 2015.
  // Un video de una plataforma: «Título». *YouTube*, 5 mar. 2020, enlace.
  void _audiovisual(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    final container =
        reference.containerTitle ??
        (source.kind == SourceKind.youtube ? 'YouTube' : null);
    if (container == null) {
      _writeTitle(builder, source, quoted: false);
      _writeElements(builder, [
        ?_publisherPart(source, terms, required: false),
        _datePart(source, terms, full: true),
        ?_linkPart(source, terms),
      ], sentenceStart: true);
    } else {
      final publisher = reference.publisher;
      _writeTitle(builder, source, quoted: true);
      _writeElements(builder, [
        _italicPart(container),
        if (publisher != null && !_same(publisher, container))
          _textPart(publisher),
        _datePart(source, terms, full: true),
        ?_linkPart(source, terms),
      ]);
    }
    _writeAccess(builder, source, terms);
  }

  // Una página de un sitio: «Título». *Sitio*, Editorial, 24 may. 2018, enlace.
  // Un sitio entero: *Título*. Editorial, 24 may. 2018, enlace.
  void _webPage(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool quoteWithoutSite,
  }) {
    final reference = source.reference;
    final site = reference.containerTitle;
    final publisher = reference.publisher;
    if (site == null && !quoteWithoutSite) {
      _writeTitle(builder, source, quoted: false);
      _writeElements(builder, [
        ?_publisherPart(source, terms, required: false),
        _datePart(source, terms, full: true),
        ?_linkPart(source, terms),
      ], sentenceStart: true);
    } else {
      _writeTitle(builder, source, quoted: true);
      _writeElements(builder, [
        if (site != null) _italicPart(site),
        // Si la editorial es el mismo sitio, MLA no la repite.
        if (publisher != null && (site == null || !_same(publisher, site)))
          _textPart(publisher),
        _datePart(source, terms, full: true),
        ?_linkPart(source, terms),
      ]);
    }
    _writeAccess(builder, source, terms);
  }

  /// El título de la obra con su punto —o el hueco—: entre comillas si es una
  /// parte de algo más grande, en cursiva si se sostiene sola. [markType] pone
  /// el hueco del tipo de obra, para la que no lo tiene.
  void _writeTitle(
    CitationBuilder builder,
    CitationSource source, {
    required bool quoted,
    bool markType = false,
  }) {
    builder.title(
      source.title,
      inQuotes: quoted,
      punctuation: '.',
      markType: markType,
    );
  }

  /// Los elementos del contenedor, separados por comas y cerrados con un
  /// punto. Si van justo después del título [sentenceStart], el primero
  /// empieza una oración: una palabra del estilo —«vol.», «edición de»— va con
  /// mayúscula; lo que escribió el usuario se deja como está.
  void _writeElements(
    CitationBuilder builder,
    List<_Part> parts, {
    bool sentenceStart = false,
  }) {
    if (parts.isEmpty) return;
    builder.space();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) builder.plain(', ');
      final part = parts[i];
      builder.append(
        i == 0 && sentenceStart && part.isLabel
            ? _capitalizedCitation(part.citation)
            : part.citation,
      );
    }
    builder.period();
  }

  /// «Accessed 5 Sept. 2026.», si corresponde: una oración aparte, después del
  /// enlace.
  void _writeAccess(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final date = accessDateOf(source);
    if (date == null) return;
    final text = terms.mlaDate(date.year, month: date.month, day: date.day);
    builder
      ..space()
      ..plain('${terms.accessed} $text')
      ..period();
  }

  // -------------------------------------------------------------------------
  // Los elementos
  // -------------------------------------------------------------------------

  /// Quien colaboró en la obra sin ser su autor: «traducción de X», «edición
  /// de Y». Los editores que ya figuran de autores no se repiten.
  List<_Part> _collaborators(CitationSource source, CitationTerms terms) {
    final reference = source.reference;
    final leadRole = leadPeopleOf(source).role;
    final translators = reference.byRole(ContributorRole.translator);
    final editors = reference.byRole(ContributorRole.editor);
    return [
      if (translators.isNotEmpty)
        _labelPart('${terms.translatedBy} ${_plainNames(translators, terms)}'),
      if (editors.isNotEmpty && leadRole != ContributorRole.editor)
        _labelPart('${terms.editedBy} ${_plainNames(editors, terms)}'),
    ];
  }

  /// Los nombres en su orden natural: «Ana García», «Ana García y Luis Paz»,
  /// «Ana García et al.».
  String _plainNames(List<Contributor> people, CitationTerms terms) {
    final names = [for (final person in people) person.name.displayName];
    if (names.length == 1) return names.single;
    if (names.length == 2) {
      final and = conjunctionBefore(terms.and, names.last);
      return '${names.first} $and ${names.last}';
    }
    return '${names.first} ${terms.etAl}';
  }

  _Part? _editionPart(ReferenceData reference, CitationTerms terms) {
    final edition = editionText(reference.edition, terms);
    return edition == null ? null : _labelPart(edition);
  }

  _Part? _volumePart(ReferenceData reference, CitationTerms terms) {
    final volume = reference.volume;
    return volume == null ? null : _labelPart('${terms.volumeAbbr} $volume');
  }

  _Part? _issuePart(ReferenceData reference, CitationTerms terms) {
    final issue = reference.issue;
    return issue == null ? null : _labelPart('${terms.numberAbbr} $issue');
  }

  /// «pp. 45-67» o «p. 12»: con guion, como MLA.
  _Part? _pagesPart(String? pages, CitationTerms terms) {
    if (pages == null) return null;
    final label = isPageSpan(pages) ? terms.pages : terms.page;
    return _labelPart('$label ${_range(pages)}');
  }

  String _range(String pages) => pageRange(pages).replaceAll('–', '-');

  /// El libro, la revista o el sitio que contiene la obra, en cursiva; o el
  /// hueco si no está.
  _Part _containerPart(CitationTerms terms, String? title) => title == null
      ? _gapPart(terms, CitationGap.container)
      : _italicPart(title);

  /// La editorial; o el hueco si el estilo la pide y no está.
  _Part? _publisherPart(
    CitationSource source,
    CitationTerms terms, {
    required bool required,
  }) {
    final publisher = source.reference.publisher;
    if (publisher != null) return _textPart(publisher);
    return required ? _gapPart(terms, CitationGap.publisher) : null;
  }

  /// La fecha: solo el año o, si [full], hasta donde se sabe —«5 mar. 2020»—;
  /// «s. f.» si la obra no la tiene y el hueco si nadie la cargó.
  _Part _datePart(
    CitationSource source,
    CitationTerms terms, {
    required bool full,
  }) {
    final date = source.date;
    final year = date.year;
    if (date.isUndated) return _textPart(terms.noDate);
    if (date.isUnknown || year == null) {
      return _gapPart(terms, CitationGap.year);
    }
    return _textPart(
      full ? terms.mlaDate(year, month: date.month, day: date.day) : '$year',
    );
  }

  /// El DOI —como enlace— o, si no hay, la dirección sin «https://». Una obra
  /// de la web sin ninguno de los dos marca el hueco.
  _Part? _linkPart(CitationSource source, CitationTerms terms) {
    final doi = source.reference.doi;
    if (doi != null) return _textPart('https://doi.org/$doi');
    final url = source.url;
    if (url != null && url.isNotEmpty) {
      return _textPart(
        url.replaceFirst(RegExp('^https?://', caseSensitive: false), ''),
      );
    }
    final type = source.type;
    final online =
        type == ReferenceType.website ||
        type == ReferenceType.onlinePublication;
    return online ? _gapPart(terms, CitationGap.link) : null;
  }

  bool _same(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  // -------------------------------------------------------------------------
  // La cita en el texto
  // -------------------------------------------------------------------------

  /// «(García Márquez 12)», «(García Márquez y Rabassa 12)», «(García Márquez
  /// et al. 12)»: el apellido y la página, sin coma ni año. Sin autor, el
  /// hueco.
  Citation _inText(CitationSource source, CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms)..plain('(');

    final lead = leadPeopleOf(source);
    if (lead.isEmpty) {
      builder.gap(CitationGap.author);
    } else {
      builder.plain(inTextSurnames(lead.names, terms, joiner: terms.and));
    }

    final locator = context.locator;
    if (locator != null) {
      builder.plain(' ${locator.isTime ? locator.text : _range(locator.text)}');
    }
    builder.plain(')');
    return builder.build();
  }
}

/// Un elemento de la entrada: su texto y si es una palabra del estilo —«vol.»,
/// «traducción de»— o algo que escribió el usuario —una editorial, una fecha—.
class _Part {
  const _Part(this.citation, {this.isLabel = false});

  final Citation citation;

  /// Si empieza con una palabra del estilo, que va con mayúscula cuando abre
  /// una oración.
  final bool isLabel;
}

_Part _textPart(String text) => _Part(Citation([PlainRun(text)]));

_Part _labelPart(String text) =>
    _Part(Citation([PlainRun(text)]), isLabel: true);

_Part _italicPart(String text) => _Part(Citation([ItalicRun(text)]));

_Part _gapPart(CitationTerms terms, CitationGap gap) =>
    _Part(Citation([terms.gap(gap)]));

/// [citation] con la primera letra en mayúscula, si empieza con texto.
Citation _capitalizedCitation(Citation citation) {
  final runs = citation.runs;
  if (runs.isEmpty || runs.first is! PlainRun) return citation;
  return Citation([PlainRun(capitalized(runs.first.text)), ...runs.skip(1)]);
}
