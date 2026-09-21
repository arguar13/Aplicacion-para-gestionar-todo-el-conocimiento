import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/citation_builder.dart';
import 'package:sinapsis/features/citations/domain/services/citation_names.dart';
import 'package:sinapsis/features/citations/domain/services/citation_terms.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';

/// Los dos sistemas del Manual de Estilo de Chicago.
enum ChicagoSystem {
  /// Notas al pie y bibliografía: la primera vez que se cita una obra va una
  /// nota completa, las siguientes una corta, y al final la entrada de la
  /// bibliografía.
  notesBibliography,

  /// Autor-fecha: la cita en el texto es «(Smith 2016, 315)» y al final va la
  /// lista de referencias, con el año justo después del autor.
  authorDate,
}

/// Chicago 17.ª edición (F15), en sus dos sistemas, para los ocho tipos de
/// obra.
///
/// - **Notas y bibliografía** (`ChicagoStyle.notes`): la entrada de la
///   bibliografía, la nota completa —la primera vez que se cita— y la nota
///   corta —las siguientes—. No tiene cita entre paréntesis: el texto lleva
///   el número de la nota.
/// - **Autor-fecha** (`ChicagoStyle.authorDate`): la entrada de la lista de
///   referencias, con el año detrás del autor, y la cita en el texto.
///
/// Los nombres son neutros —«Chicago 17 NB» y «Chicago 17 AD», como los
/// llama el propio manual— para que quien los muestre les ponga la
/// explicación en su idioma.
///
/// Lo que el manual pide y la fuente no tiene se escribe como un hueco; lo
/// opcional que falta —la ciudad, el volumen— no se marca. Decisiones, dichas
/// para poder objetarlas:
/// - Una obra sin autor marca el hueco de autor, como en los otros estilos.
/// - Las páginas van completas —«207–217»—, sin acortar el segundo número como
///   hace el manual.
/// - El título abreviado de una nota corta es lo que está antes de los dos
///   puntos, con cuatro palabras como mucho; en inglés sin «A», «An» ni
///   «The» al principio.
/// - Una tesis se escribe «Thesis» o «Tesis» a secas, sin el grado.
/// - Los títulos de una parte —artículo, capítulo, página— van entre comillas
///   y los de lo que se sostiene solo, en cursiva; el nombre de un sitio va sin
///   formato. Un documento de un archivo se trata como una parte.
/// - La fecha de consulta —«Accessed March 5, 2020»— se escribe si alguien la
///   cargó y, en una obra con dirección que no dice cuándo se publicó, con la
///   de captura.
/// - En español las comillas son angulares, con la puntuación afuera, y
///   antes de «y» va coma solo con dos autores, donde la separa el nombre
///   invertido —«García, Ana, y Luis Paz»—.
///
/// Lo que esta versión no hace: no escribe el título de un volumen ni una
/// serie, no dice «ibid.» —el manual lo desaconseja—, no repite la fecha de
/// consulta en una nota corta y una obra sin autor no empieza por el título.
class ChicagoStyle implements ReferenceStyle {
  /// Notas y bibliografía.
  const ChicagoStyle.notes() : system = ChicagoSystem.notesBibliography;

  /// Autor-fecha.
  const ChicagoStyle.authorDate() : system = ChicagoSystem.authorDate;

  /// Cuál de los dos sistemas es.
  final ChicagoSystem system;

  bool get _authorDate => system == ChicagoSystem.authorDate;

  @override
  String get id => _authorDate ? 'chicago17ad' : 'chicago17nb';

  @override
  String get name => _authorDate ? 'Chicago 17 AD' : 'Chicago 17 NB';

  @override
  Set<CitationForm> get forms => _authorDate
      ? const {CitationForm.reference, CitationForm.inText}
      : const {
          CitationForm.reference,
          CitationForm.note,
          CitationForm.shortNote,
        };

  @override
  bool get isNumbered => false;

  @override
  bool get isAuthorDate => _authorDate;

  @override
  String listTitle(CitationLanguage language) {
    final terms = CitationTerms.of(language);
    return _authorDate ? terms.referencesTitle : terms.bibliographyTitle;
  }

  @override
  Citation format(
    CitationForm form,
    CitationSource source,
    CitationContext context,
  ) {
    if (!forms.contains(form)) return const Citation.empty();
    return switch (form) {
      CitationForm.reference => _reference(source, context),
      CitationForm.inText => _inText(source, context),
      CitationForm.note => _note(source, context),
      CitationForm.shortNote => _shortNote(source, context),
    };
  }

  // -------------------------------------------------------------------------
  // La entrada de la bibliografía o de la lista de referencias
  // -------------------------------------------------------------------------

  Citation _reference(CitationSource source, CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms);

    _writeAuthors(builder, source, terms);
    if (_authorDate) {
      builder.space();
      _writeYear(builder, source, terms, suffix: context.yearSuffix ?? '');
      builder.period();
    }
    builder.space();

    switch (source.type) {
      case ReferenceType.book:
        _book(builder, source, terms, requirePublisher: true);
      case ReferenceType.chapter:
        _chapter(builder, source, terms);
      case ReferenceType.article:
        _article(builder, source, terms);
      case ReferenceType.thesis:
        _thesis(builder, source, terms);
      case ReferenceType.primarySource:
        _primarySource(builder, source, terms);
      case ReferenceType.documentary:
        if (isOnlineWork(source)) {
          _web(builder, source, terms);
        } else {
          _book(builder, source, terms, requirePublisher: false);
        }
      case ReferenceType.website || ReferenceType.onlinePublication:
        _web(builder, source, terms);
      case ReferenceType.other:
        _book(builder, source, terms, requirePublisher: false);
      case null:
        // Sin tipo no se sabe qué forma darle: la más general y el hueco.
        _book(builder, source, terms, requirePublisher: false, markType: true);
    }
    return builder.build();
  }

  /// El autor de la entrada, con el punto que lo cierra: «Smith, Zadie.», dos
  /// con «and»/«y», hasta diez; con más, los siete primeros y «et al.». Sin
  /// autor, el hueco. Si la obra se cita por sus editores o su director, el
  /// rol va después: «Franco, Jean, ed.».
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
    builder
      ..plain(
        names.length > 10
            // Con más de diez van los siete primeros, sin «and» antes de «et
            // al.».
            ? '${_invertedItems(names.take(7).toList()).join(', ')}, '
                  '${terms.etAl}'
            : _invertedList(names, terms),
      )
      ..plain(_roleAfter(lead, terms))
      ..period();
  }

  /// El primero invertido y los demás en su orden natural.
  List<String> _invertedItems(List<PersonName> names) => [
    invertedName(names.first),
    for (final name in names.skip(1)) name.displayName,
  ];

  /// «Smith, Zadie», «Gilbert, Sandra M., and Susan Gubar», «Kelly, John, Ana
  /// Ruiz, and Luis Paz»: el primero invertido y los demás en su orden.
  String _invertedList(List<PersonName> names, CitationTerms terms) {
    final items = _invertedItems(names);
    if (items.length == 1) return items.single;
    if (items.length == 2) {
      final and = conjunctionBefore(terms.and, items.last);
      return '${items.first}, $and ${items.last}';
    }
    return joinList(items, terms, joiner: terms.and);
  }

  /// «, ed.», «, eds.», «, dir.»: el rol de quien figura de autor sin serlo.
  String _roleAfter(LeadPeople lead, CitationTerms terms) {
    final many = lead.names.length > 1;
    return switch (lead.role) {
      ContributorRole.editor =>
        ', ${many ? terms.editorsAbbr : terms.editorAbbr}',
      ContributorRole.director =>
        ', ${many ? terms.directorsAbbr : terms.directorAbbr}',
      ContributorRole.author || ContributorRole.translator => '',
    };
  }

  /// El año: «2019», «2019a», «n.d.» o el hueco.
  void _writeYear(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    String suffix = '',
  }) {
    final date = source.date;
    final year = date.year;
    if (date.isUndated) {
      builder.plain(terms.noDate);
    } else if (date.isUnknown || year == null) {
      builder.gap(CitationGap.year);
    } else {
      builder.plain('$year$suffix');
    }
  }

  /// Una oración de la entrada: espacio, texto y punto.
  void _sentence(CitationBuilder builder, String text) {
    builder
      ..space()
      ..plain(text)
      ..period();
  }

  /// Los nombres en su orden natural, para lo que va dentro de la entrada:
  /// «Robert Fagles», «A and B», «A, B, and C»; con más de diez, los siete
  /// primeros y «et al.».
  String _naturalNames(List<Contributor> people, CitationTerms terms) {
    final names = [for (final person in people) person.name.displayName];
    if (names.length > 10) {
      return '${names.take(7).join(', ')}, ${terms.etAl}';
    }
    return joinList(names, terms, joiner: terms.and, commaForPair: false);
  }

  /// «Translated by X.» y «Edited by Y.»: quien colaboró en una obra que no es
  /// suya. Los editores que ya figuran de autores no se repiten.
  List<String> _collaboratorSentences(
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    final translators = reference.byRole(ContributorRole.translator);
    final editors = reference.byRole(ContributorRole.editor);
    final leadIsEditor = leadPeopleOf(source).role == ContributorRole.editor;
    final translatedBy = translators.isEmpty
        ? null
        : '${capitalized(terms.translatedBy)} '
              '${_naturalNames(translators, terms)}';
    return [
      ?translatedBy,
      if (editors.isNotEmpty && !leadIsEditor)
        '${capitalized(terms.editedBy)} ${_naturalNames(editors, terms)}',
    ];
  }

  // Un libro: *Título*. Translated by X. 2nd ed. Ciudad: Editorial, 2016.
  void _book(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool requirePublisher,
    bool markType = false,
  }) {
    final reference = source.reference;
    builder.title(
      source.title,
      inQuotes: false,
      punctuation: '.',
      markType: markType,
    );
    final volume = reference.volume;
    for (final sentence in [
      ..._collaboratorSentences(source, terms),
      ?editionText(reference.edition, terms),
      if (volume != null) '${capitalized(terms.volumeAbbr)} $volume',
    ]) {
      _sentence(builder, sentence);
    }
    _writePublication(
      builder,
      source,
      terms,
      requirePublisher: requirePublisher,
    );
    _writeLink(builder, source, terms);
  }

  // Un capítulo: «Título». In *Libro*, edited by X, 67–83. Ciudad: Editorial,
  // 2010.
  void _chapter(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    builder
      ..title(source.title, inQuotes: true, punctuation: '.')
      ..space()
      ..plain('${terms.inWord} ');
    final container = reference.containerTitle;
    if (container == null) {
      builder.gap(CitationGap.container);
    } else {
      builder.italic(container);
    }
    final editors = reference.byRole(ContributorRole.editor);
    final volume = reference.volume;
    final pages = reference.pages;
    final details = [
      if (editors.isNotEmpty)
        '${terms.editedBy} ${_naturalNames(editors, terms)}',
      ?editionText(reference.edition, terms),
      if (volume != null) '${terms.volumeAbbr} $volume',
      if (pages != null) pageRange(pages),
    ];
    if (details.isNotEmpty) builder.plain(', ${details.join(', ')}');
    builder.period();
    _writePublication(builder, source, terms, requirePublisher: true);
    _writeLink(builder, source, terms);
  }

  // Un artículo: «Título». *Revista* 104, no. 3 (2009): 439–58.
  // Autor-fecha: *Revista* 104 (3): 439–58.
  void _article(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    builder
      ..title(source.title, inQuotes: true, punctuation: '.')
      ..space();
    final journal = reference.containerTitle;
    if (journal == null) {
      builder.gap(CitationGap.container);
    } else {
      builder.italic(journal);
    }
    final volume = reference.volume;
    final issue = reference.issue;
    final numbered = volume != null || issue != null;
    if (volume != null) builder.plain(' $volume');
    if (issue != null) {
      builder.plain(_authorDate ? ' ($issue)' : ', ${terms.numberAbbr} $issue');
    }
    if (numbered && !_authorDate) {
      builder.plain(' (');
      _writeYear(builder, source, terms);
      builder.plain(')');
    } else if (!numbered && !_authorDate) {
      builder.plain(', ');
      _writeFullDate(builder, source, terms);
    } else if (!numbered) {
      // Un diario o una revista sin volumen repite la fecha entera.
      final date = source.date;
      final year = date.year;
      if (year != null) {
        final text = terms.longPartialDate(
          year,
          month: date.month,
          day: date.day,
        );
        builder.plain(', $text');
      }
    }
    final pages = reference.pages;
    if (pages != null) {
      builder.plain('${numbered ? ': ' : ', '}${pageRange(pages)}');
    }
    builder.period();
    _writeLink(builder, source, terms);
  }

  // Una tesis: «Título». Thesis, Universidad, 2014.
  void _thesis(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    builder
      ..title(source.title, inQuotes: true, punctuation: '.')
      ..space()
      ..plain('${terms.thesis}, ');
    final university = source.reference.publisher;
    if (university == null) {
      builder.gap(CitationGap.publisher);
    } else {
      builder.plain(university);
    }
    if (!_authorDate) {
      builder.plain(', ');
      _writeYear(builder, source, terms);
    }
    builder.period();
    _writeLink(builder, source, terms);
  }

  // Una fuente primaria: «Título». Archivo, 1493.
  void _primarySource(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    builder.title(source.title, inQuotes: true, punctuation: '.');
    _writePublication(builder, source, terms, requirePublisher: false);
    _writeLink(builder, source, terms);
  }

  // Una obra de la web: «Título». Sitio. Editorial. 24 de mayo de 2018.
  // Accessed …. Enlace.
  void _web(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    final site = reference.containerTitle;
    final publisher = reference.publisher;
    builder.title(source.title, inQuotes: true, punctuation: '.');

    final platform = source.kind == SourceKind.youtube
        ? terms.videoOn('YouTube')
        : null;
    final first = site ?? platform ?? publisher;
    if (first != null) _sentence(builder, first);
    if (site != null &&
        publisher != null &&
        site.trim().toLowerCase() != publisher.trim().toLowerCase()) {
      _sentence(builder, publisher);
    }
    // El año de una entrada de autor-fecha ya está detrás del autor: acá va la
    // fecha entera, si se sabe.
    final date = source.date;
    final year = date.year;
    if (year != null) {
      _sentence(
        builder,
        terms.longPartialDate(year, month: date.month, day: date.day),
      );
    } else if (!_authorDate) {
      builder.space();
      if (date.isUndated) {
        builder.plain(terms.noDate);
      } else {
        builder.gap(CitationGap.year);
      }
      builder.period();
    }
    _writeLink(builder, source, terms);
  }

  /// «Ciudad: Editorial, 2016.» —el año solo en notas y bibliografía— o el
  /// hueco de la editorial si el estilo la pide.
  void _writePublication(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool requirePublisher,
  }) {
    final publisher = source.reference.publisher;
    final place = source.reference.publisherPlace;
    final hasPublisher = publisher != null || requirePublisher;
    if (!hasPublisher && _authorDate) return;
    builder.space();
    if (hasPublisher) {
      if (publisher == null) {
        builder.gap(CitationGap.publisher);
      } else {
        builder.plain(place == null ? publisher : '$place: $publisher');
      }
      if (!_authorDate) builder.plain(', ');
    }
    if (!_authorDate) _writeYear(builder, source, terms);
    builder.period();
  }

  /// La fecha de consulta —si corresponde— y el enlace, cada uno con su punto:
  /// el DOI como enlace o, si no hay, la dirección. Una obra de la web sin
  /// ninguno de los dos marca el hueco.
  void _writeLink(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final access = accessDateOf(source);
    if (access != null) {
      _sentence(builder, '${terms.accessed} ${terms.longDate(terms, access)}');
    }
    final target = _target(source);
    if (target != null) {
      _sentence(builder, target);
    } else if (_needsLink(source)) {
      builder
        ..space()
        ..gap(CitationGap.link)
        ..period();
    }
  }

  /// El enlace de la obra: su DOI como dirección o, si no tiene, su URL.
  String? _target(CitationSource source) {
    final doi = source.reference.doi;
    if (doi != null) return 'https://doi.org/$doi';
    final url = source.url;
    return url != null && url.isNotEmpty ? url : null;
  }

  bool _needsLink(CitationSource source) {
    final type = source.type;
    return type == ReferenceType.website ||
        type == ReferenceType.onlinePublication;
  }

  /// La fecha entera de una nota —«March 5, 2020»—, hasta donde se sabe, «n.d.»
  /// si la obra no tiene o el hueco si nadie la cargó.
  void _writeFullDate(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final date = source.date;
    final year = date.year;
    if (date.isUndated) {
      builder.plain(terms.noDate);
    } else if (date.isUnknown || year == null) {
      builder.gap(CitationGap.year);
    } else {
      builder.plain(
        terms.longPartialDate(year, month: date.month, day: date.day),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Las notas al pie
  // -------------------------------------------------------------------------

  /// La nota completa, la primera vez que se cita una obra: «Zadie Smith,
  /// *Swing Time* (New York: Penguin Press, 2016), 315–16.»
  Citation _note(CitationSource source, CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms);
    final locator = _locatorText(context.locator);

    _writeNoteAuthors(builder, source, terms);
    switch (source.type) {
      case ReferenceType.book:
        _noteBook(builder, source, terms, locator, requirePublisher: true);
      case ReferenceType.chapter:
        _noteChapter(builder, source, terms, locator);
      case ReferenceType.article:
        _noteArticle(builder, source, terms, locator);
      case ReferenceType.thesis:
        _noteThesis(builder, source, terms, locator);
      case ReferenceType.primarySource:
        _notePrimarySource(builder, source, terms, locator);
      case ReferenceType.documentary:
        if (isOnlineWork(source)) {
          _noteWeb(builder, source, terms);
        } else {
          _noteBook(builder, source, terms, locator, requirePublisher: false);
        }
      case ReferenceType.website || ReferenceType.onlinePublication:
        _noteWeb(builder, source, terms);
      case ReferenceType.other:
        _noteBook(builder, source, terms, locator, requirePublisher: false);
      case null:
        _noteBook(
          builder,
          source,
          terms,
          locator,
          requirePublisher: false,
          markType: true,
        );
    }
    builder.period();
    return builder.build();
  }

  /// La nota corta, las veces siguientes: «Smith, *Swing Time*, 320.»
  Citation _shortNote(CitationSource source, CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms);
    final locator = _locatorText(context.locator);

    final lead = leadPeopleOf(source);
    if (lead.isEmpty) {
      builder.gap(CitationGap.author);
    } else {
      builder.plain(_surnames(lead.names, terms));
    }
    builder.plain(', ');

    final title = shortTitle(
      source.title,
      dropArticle: context.language == CitationLanguage.en,
    );
    builder.title(
      title,
      inQuotes: _isQuotedTitle(source),
      punctuation: locator == null ? '.' : ',',
    );
    if (locator != null) {
      builder
        ..space()
        ..plain(locator);
    }
    builder.period();
    return builder.build();
  }

  /// Si el título de la obra va entre comillas: una parte de algo más grande
  /// o un documento suelto.
  bool _isQuotedTitle(CitationSource source) => switch (source.type) {
    ReferenceType.chapter ||
    ReferenceType.article ||
    ReferenceType.thesis ||
    ReferenceType.primarySource ||
    ReferenceType.website ||
    ReferenceType.onlinePublication => true,
    ReferenceType.documentary => isOnlineWork(source),
    ReferenceType.book || ReferenceType.other || null => false,
  };

  /// El autor de una nota: «Zadie Smith, », con el nombre en su orden natural,
  /// hasta tres; con más, el primero y «et al.».
  void _writeNoteAuthors(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final lead = leadPeopleOf(source);
    if (lead.isEmpty) {
      builder.gap(CitationGap.author);
    } else {
      builder
        ..plain(_noteNames([for (final n in lead.names) n.displayName], terms))
        ..plain(_roleAfter(lead, terms));
    }
    builder.plain(', ');
  }

  String _noteNames(List<String> names, CitationTerms terms) => names.length > 3
      ? '${names.first} ${terms.etAl}'
      : joinList(names, terms, joiner: terms.and, commaForPair: false);

  /// Los apellidos de una nota corta o de una cita en el texto: hasta tres; con
  /// más, el primero y «et al.». Una institución va entera.
  String _surnames(List<PersonName> names, CitationTerms terms) =>
      names.length > 3
      ? '${names.first.family} ${terms.etAl}'
      : joinList(
          [for (final name in names) name.family],
          terms,
          joiner: terms.and,
          commaForPair: false,
        );

  /// La página o el minuto que se cita, o `null` si se cita la obra entera.
  String? _locatorText(CitationLocator? locator) {
    if (locator == null) return null;
    return locator.isTime ? locator.text : pageRange(locator.text);
  }

  /// Quien colaboró, dicho como en una nota: «, trans. X», «, ed. Y».
  void _writeNoteCollaborators(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    final translators = reference.byRole(ContributorRole.translator);
    final editors = reference.byRole(ContributorRole.editor);
    final leadIsEditor = leadPeopleOf(source).role == ContributorRole.editor;
    if (translators.isNotEmpty) {
      final names = _noteNames([
        for (final t in translators) t.name.displayName,
      ], terms);
      builder.plain(', ${terms.translator.toLowerCase()} $names');
    }
    if (editors.isNotEmpty && !leadIsEditor) {
      final names = _noteNames([
        for (final e in editors) e.name.displayName,
      ], terms);
      builder.plain(', ${terms.editorAbbr} $names');
    }
  }

  /// « (Ciudad: Editorial, 2016)»: la publicación entre paréntesis.
  void _writeNotePublication(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool requirePublisher,
  }) {
    final publisher = source.reference.publisher;
    final place = source.reference.publisherPlace;
    builder.plain(' (');
    if (publisher != null) {
      builder.plain('${place == null ? '' : '$place: '}$publisher, ');
    } else if (requirePublisher) {
      builder
        ..gap(CitationGap.publisher)
        ..plain(', ');
    }
    _writeFullDate(builder, source, terms);
    builder.plain(')');
  }

  /// «, accessed March 5, 2020, https://…»: la fecha de consulta y el enlace de
  /// una nota.
  void _writeNoteLink(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final access = accessDateOf(source);
    if (access != null) {
      builder.plain(
        ', ${terms.accessed.toLowerCase()} ${terms.longDate(terms, access)}',
      );
    }
    final target = _target(source);
    if (target != null) {
      builder.plain(', $target');
    } else if (_needsLink(source)) {
      builder
        ..plain(', ')
        ..gap(CitationGap.link);
    }
  }

  void _writeLocator(CitationBuilder builder, String? locator) {
    if (locator != null) builder.plain(', $locator');
  }

  // Un libro: *Título*, trans. X, 2nd ed. (Ciudad: Editorial, 2016), 315–16.
  void _noteBook(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
    String? locator, {
    required bool requirePublisher,
    bool markType = false,
  }) {
    final reference = source.reference;
    builder.title(source.title, inQuotes: false, markType: markType);
    _writeNoteCollaborators(builder, source, terms);
    final edition = editionText(reference.edition, terms);
    if (edition != null) builder.plain(', $edition');
    final volume = reference.volume;
    if (volume != null) builder.plain(', ${terms.volumeAbbr} $volume');
    _writeNotePublication(
      builder,
      source,
      terms,
      requirePublisher: requirePublisher,
    );
    _writeLocator(builder, locator);
    _writeNoteLink(builder, source, terms);
  }

  // Un capítulo: «Título», in *Libro*, ed. X (Ciudad: Editorial, 2010), 77.
  void _noteChapter(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
    String? locator,
  ) {
    final reference = source.reference;
    builder
      ..title(source.title, inQuotes: true, punctuation: ',')
      ..space()
      ..plain('${terms.inWord.toLowerCase()} ');
    final container = reference.containerTitle;
    if (container == null) {
      builder.gap(CitationGap.container);
    } else {
      builder.italic(container);
    }
    final editors = reference.byRole(ContributorRole.editor);
    if (editors.isNotEmpty) {
      final names = _noteNames([
        for (final e in editors) e.name.displayName,
      ], terms);
      builder.plain(', ${terms.editorAbbr} $names');
    }
    final edition = editionText(reference.edition, terms);
    if (edition != null) builder.plain(', $edition');
    final volume = reference.volume;
    if (volume != null) builder.plain(', ${terms.volumeAbbr} $volume');
    _writeNotePublication(builder, source, terms, requirePublisher: true);
    final pages = reference.pages;
    _writeLocator(
      builder,
      locator ?? (pages == null ? null : pageRange(pages)),
    );
    _writeNoteLink(builder, source, terms);
  }

  // Un artículo: «Título», *Revista* 104, no. 3 (2009): 440.
  void _noteArticle(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
    String? locator,
  ) {
    final reference = source.reference;
    builder
      ..title(source.title, inQuotes: true, punctuation: ',')
      ..space();
    final journal = reference.containerTitle;
    if (journal == null) {
      builder.gap(CitationGap.container);
    } else {
      builder.italic(journal);
    }
    final volume = reference.volume;
    final issue = reference.issue;
    final numbered = volume != null || issue != null;
    if (volume != null) builder.plain(' $volume');
    if (issue != null) {
      builder.plain(', ${terms.numberAbbr} $issue');
    }
    if (numbered) {
      builder.plain(' (');
      _writeYear(builder, source, terms);
      builder.plain(')');
    } else {
      builder.plain(', ');
      _writeFullDate(builder, source, terms);
    }
    final pages = reference.pages;
    final where = locator ?? (pages == null ? null : pageRange(pages));
    if (where != null) builder.plain('${numbered ? ': ' : ', '}$where');
    _writeNoteLink(builder, source, terms);
  }

  // Una tesis: «Título» (thesis, Universidad, 2014), 45.
  void _noteThesis(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
    String? locator,
  ) {
    builder
      ..title(source.title, inQuotes: true)
      ..plain(' (${terms.thesis.toLowerCase()}, ');
    final university = source.reference.publisher;
    if (university == null) {
      builder.gap(CitationGap.publisher);
    } else {
      builder.plain(university);
    }
    builder.plain(', ');
    _writeYear(builder, source, terms);
    builder.plain(')');
    _writeLocator(builder, locator);
    _writeNoteLink(builder, source, terms);
  }

  // Una fuente primaria: «Título», Archivo, 1493, 2.
  void _notePrimarySource(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
    String? locator,
  ) {
    builder
      ..title(source.title, inQuotes: true, punctuation: ',')
      ..space();
    final archive = source.reference.publisher;
    if (archive != null) builder.plain('$archive, ');
    _writeYear(builder, source, terms);
    _writeLocator(builder, locator);
    _writeNoteLink(builder, source, terms);
  }

  // Una obra de la web: «Título», Sitio, Editorial, 24 de mayo de 2018,
  // enlace.
  void _noteWeb(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    final site = reference.containerTitle;
    final publisher = reference.publisher;
    builder.title(source.title, inQuotes: true, punctuation: ',');

    var first = true;
    void put(String text) {
      builder.plain(first ? ' $text' : ', $text');
      first = false;
    }

    final platform = source.kind == SourceKind.youtube
        ? terms.videoOn('YouTube')
        : null;
    final head = site ?? platform ?? publisher;
    if (head != null) put(head);
    if (site != null &&
        publisher != null &&
        site.trim().toLowerCase() != publisher.trim().toLowerCase()) {
      put(publisher);
    }
    final date = source.date;
    final year = date.year;
    if (year != null) {
      put(terms.longPartialDate(year, month: date.month, day: date.day));
    } else if (date.isUndated) {
      put(terms.noDate);
    } else {
      builder
        ..plain(first ? ' ' : ', ')
        ..gap(CitationGap.year);
      first = false;
    }
    final access = accessDateOf(source);
    if (access != null) {
      put('${terms.accessed.toLowerCase()} ${terms.longDate(terms, access)}');
    }
    final target = _target(source);
    if (target != null) {
      put(target);
    } else if (_needsLink(source)) {
      builder
        ..plain(first ? ' ' : ', ')
        ..gap(CitationGap.link);
    }
  }

  // -------------------------------------------------------------------------
  // La cita en el texto (autor-fecha)
  // -------------------------------------------------------------------------

  /// «(Smith 2016)», «(Smith 2016, 315)», «(Gilbert and Gubar 2000)»,
  /// «(Kelly et al. 2010)»: el apellido, el año y, si se cita un pasaje,
  /// dónde. Sin autor, el hueco; sin fecha, «n.d.».
  Citation _inText(CitationSource source, CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms)..plain('(');

    final lead = leadPeopleOf(source);
    if (lead.isEmpty) {
      builder.gap(CitationGap.author);
    } else {
      builder.plain(_surnames(lead.names, terms));
    }
    builder.plain(' ');
    _writeYear(builder, source, terms, suffix: context.yearSuffix ?? '');

    final locator = _locatorText(context.locator);
    if (locator != null) builder.plain(', $locator');
    builder.plain(')');
    return builder.build();
  }
}
