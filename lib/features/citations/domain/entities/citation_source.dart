import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// En qué idioma se escribe una cita (F15): el de los términos —«y», «Ed.»,
/// «pp.», «s. f.», «En»— y el de las fechas, no el de la obra.
///
/// Una referencia en inglés en un trabajo en español se cita con los términos
/// del trabajo —«En J. Smith (Ed.)», no «In»—, así que es una elección de quien
/// cita y no un dato de la fuente.
enum CitationLanguage {
  es,
  en;

  /// El idioma de un código de la app —«es», «en»—; el español si no se
  /// conoce.
  static CitationLanguage fromCode(String? code) => switch (code) {
    'en' => CitationLanguage.en,
    _ => CitationLanguage.es,
  };
}

/// Qué forma de la cita se pide.
enum CitationForm {
  /// La entrada de la lista de referencias o de la bibliografía.
  reference,

  /// La cita dentro del texto, entre paréntesis o numerada.
  inText,

  /// La nota al pie completa: la primera vez que se cita una obra (Chicago).
  note,

  /// La nota al pie corta: las veces siguientes (Chicago).
  shortNote,
}

/// Dónde de una obra está lo que se cita: una página, un pasaje, un minuto.
@immutable
class CitationLocator {
  const CitationLocator.page(this.text) : isTime = false;

  /// Un instante de un audio o un video: «0:14:35».
  const CitationLocator.time(this.text) : isTime = true;

  final String text;

  /// Si es un instante y no una página.
  final bool isTime;

  @override
  bool operator ==(Object other) =>
      other is CitationLocator && other.text == text && other.isTime == isTime;

  @override
  int get hashCode => Object.hash(text, isTime);
}

/// Cómo se pide una cita: en qué idioma y, si es de un fragmento, dónde.
@immutable
class CitationContext {
  const CitationContext({
    this.language = CitationLanguage.es,
    this.locator,
    this.number,
  });

  final CitationLanguage language;

  /// Página o minuto del pasaje citado, o `null` para citar la obra entera.
  final CitationLocator? locator;

  /// El lugar de la fuente en una lista numerada, para el estilo que numera
  /// sus entradas (IEEE). `null` fuera de una lista: una fuente citada sola es
  /// la primera.
  final int? number;
}

/// Lo que un estilo necesita saber de una fuente para citarla (F15): su
/// título, sus datos bibliográficos, su fecha y de dónde salió.
///
/// Es un valor armado por quien cita, a partir de lo que guarda la app, y no
/// una lectura de la base: los estilos son funciones puras que no saben de
/// dónde sale nada.
@immutable
class CitationSource {
  const CitationSource({
    required this.title,
    this.reference = const ReferenceData(),
    this.date = const PublicationDate.unknown(),
    this.url,
    this.authorName,
    this.capturedAt,
    this.kind,
  });

  /// El título del elemento.
  final String title;

  /// Los datos bibliográficos: personas, editorial, volumen…
  final ReferenceData reference;

  /// Cuándo se publicó, con la exactitud con que se sabe.
  final PublicationDate date;

  /// El enlace al original.
  final String? url;

  /// Quien la escribió tal como se capturó —un canal, una cuenta—, sin partir
  /// en apellido y nombre. Se cita entero, sin invertirlo, cuando la fuente
  /// no tiene personas cargadas.
  final String? authorName;

  /// Cuándo se guardó. No es la fecha de publicación —decir que algo se
  /// publicó el día que se guardó sería una cita falsa—; sirve de fecha de
  /// consulta de una página web que no trae la suya.
  final DateTime? capturedAt;

  /// De qué clase de captura salió, para darle un tipo de obra a la que no lo
  /// tiene.
  final SourceKind? kind;

  /// La clase de obra: la que dice la referencia o, si no dice ninguna, la que
  /// se deduce de cómo se capturó —una página web es un sitio web, un video es
  /// un documental—. Un documento suelto no tiene tipo: `null`, y la cita lo
  /// marca como un hueco en lugar de suponerlo.
  ReferenceType? get type => reference.type ?? _typeOf(kind);

  /// La fecha en que se consultó, si alguien la cargó.
  DateTime? get accessedAt => reference.accessedAt;

  /// La fecha de consulta que un estilo que la pide puede escribir: la cargada
  /// o, en una fuente web, la de captura.
  DateTime? get accessedOrCaptured => accessedAt ?? capturedAt;

  /// Si la obra está en la web.
  bool get isOnline =>
      type == ReferenceType.website ||
      type == ReferenceType.onlinePublication ||
      (url != null && url!.isNotEmpty);

  static ReferenceType? _typeOf(SourceKind? kind) => switch (kind) {
    SourceKind.webPage => ReferenceType.website,
    SourceKind.youtube || SourceKind.video => ReferenceType.documentary,
    SourceKind.socialPost => ReferenceType.onlinePublication,
    _ => null,
  };
}
