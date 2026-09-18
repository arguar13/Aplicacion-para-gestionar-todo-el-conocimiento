import 'dart:convert';

import 'package:crypto/crypto.dart';

/// La base de FNV-1a de 64 bits (el punto de partida del hash, antes de
/// mezclar el primer byte).
final _fnv64OffsetBasis = BigInt.parse('cbf29ce484222325', radix: 16);

/// El primo de FNV-1a de 64 bits.
final _fnv64Prime = BigInt.parse('100000001b3', radix: 16);

/// Máscara de 64 bits en 1 — recorta cualquier desborde de la
/// multiplicación a 64 bits, ya que `BigInt` no tiene ancho fijo.
final _mask64 = (BigInt.one << 64) - BigInt.one;

/// Minúsculas, sin puntuación ni símbolos, espacios colapsados — el mismo
/// texto con formato distinto (mayúsculas, signos, espacios de más)
/// normaliza igual.
///
/// Preserva letras y números de cualquier alfabeto (`\p{L}`/`\p{N}`, no
/// solo ASCII): un acento o una eñe no es puntuación.
String normalizeForDedup(String text) {
  final lowercased = text.toLowerCase();
  final withoutPunctuation = lowercased.replaceAll(
    RegExp(r'[^\p{L}\p{N}\s]', unicode: true),
    '',
  );
  return withoutPunctuation
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .join(' ');
}

/// SHA-256 de [normalized] — duplicados EXACTOS: el mismo texto
/// normalizado da siempre el mismo hash, sin importar mayúsculas,
/// puntuación o espacios de más en el original.
///
/// Distinto de `KnowledgeSources.contentHash` (F5): ese hashea el texto
/// CRUDO y sirve de guarda de idempotencia para el chunking, no para
/// comparar contra otro elemento — mezclar los dos significados sería
/// confuso y frágil.
String contentHashOf(String normalized) =>
    sha256.convert(utf8.encode(normalized)).toString();

/// Huella de [bits] bits para CASI-duplicados (simhash): shingles de tres
/// palabras sobre [normalized], hash FNV-1a de 64 bits por shingle, voto
/// ponderado por bit — dos textos parecidos dan huellas con poca
/// [hammingDistance] entre sí, aunque no sean idénticos byte a byte.
///
/// Con menos de tres palabras, todo [normalized] es un solo shingle: sin
/// esto, cualquier texto corto votaría cero en cada bit y todos
/// terminarían con la misma huella (distancia 0 entre cualquier par),
/// que los haría parecer idénticos entre sí sin serlo. Texto vacío
/// devuelve una huella de puros ceros — no hay nada que votar.
String simhashOf(String normalized, {int bits = 64}) {
  final words = normalized.split(' ').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return '0' * (bits ~/ 4);

  final shingles = <String>[];
  if (words.length < 3) {
    shingles.add(words.join(' '));
  } else {
    for (var i = 0; i + 3 <= words.length; i++) {
      shingles.add('${words[i]} ${words[i + 1]} ${words[i + 2]}');
    }
  }

  final votes = List<int>.filled(bits, 0);
  for (final shingle in shingles) {
    final hash = _fnv1a64(shingle);
    for (var bit = 0; bit < bits; bit++) {
      final bitIsSet = (hash >> bit) & BigInt.one == BigInt.one;
      votes[bit] += bitIsSet ? 1 : -1;
    }
  }

  var result = BigInt.zero;
  for (var bit = 0; bit < bits; bit++) {
    if (votes[bit] > 0) result |= BigInt.one << bit;
  }
  return result.toRadixString(16).padLeft(bits ~/ 4, '0');
}

/// Cuántos bits difieren entre dos huellas de [simhashOf], en hexadecimal
/// — mientras más chica, más parecidos los textos originales.
int hammingDistance(String simhashA, String simhashB) {
  var xor =
      BigInt.parse(simhashA, radix: 16) ^ BigInt.parse(simhashB, radix: 16);

  var distance = 0;
  while (xor > BigInt.zero) {
    if (xor & BigInt.one == BigInt.one) distance++;
    xor >>= 1;
  }
  return distance;
}

/// FNV-1a de 64 bits sobre los bytes UTF-8 de [text] — determinístico,
/// rápido, y en `BigInt` para dar el mismo resultado en cualquier
/// plataforma (a diferencia de `int`, que en la web es un `double` de 53
/// bits de mantisa, insuficiente para aritmética de 64 bits exacta).
BigInt _fnv1a64(String text) {
  var hash = _fnv64OffsetBasis;
  for (final byte in utf8.encode(text)) {
    hash = (hash ^ BigInt.from(byte)) & _mask64;
    hash = (hash * _fnv64Prime) & _mask64;
  }
  return hash;
}
