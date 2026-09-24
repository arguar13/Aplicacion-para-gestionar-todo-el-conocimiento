import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/services/bibliographic_identifiers.dart';

/// Quién ya tiene cada identificador bibliográfico, para no importar dos
/// veces la misma obra (F15, D9): DOI (normalizado) → ISBN-13 → URL
/// canónica, en ese orden —el primero que coincide gana—; recién si ninguno
/// coincide entra la coincidencia difusa (título, año, primer autor), que
/// no vive acá: ese es el comando 15b.
///
/// Se arma UNA vez por corrida de importación, con el repositorio de
/// identidad, no una consulta por entrada: una importación de miles de
/// referencias no puede ser miles de vueltas a la base.
@immutable
class ReferenceIdentityIndex {
  const ReferenceIdentityIndex({
    required Map<String, String> byDoi,
    required Map<String, String> byIsbn,
    required Map<String, String> byUrl,
  }) : _byDoi = byDoi,
       _byIsbn = byIsbn,
       _byUrl = byUrl;

  final Map<String, String> _byDoi;
  final Map<String, String> _byIsbn;
  final Map<String, String> _byUrl;

  /// El id de la fuente que ya tiene este DOI, este ISBN o este enlace
  /// —el primero de los tres que coincide, en ese orden—, o `null` si
  /// ninguno coincide con nada.
  ///
  /// [doi] e [isbn] llegan tal como los guarda `ReferenceData` —ya
  /// normalizados—; [url] llega tal cual, sin normalizar: acá se lo
  /// canonicaliza, igual que a los que arma el repositorio de identidad.
  String? find({String? doi, String? isbn, String? url}) {
    if (doi != null && _byDoi.containsKey(doi)) return _byDoi[doi];
    if (isbn != null && _byIsbn.containsKey(isbn)) return _byIsbn[isbn];
    if (url != null) {
      final canonical = canonicalUrl(url);
      if (canonical != null && _byUrl.containsKey(canonical)) {
        return _byUrl[canonical];
      }
    }
    return null;
  }
}
