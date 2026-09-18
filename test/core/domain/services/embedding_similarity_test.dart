import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';

void main() {
  group('cosineSimilarity', () {
    test('vectores paralelos: 1.0', () {
      expect(cosineSimilarity([1, 2, 3], [2, 4, 6]), closeTo(1.0, 1e-9));
    });

    test('vectores ortogonales: 0.0', () {
      expect(cosineSimilarity([1, 0], [0, 1]), closeTo(0.0, 1e-9));
    });

    test('vectores opuestos: -1.0', () {
      expect(cosineSimilarity([1, 2, 3], [-1, -2, -3]), closeTo(-1.0, 1e-9));
    });

    test('un vector todo ceros: 0.0, no NaN', () {
      expect(cosineSimilarity([0, 0, 0], [1, 2, 3]), 0.0);
    });

    test('el mismo vector contra sí mismo: 1.0', () {
      expect(cosineSimilarity([3, 1, 4], [3, 1, 4]), closeTo(1.0, 1e-9));
    });
  });

  group('encode/decodeEmbeddingVector', () {
    test('el round-trip preserva los valores, con tolerancia float32', () {
      final original = [0.1, -2.5, 3.75, 0.0, -1.0];

      final encoded = encodeEmbeddingVector(original);
      final decoded = decodeEmbeddingVector(encoded);

      expect(decoded.length, original.length);
      for (var i = 0; i < original.length; i++) {
        expect(decoded[i], closeTo(original[i], 1e-6));
      }
    });

    test('un vector vacío no revienta', () {
      expect(decodeEmbeddingVector(encodeEmbeddingVector(const [])), isEmpty);
    });
  });

  group('centroid', () {
    test('de un solo vector, es el vector mismo', () {
      expect(
        centroid([
          [1.0, 2.0, 3.0],
        ]),
        [1.0, 2.0, 3.0],
      );
    });

    test('de varios vectores, es el promedio elemento a elemento', () {
      final result = centroid([
        [2.0, 4.0],
        [4.0, 8.0],
        [6.0, 0.0],
      ]);

      expect(result, [4.0, 4.0]);
    });
  });
}
