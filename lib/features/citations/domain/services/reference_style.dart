import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';

/// Un estilo de cita (F15): APA 7, MLA 9, Chicago, IEEE. Dada una fuente, arma
/// su cita en una de las formas que el estilo tiene.
///
/// Es una función pura: no lee la base, no conoce la pantalla ni el idioma de
/// la app. Recibe todo lo que necesita en una [CitationSource] y un
/// [CitationContext], y devuelve una [Citation] —corridas de texto, cursiva y
/// huecos—, que quien la pidió muestra, copia o exporta como quiera.
///
/// Agregar un estilo es escribir una clase que implemente esta interfaz y una
/// línea en `kReferenceStyles`: nada más de la app lo nombra.
abstract interface class ReferenceStyle {
  /// El identificador estable con que se guarda la elección del usuario:
  /// `apa7`, `mla9`…
  String get id;

  /// Cómo se llama para quien la elige: «APA 7».
  String get name;

  /// Las formas que tiene el estilo: APA no tiene notas al pie; Chicago sí.
  Set<CitationForm> get forms;

  /// Si las entradas de la bibliografía van numeradas y se citan por su
  /// número —IEEE—. Quien arma una lista le pasa a cada entrada su
  /// `CitationContext.number`; el estilo lo escribe a su manera.
  bool get isNumbered;

  /// La cita de [source] en la forma [form]. Para una forma que el estilo no
  /// tiene devuelve la cita vacía: quien la pide mira antes [forms].
  Citation format(
    CitationForm form,
    CitationSource source,
    CitationContext context,
  );
}

/// Los estilos que ofrece la app, en el orden en que se ofrecen.
class ReferenceStyleRegistry {
  const ReferenceStyleRegistry(this.styles);

  final List<ReferenceStyle> styles;

  /// El que se usa mientras nadie elige: el primero.
  ReferenceStyle get defaultStyle => styles.first;

  /// El estilo llamado [id], o `null` si ninguno se llama así.
  ReferenceStyle? byId(String? id) {
    for (final style in styles) {
      if (style.id == id) return style;
    }
    return null;
  }

  /// El estilo llamado [id] o, si no hay ninguno, el predeterminado: una
  /// elección guardada de un estilo que la app ya no ofrece no rompe nada.
  ReferenceStyle resolve(String? id) => byId(id) ?? defaultStyle;
}
