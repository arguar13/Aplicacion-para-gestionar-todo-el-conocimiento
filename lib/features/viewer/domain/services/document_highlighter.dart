import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';

/// Por qué una selección sobre el documento real no se pudo resaltar (F38).
enum HighlightIssue {
  /// No hay nada seleccionado.
  nothingSelected,

  /// La página es una foto: no tiene letras donde resaltar. Lo que se lee de
  /// ella lo reconoció el OCR, y se resalta en «Texto extraído».
  scanned,

  /// La selección no se pudo llevar al texto extraído: el documento muestra
  /// el texto en otro orden o con otras letras que el texto guardado.
  notLocated,

  /// Se ubicó, pero no se pudo guardar: ver [HighlightOutcome.failure].
  notSaved,
}

/// Dónde cae una selección del documento real en el texto extraído (F38):
/// los tramos `[start, end)` —uno por página, en un PDF; uno solo en una
/// página web— o, si no se pudo ubicar, por qué.
///
/// Un PDF da un tramo por página y no uno solo de punta a punta porque el
/// texto extraído lleva entre páginas un separador (`---`) que no es del
/// documento: un resaltado que lo cruzara lo traería adentro.
class SelectionLocation {
  const SelectionLocation.found(this.slices) : issue = null;

  const SelectionLocation.failed(HighlightIssue this.issue) : slices = const [];

  final List<TextSlice> slices;

  /// `null` si se ubicó.
  final HighlightIssue? issue;

  bool get found => issue == null;
}

/// Lo que pasó al resaltar una selección del documento real (F38).
class HighlightOutcome {
  const HighlightOutcome.created(this.highlights)
    : issue = null,
      failure = null;

  const HighlightOutcome.issue(
    HighlightIssue this.issue, {
    this.failure,
    this.highlights = const [],
  });

  /// Los resaltados guardados: uno por tramo. Con un problema al guardar, los
  /// que alcanzaron a guardarse antes.
  final List<Highlight> highlights;

  /// `null` si se guardó.
  final HighlightIssue? issue;

  /// Por qué no se pudo guardar, con [HighlightIssue.notSaved].
  final Failure? failure;

  bool get created => issue == null;
}

/// Guarda un resaltado de la persona por cada uno de [slices] —tramos
/// ubicados del texto extraído [content] de la forma [renditionId]—, con el
/// [color] y el [style] elegidos: el punto de entrada para resaltar lo que se
/// seleccionó sobre el documento real (F38).
///
/// El texto que guarda cada resaltado es el del tramo, copiado: si la forma
/// se regenera y las posiciones dejan de valer, no se pierde lo marcado. La
/// [note], si hay, queda en el primero.
///
/// Si alguno no se puede guardar, se cortan los que siguen y se avisa; los ya
/// guardados quedan.
Future<HighlightOutcome> saveHighlights(
  OrganizeRepository repository, {
  required String renditionId,
  required String content,
  required List<TextSlice> slices,
  HighlightColor? color,
  HighlightStyle style = HighlightStyle.fill,
  String? note,
}) async {
  if (slices.isEmpty) {
    return const HighlightOutcome.issue(HighlightIssue.nothingSelected);
  }
  final saved = <Highlight>[];
  for (final slice in slices) {
    final result = await repository.createHighlight(
      renditionId: renditionId,
      startOffset: slice.start,
      endOffset: slice.end,
      excerpt: content.substring(slice.start, slice.end),
      note: saved.isEmpty ? note : null,
      color: color,
      style: style,
    );
    final failure = result.fold<Failure?>((failure) => failure, (highlight) {
      saved.add(highlight);
      return null;
    });
    if (failure != null) {
      return HighlightOutcome.issue(
        HighlightIssue.notSaved,
        failure: failure,
        highlights: saved,
      );
    }
  }
  return HighlightOutcome.created(saved);
}
