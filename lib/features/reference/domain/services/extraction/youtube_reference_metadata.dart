import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source.dart';

/// Lo que se puede proponer como referencia de un video de YouTube (F15,
/// D12), a partir de lo que la transcripción ya guardó en [source]: el canal
/// como autor institucional y la fecha de publicación, con el día completo
/// —es lo que trae la API de YouTube—.
///
/// A diferencia del PDF y de la página, no hace falta leer nada de nuevo: el
/// canal y la fecha ya están en la fuente desde que se capturó el video, así
/// que esto es una función pura sobre lo que ya se guardó, sin red ni
/// archivo. Por eso se puede volver a llamar al abrir el formulario sin
/// costo.
ExtractedMetadata youtubeReferenceMetadata(Source source) {
  final channel = source.authorName?.trim();
  if (channel == null || channel.isEmpty) return const ExtractedMetadata();

  final publishedAt = source.publishedAt;
  return ExtractedMetadata(
    publishedAt: publishedAt,
    publicationPrecision: publishedAt == null ? null : PublicationPrecision.day,
    reference: ReferenceData(
      type: ReferenceType.documentary,
      contributors: [Contributor(name: PersonName.institution(channel))],
    ),
  );
}
