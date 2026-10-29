import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_passage.dart';

/// F43, paso 9: «Ver en el documento» encuentra el pasaje que copió la IA,
/// aunque no lo haya copiado letra por letra.
void main() {
  const text =
      'Capítulo 7.\n\nEntonces Moisés y Aarón fueron ante el Faraón, e '
      'hicieron como el Señor les había mandado. Aarón echó su vara delante '
      'del Faraón y de sus siervos, y se convirtió en culebra.';

  String at(PassageRange range) => text.substring(range.start, range.end);

  test('tal cual: el tramo exacto', () {
    final range = findPassage(text, 'Aarón echó su vara delante del Faraón')!;
    expect(at(range), 'Aarón echó su vara delante del Faraón');
  });

  test('sin tildes, con otras mayúsculas, otros signos y espacios de más', () {
    final range = findPassage(
      text,
      '«moises y aaron   fueron ante el faraon e hicieron»',
    )!;
    expect(at(range), 'Moisés y Aarón fueron ante el Faraón, e hicieron');
  });

  test('si el pasaje entero no está, su comienzo alcanza para llegar', () {
    final range = findPassage(
      text,
      'Aarón echó su vara delante del Faraón y de todo su pueblo reunido',
    )!;
    // Las ocho primeras palabras están; lo demás lo inventó.
    expect(at(range), 'Aarón echó su vara delante del Faraón y');
  });

  test('palabras enteras: «vara» no se encuentra dentro de «varado»', () {
    expect(findPassage('el barco quedó varado', 'vara'), isNull);
    expect(findPassage('una vara de madera', 'vara')!.start, 4);
  });

  test('un comienzo de pocas letras no sirve: no se adivina', () {
    // «de la casa de» está en cualquier lado: no lleva a ningún lugar.
    expect(
      findPassage(
        'vino de la casa de enfrente',
        'de la casa de mi abuela materna con patios',
      ),
      isNull,
    );
  });

  test('gana la primera aparición', () {
    final range = findPassage('uno dos. uno dos.', 'uno dos')!;
    expect(range.start, 0);
  });

  test('vacío o sin letras: nada', () {
    expect(findPassage(text, '   '), isNull);
    expect(findPassage(text, '«—»'), isNull);
    expect(findPassage('', 'algo'), isNull);
  });

  test('otras escrituras: el griego, en minúscula', () {
    const greek = 'Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν';
    final range = findPassage(greek, 'ὁ λόγος ἦν πρὸς')!;
    expect(greek.substring(range.start, range.end), 'ὁ λόγος ἦν πρὸς');
  });
}
