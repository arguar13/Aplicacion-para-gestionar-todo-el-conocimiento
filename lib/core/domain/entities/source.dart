import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'source.freezed.dart';

/// De dónde salió algo: el rastro que permite volver al original.
///
/// Es una entidad propia y no cuatro campos sueltos dentro del elemento, por
/// una razón concreta: un texto sin origen es una cita sin autor — sirve para
/// leer, no para trabajar. Teniéndola aparte, guardar algo sin decir de dónde
/// vino deja de ser un descuido posible y pasa a ser imposible.
@freezed
sealed class Source with _$Source {
  const factory Source({
    required String id,
    required SourceKind kind,

    /// Cuándo lo guardó el usuario. Distinto de [publishedAt]: un artículo de
    /// 2019 capturado hoy tiene las dos fechas, y ordenar por una o por otra
    /// responde preguntas distintas.
    required DateTime capturedAt,

    /// El enlace al original. Nulo solo en [SourceKind.manualNote] y en
    /// archivos locales, donde no hay ningún original en la web al que volver.
    String? url,

    String? authorName,

    /// El perfil de quien lo publicó, no el enlace a la publicación. Para un
    /// tweet son dos cosas distintas y las dos hacen falta: una lleva al
    /// contenido, la otra a quien lo escribió.
    String? authorUrl,

    /// Cuándo se publicó originalmente, si se pudo averiguar.
    DateTime? publishedAt,

    /// Ruta a una copia del original tal como estaba el día que se guardó: el
    /// PDF, el audio, la página con sus recursos incrustados.
    ///
    /// Es el seguro contra el enlace que mañana da 404 — que es exactamente
    /// el problema que esta app viene a resolver.
    String? originalFilePath,

    /// El idioma en que se habla o está escrito el original, como código de
    /// dos letras ("es", "en"): con qué idioma se transcribe un audio o un
    /// video, y en qué idioma están los subtítulos de YouTube que se
    /// guardaron. Nulo: no se sabe, y un audio se transcribe en español —el
    /// idioma de quien usa esta app— (F22).
    ///
    /// Se guarda para no traducir sin querer: Whisper con el idioma fijado
    /// en español transcribe un audio en inglés traduciéndolo, y dejándolo
    /// detectar solo confunde el español con el gallego y le quita las
    /// tildes (medido, F22).
    String? language,

    /// «Solo el libro» (F30, decisión 68): el texto se soltó a propósito y
    /// queda el archivo, que **no se vuelve a extraer solo**. Lo pone y lo
    /// saca quien suelta y recupera el texto —la papelera del contenido— o
    /// «Volver a extraer»; guardar el elemento no lo escribe, para que una
    /// foto vieja del elemento no lo pise.
    @Default(false) bool onlyFile,
  }) = _Source;
}
