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

/// APA 7.ª edición (F15): la entrada de la lista de referencias y la cita en el
/// texto, para los ocho tipos de obra.
///
/// Sigue el Manual de Publicaciones de la APA. Lo que el manual pide y la
/// fuente no tiene se escribe como un hueco —«[falta: año]»—, no se inventa ni
/// se omite. Lo que el manual deja opcional y falta —el volumen de un libro, la
/// editorial de un sitio— no se marca.
///
/// Lo que esta versión no hace, dicho: no pasa los títulos a «sentence case»
/// —cambiaría un nombre propio a minúscula—, no escribe el año de la
/// publicación original de una traducción —no se guarda—, nombra a quien
/// tradujo solo en un libro y no en un capítulo, y una tesis se describe como
/// «Tesis» a secas, sin decir si es doctoral o de maestría.
class Apa7Style implements ReferenceStyle {
  const Apa7Style();

  @override
  String get id => 'apa7';

  @override
  String get name => 'APA 7';

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
  // La entrada de la lista de referencias
  // -------------------------------------------------------------------------

  Citation _reference(CitationSource source, CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms);
    final type = source.type;

    _writeAuthors(builder, source, terms);
    builder.space();
    _writeDate(builder, source, terms, fullDate: _usesFullDate(type));
    builder.space();

    switch (type) {
      case ReferenceType.book:
        _book(builder, source, terms);
      case ReferenceType.chapter:
        _chapter(builder, source, terms);
      case ReferenceType.article:
        _article(builder, source, terms);
      case ReferenceType.thesis:
        _thesis(builder, source, terms);
      case ReferenceType.primarySource:
        _primarySource(builder, source, terms);
      case ReferenceType.documentary:
        _audiovisual(builder, source, terms);
      case ReferenceType.website:
        _webPage(builder, source, terms, italicTitle: true);
      case ReferenceType.onlinePublication:
        _webPage(builder, source, terms, italicTitle: false);
      case ReferenceType.other:
        _generic(builder, source, terms, markType: false);
      case null:
        // Sin tipo no se sabe qué forma darle: se escribe con la más general y
        // se marca el hueco.
        _generic(builder, source, terms, markType: true);
    }

    _writeLink(builder, source, terms, type);
    return builder.build();
  }

  /// El autor de la entrada, con el punto que lo cierra: «García Márquez, G.»,
  /// dos o más unidos con «y» o «&», editores con «(Ed.)», o el hueco.
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

    final names = [for (final name in lead.names) surnameInitials(name)];
    if (names.length > 20) {
      // APA 7: los primeros diecinueve, tres puntos y el último.
      builder.plain('${names.take(19).join(', ')}, . . . ${names.last}');
    } else {
      builder.plain(_joinNames(names, terms));
    }
    final many = names.length > 1;
    switch (lead.role) {
      case ContributorRole.editor:
        builder.plain(' (${many ? terms.editors : terms.editor})');
      case ContributorRole.director:
        builder.plain(' (${many ? terms.directors : terms.director})');
      case ContributorRole.author || ContributorRole.translator:
        break;
    }
    builder.period();
  }

  /// Los nombres unidos como los pide la lista de referencias de APA: con «&»
  /// —y coma antes— en inglés, con «y» en español.
  String _joinNames(List<String> names, CitationTerms terms) =>
      joinList(names, terms, joiner: terms.ampersand);

  /// Los nombres con las iniciales antes del apellido —los de los editores y
  /// los traductores, que van dentro de la entrada—: «A. Editor & B. Editor»
  /// sin coma con dos, «A. Editor, B. Editor, & C. Editor» con tres.
  String _joinInitialsFirst(List<Contributor> people, CitationTerms terms) =>
      joinList(
        [for (final person in people) initialsSurname(person.name)],
        terms,
        joiner: terms.ampersand,
        commaForPair: false,
      );

  /// «R. Pevear & L. Volokhonsky, Trans.» / «R. Pevear y L. Volokhonsky,
  /// Trads.».
  String _translatorsText(List<Contributor> people, CitationTerms terms) {
    final label = people.length > 1 ? terms.translators : terms.translator;
    return '${_joinInitialsFirst(people, terms)}, $label';
  }

  /// «(2019).», «(2019, 15 de marzo).», «(s. f.).» o el hueco del año.
  void _writeDate(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool fullDate,
  }) {
    final date = source.date;
    builder.plain('(');
    final year = date.year;
    if (date.isUndated) {
      builder.plain(terms.noDate);
    } else if (date.isUnknown || year == null) {
      builder.gap(CitationGap.year);
    } else if (fullDate) {
      builder.plain(terms.apaDate(year, month: date.month, day: date.day));
    } else {
      builder.plain('$year');
    }
    builder.plain(').');
  }

  /// Las obras que se citan con el día y el mes, no solo el año: lo que sale en
  /// la web o en video, donde el día importa.
  bool _usesFullDate(ReferenceType? type) =>
      type == ReferenceType.website ||
      type == ReferenceType.onlinePublication ||
      type == ReferenceType.documentary;

  // Un libro: *Título* (2.ª ed., R. Pevear, Trad.). Editorial.
  void _book(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    _writeTitle(builder, source, terms, italic: true);
    final translators = reference.byRole(ContributorRole.translator);
    final details = [
      ?editionText(reference.edition, terms),
      if (translators.isNotEmpty) _translatorsText(translators, terms),
    ];
    if (details.isNotEmpty) builder.plain(' (${details.join(', ')})');
    builder.period();
    _writePublisher(builder, source, required: true);
  }

  // Un capítulo: Título. En E. Editor (Ed.), *Libro* (pp. 1–2). Editorial.
  void _chapter(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    _writeTitle(builder, source, terms, italic: false);
    builder
      ..period()
      ..space()
      ..plain('${terms.inWord} ');

    final editors = reference.byRole(ContributorRole.editor);
    if (editors.isNotEmpty) {
      builder.plain(
        '${_joinInitialsFirst(editors, terms)} '
        '(${editors.length > 1 ? terms.editors : terms.editor}), ',
      );
    }

    final container = reference.containerTitle;
    if (container == null) {
      builder.gap(CitationGap.container);
    } else {
      builder.italic(container);
    }

    final details = [
      ?editionText(reference.edition, terms),
      ?pagesWithTerm(reference.pages, terms),
    ];
    if (details.isNotEmpty) builder.plain(' (${details.join(', ')})');
    builder.period();
    _writePublisher(builder, source, required: true);
  }

  // Un artículo: Título. *Revista, 8*(3), 207–217.
  void _article(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final reference = source.reference;
    _writeTitle(builder, source, terms, italic: false);
    builder
      ..period()
      ..space();

    final journal = reference.containerTitle;
    final volume = reference.volume;
    // El nombre de la revista, la coma y el volumen van juntos en cursiva.
    if (journal != null && volume != null) {
      builder.italic('$journal, $volume');
    } else {
      if (journal == null) {
        builder.gap(CitationGap.container);
      } else {
        builder.italic(journal);
      }
      builder.plain(', ');
      if (volume == null) {
        builder.gap(CitationGap.volume);
      } else {
        builder.italic(volume);
      }
    }
    final issue = reference.issue;
    if (issue != null) builder.plain('($issue)');
    final pages = reference.pages;
    if (pages != null) builder.plain(', ${pageRange(pages)}');
    builder.period();
  }

  // Una tesis: *Título* [Tesis, Universidad].
  void _thesis(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    _writeTitle(builder, source, terms, italic: true);
    builder.plain(' [${terms.thesis}, ');
    final university = source.reference.publisher;
    if (university == null) {
      builder.gap(CitationGap.publisher);
    } else {
      builder.plain(university);
    }
    builder
      ..plain(']')
      ..period();
  }

  // Una fuente primaria: *Título*. Archivo.
  void _primarySource(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    _writeTitle(builder, source, terms, italic: true);
    builder.period();
    _writePublisher(builder, source, required: false);
  }

  // Un documental o un video: *Título* [Documental]. Productora.
  void _audiovisual(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
  ) {
    final isVideo =
        source.kind == SourceKind.youtube || source.kind == SourceKind.video;
    _writeTitle(builder, source, terms, italic: true);
    builder
      ..plain(' [${isVideo ? terms.video : terms.documentary}]')
      ..period();
    // Una plataforma conocida es el «sitio» de un video de YouTube aunque nadie
    // haya cargado editorial.
    final publisher = source.reference.publisher;
    if (publisher == null && source.kind == SourceKind.youtube) {
      builder
        ..space()
        ..plain('YouTube')
        ..period();
    } else {
      _writePublisher(builder, source, required: false);
    }
  }

  // Una página web o una publicación en red: *Título*. Sitio.
  void _webPage(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool italicTitle,
  }) {
    _writeTitle(builder, source, terms, italic: italicTitle);
    builder.period();
    final reference = source.reference;
    final site = reference.containerTitle ?? reference.publisher;
    // Si el sitio es el mismo autor —una institución que publica en su propia
    // página— APA no lo repite.
    final lead = leadPeopleOf(source);
    final sameAsAuthor =
        site != null &&
        lead.names.length == 1 &&
        lead.names.single.family.toLowerCase() == site.toLowerCase();
    if (site != null && !sameAsAuthor) {
      builder
        ..space()
        ..plain(site)
        ..period();
    }
  }

  // Cualquier otra obra: *Título*. Editorial.
  void _generic(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool markType,
  }) {
    _writeTitle(builder, source, terms, italic: true);
    if (markType) {
      builder
        ..plain(' ')
        ..gap(CitationGap.type);
    }
    builder.period();
    _writePublisher(builder, source, required: false);
  }

  /// El título de la obra —o el hueco—, en cursiva o no.
  void _writeTitle(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms, {
    required bool italic,
  }) {
    final title = source.title.trim();
    if (title.isEmpty) {
      builder.gap(CitationGap.title);
    } else if (italic) {
      builder.italic(title);
    } else {
      builder.plain(title);
    }
  }

  /// La editorial, con su punto; o el hueco si el estilo la pide y no está.
  void _writePublisher(
    CitationBuilder builder,
    CitationSource source, {
    required bool required,
  }) {
    final publisher = source.reference.publisher;
    if (publisher == null && !required) return;
    builder.space();
    if (publisher == null) {
      builder.gap(CitationGap.publisher);
    } else {
      builder.plain(publisher);
    }
    builder.period();
  }

  /// El DOI —como enlace— o, si no hay, la URL, al final y sin punto. Una obra
  /// en la web sin ninguno de los dos marca el hueco. Si alguien cargó cuándo
  /// se consultó una página web, se dice.
  void _writeLink(
    CitationBuilder builder,
    CitationSource source,
    CitationTerms terms,
    ReferenceType? type,
  ) {
    final doi = source.reference.doi;
    final url = source.url;
    final target = doi != null
        ? 'https://doi.org/$doi'
        : (url != null && url.isNotEmpty ? url : null);
    final online =
        type == ReferenceType.website ||
        type == ReferenceType.onlinePublication;

    if (target == null) {
      if (online) {
        builder
          ..space()
          ..gap(CitationGap.link);
      }
      return;
    }
    builder.space();
    final accessed = source.accessedAt;
    if (online && doi == null && accessed != null) {
      builder.plain(terms.retrieved(terms, accessed, target));
    } else {
      builder.plain(target);
    }
  }

  // -------------------------------------------------------------------------
  // La cita en el texto
  // -------------------------------------------------------------------------

  /// «(García Márquez, 1967)», «(García Márquez y Rabassa, 1967, p. 12)»,
  /// «(García Márquez et al., 1967)». Sin autor, el hueco; sin año, «s. f.» o
  /// el hueco.
  Citation _inText(CitationSource source, CitationContext context) {
    final terms = CitationTerms.of(context.language);
    final builder = CitationBuilder(terms)..plain('(');

    final lead = leadPeopleOf(source);
    if (lead.isEmpty) {
      builder.gap(CitationGap.author);
    } else {
      builder.plain(inTextSurnames(lead.names, terms, joiner: terms.ampersand));
    }
    builder.plain(', ');

    final date = source.date;
    if (date.isUndated) {
      builder.plain(terms.noDate);
    } else if (date.isUnknown || date.year == null) {
      builder.gap(CitationGap.year);
    } else {
      builder.plain('${date.year}');
    }

    final locator = context.locator;
    if (locator != null) {
      builder.plain(', ${locatorWithTerm(locator, terms)}');
    }
    builder.plain(')');
    return builder.build();
  }
}
