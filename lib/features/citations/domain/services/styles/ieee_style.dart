import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/citation_builder.dart';
import 'package:sinapsis/features/citations/domain/services/citation_names.dart';
import 'package:sinapsis/features/citations/domain/services/citation_terms.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';

/// IEEE (F15): la entrada numerada de la lista de referencias y la cita en el
/// texto por su número —«[1]»—, para los ocho tipos de obra.
///
/// Sigue la guía de referencias de IEEE: los autores con las iniciales antes
/// del apellido, hasta seis y con «et al.» desde el séptimo; el título de un
/// artículo o un capítulo entre comillas y el de un libro o una revista en
/// cursiva; la editorial precedida de su ciudad. Una obra de la web va como en
/// la guía —autor, título entre comillas, sitio, fecha de consulta y
/// `[Online]. Available: enlace`—, sin fecha de publicación. Lo que la guía
/// pide y la fuente no tiene se escribe como un hueco; lo opcional que falta
/// —la ciudad, el volumen— no se marca.
///
/// La entrada lleva su número —«[3] …»— solo si quien la pide lo dice con
/// `CitationContext.number`: una entrada suelta no lleva ninguno. Sin número,
/// la cita en el texto es «[1]»: una fuente citada sola es la primera.
///
/// Lo que esta versión no hace, dicho: no abrevia los títulos de las revistas
/// ni las editoriales —«IEEE Trans. Electron Devices», «Univ.»—, no escribe el
/// número de un capítulo o una sección y una tesis se describe como «Tesis» a
/// secas, sin el grado ni el departamento.
class IeeeStyle implements ReferenceStyle {
  const IeeeStyle();

  @override
  String get id => 'ieee';

  @override
  String get name => 'IEEE';

  @override
  Set<CitationForm> get forms => const {
    CitationForm.reference,
    CitationForm.inText,
  };

  @override
  bool get isNumbered => true;

  @override
  bool get isAuthorDate => false;

  @override
  String listTitle(CitationLanguage language) =>
      CitationTerms.of(language).referencesTitle;

  @override
  Citation format(
    CitationForm form,
    CitationSource source,
    CitationContext context,
  ) => switch (form) {
    CitationForm.reference => _reference(source, context),
    CitationForm.inText => _inText(context),
    CitationForm.note || CitationForm.shortNote => const Citation.empty(),
  };

  // -------------------------------------------------------------------------
  // La entrada de la lista de referencias
  // -------------------------------------------------------------------------

  Citation _reference(CitationSource source, CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms);
    final number = context.number;
    if (number != null) builder.plain('[$number] ');

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
          _online(builder, source, terms);
        } else {
          _book(builder, source, terms, requirePublisher: false);
        }
      case ReferenceType.website || ReferenceType.onlinePublication:
        _online(builder, source, terms);
      case ReferenceType.other:
        _book(builder, source, terms, requirePublisher: false);
      case null:
        // Sin tipo no se sabe qué forma darle: la más general y el hueco.
        _book(builder, source, terms, requirePublisher: false, markType: true);
    }
    return builder.build();
  }

  /// Los autores de la entrada: «J. K. Rowling», «A. Ruiz and B. Paz», «A, B,
  /// and C», más de seis con «et al.». [period] cierra con punto —la web— y no
  /// con coma. Sin autores, el hueco.
  void _writeAuthors(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool period,
  }) {
    final lead = leadPeopleOf(source);
    if (lead.isEmpty) {
      builder.gap(CitationGap.author);
    } else {
      final names = [for (final name in lead.names) initialsSurname(name)];
      builder.plain(
        names.length > 6
            ? '${names.first} ${terms.etAl}'
            : joinList(names, terms, joiner: terms.and, commaForPair: false),
      );
      final many = names.length > 1;
      switch (lead.role) {
        case ContributorRole.editor:
          builder.plain(', ${many ? terms.editors : terms.editor}');
        case ContributorRole.director:
          builder.plain(', ${many ? terms.directors : terms.director}');
        case ContributorRole.author || ContributorRole.translator:
          break;
      }
    }
    if (period) {
      builder.period();
    } else {
      builder.comma();
    }
    builder.space();
  }

  // Un libro: A. Autor, *Título*, 2.ª ed., vol. 2. Ciudad: Editorial, 1967.
  void _book(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool requirePublisher,
    bool markType = false,
  }) {
    final reference = source.reference;
    _writeAuthors(builder, source, terms, period: false);
    final title = source.title.trim();
    if (title.isEmpty) {
      builder.gap(CitationGap.title);
    } else {
      builder.italic(title);
    }
    if (markType) {
      builder
        ..plain(' ')
        ..gap(CitationGap.type);
    }
    final edition = editionText(reference.edition, terms);
    if (edition != null) builder.plain(', $edition');
    final volume = reference.volume;
    if (volume != null) builder.plain(', ${terms.volumeAbbr} $volume');
    builder.period();
    _writePublication(
      builder,
      source,
      terms,
      requirePublisher: requirePublisher,
    );
    _writeLocation(builder, source, terms);
  }

  // Un capítulo: A. Autor, “Título,” en *Libro*, 2.ª ed., vol. 2, E. Editor,
  // Ed. Ciudad: Editorial, 1994, pp. 55–70.
  void _chapter(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    _writeAuthors(builder, source, terms, period: false);
    _writeQuotedTitle(builder, source, punctuation: ',');
    builder
      ..space()
      ..plain('${terms.inWord.toLowerCase()} ');
    final container = reference.containerTitle;
    if (container == null) {
      builder.gap(CitationGap.container);
    } else {
      builder.italic(container);
    }
    final edition = editionText(reference.edition, terms);
    if (edition != null) builder.plain(', $edition');
    final volume = reference.volume;
    if (volume != null) builder.plain(', ${terms.volumeAbbr} $volume');

    final editors = reference.byRole(ContributorRole.editor);
    if (editors.isNotEmpty) {
      final names = [for (final e in editors) initialsSurname(e.name)];
      final joined = joinList(
        names,
        terms,
        joiner: terms.and,
        commaForPair: false,
      );
      builder.plain(
        ', $joined, ${editors.length > 1 ? terms.editors : terms.editor}',
      );
    }
    builder.period();
    _writePublication(
      builder,
      source,
      terms,
      requirePublisher: true,
      pages: pagesWithTerm(reference.pages, terms),
    );
    _writeLocation(builder, source, terms);
  }

  // Un artículo: A. Autor, “Título,” *Revista*, vol. 8, núm. 3, pp. 207–217,
  // mar. 2019, doi: 10.1000/xyz.
  void _article(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    _writeAuthors(builder, source, terms, period: false);
    _writeQuotedTitle(builder, source, punctuation: ',');
    builder.space();
    final journal = reference.containerTitle;
    if (journal == null) {
      builder.gap(CitationGap.container);
    } else {
      builder.italic(journal);
    }
    final volume = reference.volume;
    if (volume != null) builder.plain(', ${terms.volumeAbbr} $volume');
    final issue = reference.issue;
    if (issue != null) builder.plain(', ${terms.numberAbbr} $issue');
    final pages = pagesWithTerm(reference.pages, terms);
    if (pages != null) builder.plain(', $pages');
    builder.plain(', ');
    _writeDate(builder, source, terms, withMonth: true);
    _writeLocation(builder, source, terms);
  }

  // Una tesis: A. Autor, “Título,” Tesis, Universidad, 2014.
  void _thesis(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    _writeAuthors(builder, source, terms, period: false);
    _writeQuotedTitle(builder, source, punctuation: ',');
    builder
      ..space()
      ..plain('${terms.thesis}, ');
    final university = source.reference.publisher;
    if (university == null) {
      builder.gap(CitationGap.publisher);
    } else {
      builder.plain(university);
    }
    builder.plain(', ');
    _writeDate(builder, source, terms);
    _writeLocation(builder, source, terms);
  }

  // Una fuente primaria: A. Autor, “Título,” Archivo, 1493.
  void _primarySource(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    _writeAuthors(builder, source, terms, period: false);
    _writeQuotedTitle(builder, source, punctuation: ',');
    builder.space();
    final archive = source.reference.publisher;
    if (archive != null) builder.plain('$archive, ');
    _writeDate(builder, source, terms);
    _writeLocation(builder, source, terms);
  }

  // Una obra de la web: A. Autor. “Título.” Sitio. Accessed: 1 feb. 2009.
  // [Online]. Available: enlace
  void _online(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    _writeAuthors(builder, source, terms, period: true);
    _writeQuotedTitle(builder, source, punctuation: '.');

    final site =
        reference.containerTitle ??
        reference.publisher ??
        (source.kind == SourceKind.youtube ? 'YouTube' : null);
    if (site != null) {
      builder
        ..space()
        ..plain(site)
        ..period();
    }

    builder.space();
    final accessed = source.accessedOrCaptured;
    if (accessed == null) {
      builder.gap(CitationGap.accessed);
    } else {
      builder.plain('${terms.ieeeAccessed} ${_dateOf(accessed, terms)}');
    }
    builder
      ..period()
      ..space()
      ..plain('${terms.ieeeOnline} ');
    final url = source.url;
    if (url == null || url.isEmpty) {
      builder.gap(CitationGap.link);
    } else {
      builder.plain(url);
    }
  }

  /// El título entre comillas con la [punctuation] que le sigue, o el hueco.
  void _writeQuotedTitle(
    CitationBuilder builder,
    CitationSource source, {
    required String punctuation,
  }) {
    final title = source.title.trim();
    if (title.isEmpty) {
      builder
        ..gap(CitationGap.title)
        ..plain(punctuation);
    } else {
      builder.quoted(title, punctuation: punctuation);
    }
  }

  /// «Ciudad: Editorial, 1967» —o el hueco de la editorial, si el estilo la
  /// pide— y, si hay, «, pp. 55–70». La ciudad no se pide: si no está, no se
  /// escribe.
  void _writePublication(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool requirePublisher,
    String? pages,
  }) {
    final publisher = source.reference.publisher;
    final place = source.reference.publisherPlace;
    builder.space();
    if (publisher != null) {
      builder.plain('${place == null ? '' : '$place: '}$publisher, ');
    } else if (requirePublisher) {
      builder
        ..gap(CitationGap.publisher)
        ..plain(', ');
    }
    _writeDate(builder, source, terms);
    if (pages != null) builder.plain(', $pages');
  }

  /// El año —o «mar. 2019» si [withMonth] y se sabe el mes—, «s. f.» si la obra
  /// no tiene fecha y el hueco si nadie la cargó.
  void _writeDate(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    bool withMonth = false,
  }) {
    final date = source.date;
    final year = date.year;
    if (date.isUndated) {
      builder.plain(terms.noDate);
    } else if (date.isUnknown || year == null) {
      builder.gap(CitationGap.year);
    } else if (withMonth && date.month != null) {
      builder.plain(terms.ieeeDate(year, month: date.month));
    } else {
      builder.plain('$year');
    }
  }

  String _dateOf(DateTime date, CitationTerms terms) =>
      terms.ieeeDate(date.year, month: date.month, day: date.day);

  /// Cierra la entrada: con el DOI —«, doi: 10.1000/xyz.»— o, si no hay, con
  /// punto y, si hay una dirección, `[Online]. Available: enlace` —con la
  /// fecha de consulta si alguien la cargó—.
  void _writeLocation(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final doi = source.reference.doi;
    if (doi != null) {
      builder
        ..plain(', doi: $doi')
        ..period();
      return;
    }
    builder.period();
    final url = source.url;
    if (url == null || url.isEmpty) return;
    final accessed = source.accessedAt;
    if (accessed != null) {
      builder
        ..space()
        ..plain('${terms.ieeeAccessed} ${_dateOf(accessed, terms)}')
        ..period();
    }
    builder
      ..space()
      ..plain('${terms.ieeeOnline} $url');
  }

  // -------------------------------------------------------------------------
  // La cita en el texto
  // -------------------------------------------------------------------------

  /// «[3]», «[3, p. 12]», «[3, pp. 12–14]» o «[3, 0:14:35]».
  Citation _inText(CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms)..plain('[${context.number ?? 1}');
    final locator = context.locator;
    if (locator != null) {
      builder.plain(', ${locatorWithTerm(locator, terms)}');
    }
    builder.plain(']');
    return builder.build();
  }
}
