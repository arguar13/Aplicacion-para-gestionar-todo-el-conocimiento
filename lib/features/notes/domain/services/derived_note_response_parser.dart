/// Una afirmación tal como la escribió el modelo, todavía sin anclar: la
/// cita es una AFIRMACIÓN del modelo, no un dato —ver `anchorDerivedClaims`,
/// que la comprueba contra el texto real de alguna fuente—.
class RawDerivedClaim {
  const RawDerivedClaim({required this.text, this.quote});

  final String text;
  final String? quote;
}

/// Un grupo de [RawDerivedClaim] bajo un título opcional, tal como salió del
/// modelo.
class RawDerivedSection {
  const RawDerivedSection({required this.claims, this.heading});

  final String? heading;
  final List<RawDerivedClaim> claims;
}

final _headingLine = RegExp(r'^T:\s*(.+)$', caseSensitive: false);
final _claimLine = RegExp(r'^A:\s*(.+)$', caseSensitive: false);
final _quoteLine = RegExp(r'^C:\s*(.+)$', caseSensitive: false);

/// Interpreta la respuesta cruda del modelo como una lista de secciones con
/// sus afirmaciones (F16, D5).
///
/// Función pura a propósito, aparte de quien habla con el modelo —mismo
/// criterio que `parseFlashcardDrafts`—: lo único que puede fallar acá es el
/// formato de un texto, y eso se prueba sin ningún modelo de lenguaje de
/// verdad corriendo.
///
/// El formato esperado es `T: <título>` (opcional, agrupa lo que sigue),
/// `A: <afirmación>` y, después de una `A`, opcionalmente `C: <cita textual
/// de una fuente>` — nada de Markdown ni numeración propia: cuanto más
/// simple el formato pedido, menos formas tiene el modelo de desviarse de
/// él. Una línea que no matchea ninguno de los tres patrones se ignora en
/// silencio, mismo motivo que el parser de tarjetas: un modelo chico no es
/// tan confiable siguiendo instrucciones como uno grande.
List<RawDerivedSection> parseDerivedNoteResponse(String rawResponse) {
  final sections = <RawDerivedSection>[];
  String? heading;
  var claims = <RawDerivedClaim>[];

  void flushSection() {
    if (claims.isNotEmpty) {
      sections.add(RawDerivedSection(heading: heading, claims: claims));
    }
    claims = [];
  }

  for (final rawLine in rawResponse.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final headingMatch = _headingLine.firstMatch(line);
    if (headingMatch != null) {
      flushSection();
      heading = headingMatch.group(1)!.trim();
      continue;
    }

    final claimMatch = _claimLine.firstMatch(line);
    if (claimMatch != null) {
      final text = claimMatch.group(1)!.trim();
      if (text.isNotEmpty) claims.add(RawDerivedClaim(text: text));
      continue;
    }

    // La cita pertenece a la afirmación que se acaba de agregar, si esa
    // todavía no tiene: una `C:` suelta, o una segunda, se ignora.
    final quoteMatch = _quoteLine.firstMatch(line);
    if (quoteMatch != null && claims.isNotEmpty && claims.last.quote == null) {
      final text = quoteMatch.group(1)!.trim();
      if (text.isNotEmpty) {
        final last = claims.removeLast();
        claims.add(RawDerivedClaim(text: last.text, quote: text));
      }
    }
  }
  flushSection();

  return sections;
}
