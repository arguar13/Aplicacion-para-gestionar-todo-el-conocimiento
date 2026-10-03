import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/features/ai_organize/domain/services/relation_confidence.dart';

void main() {
  RelationVerdict verdict(double cosine, AiCertainty? certainty) =>
      relationVerdictFor(
        relationConfidence(cosine: cosine, certainty: certainty),
      );

  test('con certeza alta y un parecido real, se aplica sola', () {
    expect(verdict(0.62, AiCertainty.high), RelationVerdict.apply);
    expect(verdict(0.95, AiCertainty.high), RelationVerdict.apply);
  });

  test('la certeza alta sola no alcanza: sin parecido, va a revisar', () {
    expect(verdict(0.5, AiCertainty.high), RelationVerdict.review);
    expect(verdict(0.6, AiCertainty.high), RelationVerdict.review);
  });

  test('lo que el modelo no afirma con claridad nunca se aplica solo', () {
    expect(verdict(1, AiCertainty.medium), RelationVerdict.review);
    expect(verdict(1, null), RelationVerdict.review);
  });

  test('una duda floja se descarta en vez de llenar «Para revisar»', () {
    expect(verdict(0.55, AiCertainty.medium), RelationVerdict.discard);
    expect(verdict(0.62, null), RelationVerdict.discard);
    expect(verdict(1, AiCertainty.low), RelationVerdict.discard);
  });

  test('el parecido deja de sumar en el techo', () {
    expect(
      relationConfidence(cosine: 0.99, certainty: AiCertainty.medium),
      relationConfidence(
        cosine: kRelationCosineCeiling,
        certainty: AiCertainty.medium,
      ),
    );
  });
}
