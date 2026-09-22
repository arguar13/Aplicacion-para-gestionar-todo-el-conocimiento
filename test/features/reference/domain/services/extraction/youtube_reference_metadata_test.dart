import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/youtube_reference_metadata.dart';

void main() {
  final source = Source(
    id: 's1',
    kind: SourceKind.youtube,
    capturedAt: DateTime(2024),
    authorName: 'Canal de Prueba',
    publishedAt: DateTime(2021, 8, 3),
  );

  test('el canal se propone como autor institucional', () {
    final metadata = youtubeReferenceMetadata(source);

    expect(metadata.reference.contributors, hasLength(1));
    final author = metadata.reference.contributors.single;
    expect(author.name.isInstitution, isTrue);
    expect(author.name.label, 'Canal de Prueba');
    expect(metadata.reference.type, ReferenceType.documentary);
  });

  test('la fecha de publicacion se propone con el dia completo', () {
    final metadata = youtubeReferenceMetadata(source);

    expect(metadata.publishedAt, DateTime(2021, 8, 3));
    expect(metadata.publicationPrecision, PublicationPrecision.day);
  });

  test('sin canal, no hay nada que proponer', () {
    final withoutChannel = source.copyWith(authorName: null);

    expect(youtubeReferenceMetadata(withoutChannel).isEmpty, isTrue);
  });

  test('sin fecha, se propone el autor sin fecha', () {
    final withoutDate = source.copyWith(publishedAt: null);

    final metadata = youtubeReferenceMetadata(withoutDate);

    expect(metadata.publishedAt, isNull);
    expect(metadata.publicationPrecision, isNull);
    expect(metadata.reference.contributors, isNotEmpty);
  });
}
