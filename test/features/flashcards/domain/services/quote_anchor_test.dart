import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/services/quote_anchor.dart';

/// Los textos de los que salen las citas de abajo: un artículo de historia,
/// uno de ciencia y uno en inglés, como los que llegan a la biblioteca.
const _rome =
    'Roma fue fundada en el año 753 antes de Cristo, según la tradición, por '
    'Rómulo, que le dio su nombre. Durante la monarquía la gobernaron siete '
    'reyes. En el 509 a. C. los romanos expulsaron a Tarquinio el Soberbio y '
    'fundaron la república.\n\n'
    'El Senado asesoraba a los cónsules, que se elegían cada año y tenían el '
    'mando del ejército. En tiempos de crisis se podía nombrar un dictador por '
    'seis meses. La república duró casi cinco siglos, hasta que Augusto se '
    'convirtió en el primer emperador en el 27 a. C.';

const _cell =
    'La mitocondria es el orgánulo que produce la mayor parte de la energía '
    'de la célula, en forma de ATP, mediante la respiración celular. Tiene '
    'su propio ADN, heredado casi siempre de la madre.\n\n'
    'La fotosíntesis ocurre en los cloroplastos: las plantas usan la luz del '
    'sol, el agua y el dióxido de carbono para fabricar glucosa, y liberan '
    'oxígeno. Sin ella no habría oxígeno libre en la atmósfera.';

const _press =
    'Johannes Gutenberg introduced movable-type printing to Europe around '
    '1440. His press made books far cheaper to produce, and within fifty '
    'years printing shops had spread to more than two hundred cities. The '
    'Gutenberg Bible, printed in Mainz, is the most famous early book.';

/// Citas cambiadas como las cambia un modelo chico: de cada una, el texto y
/// el pasaje del que sale.
const _paraphrased = [
  // Otro tiempo verbal, otra voz.
  (
    _rome,
    'Rómulo fundó Roma en el año 753 antes de Cristo',
    'Roma fue fundada',
  ),
  // Sinónimos.
  (_rome, 'El Senado aconsejaba a los cónsules', 'El Senado asesoraba'),
  // La derivada en vez de la palabra.
  (_rome, 'La fundación de Roma fue en el 753 a. C.', 'Roma fue fundada'),
  // Otra forma de escribir la fecha.
  (_rome, 'Roma fue fundada en el 753 a. C. por Rómulo', 'Roma fue fundada'),
  // Resumida.
  (_rome, 'Durante la monarquía Roma tuvo siete reyes', 'Durante la monarquía'),
  // El orden cambiado.
  (
    _rome,
    'los cónsules tenían el mando del ejército y se elegían cada año',
    'que se elegían cada año',
  ),
  // Dos oraciones juntas.
  (
    _rome,
    'Expulsaron a Tarquinio el Soberbio en el 509 a. C. y fundaron la '
        'república',
    'expulsaron a Tarquinio',
  ),
  // Con un sujeto que el texto sobreentiende.
  (
    _rome,
    'En tiempos de crisis los romanos podían nombrar un dictador por seis '
        'meses',
    'En tiempos de crisis',
  ),
  (
    _rome,
    'La república romana duró casi cinco siglos',
    'La república duró casi cinco siglos',
  ),
  (
    _rome,
    'Augusto fue el primer emperador, en el año 27 a. C.',
    'Augusto se convirtió',
  ),
  // Sin acentos y en minúsculas, con otra puntuación.
  (
    _rome,
    'el senado asesoraba a los consules; se elegian cada año',
    'El Senado asesoraba',
  ),
  (_rome, 'Roma fue gobernada por siete reyes durante la monarquía', 'siete'),
  (
    _cell,
    'La mitocondria produce la mayor parte de la energía de la célula',
    'La mitocondria es el orgánulo',
  ),
  (
    _cell,
    'la mitocondria genera casi toda la energía celular en forma de ATP',
    'La mitocondria es el orgánulo',
  ),
  (
    _cell,
    'Las mitocondrias tienen su propio ADN, que se hereda de la madre',
    'Tiene su propio ADN',
  ),
  (
    _cell,
    'La fotosíntesis se produce en los cloroplastos',
    'La fotosíntesis ocurre',
  ),
  (
    _cell,
    'Las plantas fabrican glucosa con luz solar, agua y dióxido de carbono',
    'las plantas usan la luz',
  ),
  (
    _cell,
    'Sin la fotosíntesis no existiría oxígeno libre en la atmósfera',
    'Sin ella no habría oxígeno',
  ),
  (
    _cell,
    'mediante la respiración celular la mitocondria produce ATP',
    'mediante la respiración celular',
  ),
  (
    _press,
    'Gutenberg brought movable type printing to Europe around 1440',
    'introduced movable-type printing',
  ),
  (
    _press,
    'His printing press made books much cheaper to produce',
    'His press made books',
  ),
  (
    _press,
    'Within fifty years, print shops spread to over two hundred cities',
    'within fifty years',
  ),
  (
    _press,
    'The most famous early book is the Gutenberg Bible, printed in Mainz',
    'The Gutenberg Bible',
  ),
  (
    _press,
    'Gutenberg introduced printing with movable type in Europe in 1440',
    'introduced movable-type printing',
  ),
];

/// Citas que no son de ningún pasaje del texto: del mismo tema, armadas con
/// sus palabras pero diciendo otra cosa, o de otro texto.
const _foreign = [
  (_rome, 'Julio César cruzó el Rubicón en el 49 a. C.'),
  (_rome, 'Los romanos construyeron acueductos para llevar agua a la ciudad'),
  (_rome, 'Roma fue la capital del Imperio bizantino'),
  (_rome, 'El emperador Constantino legalizó el cristianismo'),
  (_rome, 'Los gladiadores combatían en el Coliseo'),
  (_rome, 'Rómulo y Remo fueron amamantados por una loba'),
  (_rome, 'La mitocondria produce la energía de la célula'),
  (_rome, 'Gutenberg printed the Bible in Mainz'),
  (_cell, 'El núcleo contiene la información genética de la célula'),
  (_cell, 'Los ribosomas fabrican proteínas a partir del ARN mensajero'),
  (_cell, 'Las plantas absorben nitrógeno del suelo por las raíces'),
  (_cell, 'La glucosa se almacena en el hígado como glucógeno'),
  (_cell, 'El Senado asesoraba a los cónsules de la república'),
  (_press, 'The printing press was invented in China centuries earlier'),
  (_press, 'Martin Luther used pamphlets to spread the Reformation'),
  (_press, 'Paper was made from rags before wood pulp was used'),
  (_press, 'Books were copied by hand in medieval monasteries'),
  (_press, 'Roma fue fundada en el año 753 antes de Cristo'),
  // Con palabras del texto, pero de oraciones distintas: dicen otra cosa.
  (_rome, 'Rómulo fue el primer emperador de Roma'),
  (_rome, 'El dictador gobernaba el Senado durante cinco siglos'),
  (_rome, 'Los siete reyes elegían a los cónsules en tiempos de crisis'),
  (_press, 'Gutenberg printed two hundred books in Mainz'),
];

/// Citas que cambian algo DENTRO de la oración de la que salen —el sujeto, a
/// quién se refiere—: se ubican en esa oración, que es de donde salen. Es el
/// límite de cualquier búsqueda por palabras (ver `kQuoteAnchorMinRecall`).
const _twisted = [
  (
    _rome,
    'Augusto expulsó a Tarquinio y fundó la república',
    'los romanos expulsaron',
  ),
  (
    _cell,
    'La mitocondria fabrica glucosa con la luz del sol',
    'las plantas usan la luz',
  ),
  (
    _cell,
    'La célula libera oxígeno mediante la respiración celular',
    'mediante la respiración celular',
  ),
  (
    _press,
    'The Bible made printing shops cheaper in Europe',
    'His press made books',
  ),
];

void main() {
  group('el umbral, medido', () {
    test('las citas parafraseadas reúnen al menos el umbral', () {
      for (final (text, quote, _) in _paraphrased) {
        final recall = quoteAnchorRecall(text, quote);
        expect(
          recall,
          greaterThanOrEqualTo(kQuoteAnchorMinRecall),
          reason: '«$quote»: $recall',
        );
      }
    });

    test('las que no son de ningún pasaje quedan por debajo', () {
      for (final (text, quote) in _foreign) {
        final recall = quoteAnchorRecall(text, quote) ?? 0;
        expect(recall, lessThan(kQuoteAnchorMinRecall), reason: '«$quote»');
      }
    });

    test('cada parafraseada cae en la oración de la que sale; también la que '
        'cambia algo dentro de ella', () {
      for (final (text, quote, passage) in [..._paraphrased, ..._twisted]) {
        final anchor = anchorQuote(text, quote);
        expect(anchor, isNotNull, reason: quote);
        final found = text.substring(anchor!.start, anchor.end);
        final expected = text.indexOf(passage);
        expect(expected, isNonNegative, reason: passage);
        // El pasaje encontrado toca la frase marcada de la oración de la que
        // sale la cita: empieza antes de que termine y termina después de que
        // empiece.
        expect(
          anchor.start < expected + passage.length && anchor.end > expected,
          isTrue,
          reason: '«$quote» cayó en «$found»',
        );
        expect(anchor.exact, isFalse);
      }
    });
  });

  test('una cita textual es exacta, con su rango', () {
    const quote = 'El Senado asesoraba a los cónsules';

    final anchor = anchorQuote(_rome, quote)!;

    expect(anchor.exact, isTrue);
    expect(_rome.substring(anchor.start, anchor.end), quote);
  });

  test('sin distinguir mayúsculas, acentos, puntuación ni espacios, el rango '
      'es el del texto real', () {
    final anchor = anchorQuote(
      _rome,
      '  el senado   asesoraba a los CONSULES  ',
    )!;

    expect(anchor.exact, isFalse);
    expect(
      _rome.substring(anchor.start, anchor.end),
      'El Senado asesoraba a los cónsules',
    );
  });

  test('una parafraseada se ancla de la primera a la última palabra que '
      'reconoce', () {
    final anchor = anchorQuote(
      _rome,
      'La república romana duró casi cinco '
      'siglos',
    )!;

    // «La» no es de nadie: el pasaje va de la primera palabra que dice algo
    // a la última.
    expect(
      _rome.substring(anchor.start, anchor.end),
      'república duró casi cinco siglos',
    );
  });

  test('una cita muy corta solo cuenta textual', () {
    // Dos palabras con contenido: cualquier pasaje que las nombre parecería
    // el suyo.
    expect(anchorQuote(_rome, 'reyes romanos'), isNull);
    expect(anchorQuote(_rome, 'siete reyes'), isNotNull);
  });

  test('sin cita, sin texto o sin palabras no ubica nada', () {
    expect(anchorQuote(_rome, null), isNull);
    expect(anchorQuote(_rome, '   '), isNull);
    expect(anchorQuote('', 'Roma fue fundada'), isNull);
    expect(anchorQuote(_rome, '¿¡…!?'), isNull);
  });
}
