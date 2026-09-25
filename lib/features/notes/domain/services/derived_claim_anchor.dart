import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/flashcards/domain/services/source_quote_locator.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_response_parser.dart';

/// Ancla lo que el modelo propuso contra el texto real de [sources] (F16,
/// D6): una afirmación cuya cita no aparece TEXTUAL en ninguna fuente se
/// descarta entera, no solo su fragmento —a diferencia de una tarjeta
/// (F11), que se guarda igual sin cita cuando no coincide—. Reusa
/// `locateQuote`: misma comprobación exacta, primera coincidencia, nada de
/// comparaciones aproximadas.
///
/// Cada fuente ancla como mucho UNA afirmación: `RelationKind.extractedFrom`
/// solo admite un vínculo por par de elementos (`UNIQUE(from_item_id,
/// to_item_id, kind)`), así que una segunda afirmación que citara la misma
/// fuente no tendría dónde guardar su propio rango — se descarta, no se
/// junta con la primera ni se guarda sin ancla.
///
/// El offset final es el de la fuente ENTERA, no el del extracto que vio el
/// modelo: `source.excerpt` empieza en `source.sourceCharStart` del texto
/// real, así que la cita se busca dentro del extracto y el resultado se
/// corre esa misma cantidad. Una fuente sin `sourceCharStart` —sin chunks
/// de verdad, como una nota manual— nunca puede anclar nada.
///
/// Una sección que se queda sin ninguna afirmación anclada se descarta
/// entera: un título sin nada debajo no sirve de nada.
List<DerivedSection> anchorDerivedClaims(
  List<RawDerivedSection> raw,
  List<ChatSource> sources,
) {
  final usedSourceIds = <String>{};
  final sections = <DerivedSection>[];

  for (final rawSection in raw) {
    final claims = <DerivedClaim>[];
    for (final rawClaim in rawSection.claims) {
      final anchored = _anchor(rawClaim, sources, usedSourceIds);
      if (anchored == null) continue;
      claims.add(anchored);
      usedSourceIds.add(anchored.sourceItemId);
    }
    if (claims.isNotEmpty) {
      sections.add(DerivedSection(heading: rawSection.heading, claims: claims));
    }
  }

  return sections;
}

DerivedClaim? _anchor(
  RawDerivedClaim claim,
  List<ChatSource> sources,
  Set<String> usedSourceIds,
) {
  for (final source in sources) {
    if (usedSourceIds.contains(source.itemId)) continue;
    final base = source.sourceCharStart;
    if (base == null) continue;

    final range = locateQuote(source.excerpt, claim.quote);
    if (range == null) continue;

    return DerivedClaim(
      text: claim.text,
      sourceItemId: source.itemId,
      sourceCharStart: base + range.start,
      sourceCharEnd: base + range.end,
    );
  }
  return null;
}
