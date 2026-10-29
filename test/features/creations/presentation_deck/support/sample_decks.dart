import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_json.dart';

/// Un mazo como el que escribiría la IA sobre un documento procesado: una
/// diapositiva de cada uno de los doce diseños, con textos de largo común.
/// Con esto nada debería cortarse con «…».
SlideDeck sampleDeck({bool illustrations = false}) => SlideDeck(
  title: 'Éxodo: liberación y alianza',
  subtitle: 'Un recorrido por el comentario de Alonso',
  format: DeckFormat.presenter,
  slides: [
    Slide.cover(
      title: 'Éxodo: liberación y alianza',
      subtitle: 'Del Egipto de los faraones al pie del Sinaí',
      kicker: 'Estudio · Comentario de Alonso',
      illustrationPrompt: illustrations ? 'El mar abierto al amanecer' : null,
      speakerNotes: 'Hoy recorremos el libro del Éxodo en cuatro partes.',
    ),
    const Slide.section(
      title: 'La salida de Egipto',
      subtitle: 'Opresión, llamado y las diez plagas',
    ),
    Slide.bullets(
      title: 'Por qué importa el Éxodo',
      bullets: const [
        'Es el relato fundante de la identidad de Israel',
        'Une la liberación política con la alianza religiosa',
        'Ofrece el marco de la Pascua y de la Ley',
        'Inspira movimientos de liberación hasta hoy',
      ],
      illustrationPrompt: illustrations ? 'Un pueblo que camina' : null,
    ),
    const Slide.twoColumns(
      title: 'Dos lecturas del texto',
      left: SlideColumn(
        heading: 'Histórica',
        points: [
          'Busca huellas en Egipto',
          'Fecha la salida en el siglo XIII a. C.',
          'Compara con otras migraciones',
        ],
      ),
      right: SlideColumn(
        heading: 'Teológica',
        points: [
          'Lee la liberación como obra de Dios',
          'Ve en la alianza un pacto de amor',
          'Relaciona el relato con la liturgia',
        ],
      ),
    ),
    const Slide.quote(
      quote: 'Deja ir a mi pueblo, para que me sirva en el desierto',
      author: 'Moisés ante el faraón',
      source: 'Éxodo 7, 16',
    ),
    const Slide.bigNumber(
      title: 'El camino por el desierto',
      value: '40 años',
      label: 'de travesía hasta la tierra prometida',
      detail: 'Una generación entera: los que salieron de Egipto no llegan.',
    ),
    const Slide.steps(
      title: 'De la esclavitud a la alianza',
      steps: [
        SlideStep(title: 'Opresión', detail: 'Trabajo forzado en Egipto'),
        SlideStep(title: 'Llamado', detail: 'La zarza que arde'),
        SlideStep(title: 'Liberación', detail: 'El paso del mar'),
        SlideStep(title: 'Alianza', detail: 'Los mandamientos en el Sinaí'),
      ],
    ),
    const Slide.comparison(
      title: 'Moisés y el faraón',
      left: SlideColumn(
        heading: 'Moisés',
        points: ['Duda y pide ayuda', 'Habla por su pueblo', 'Obedece'],
      ),
      right: SlideColumn(
        heading: 'Faraón',
        points: ['Endurece su corazón', 'Habla por su poder', 'Se resiste'],
      ),
      conclusion: 'El relato contrapone la fragilidad que escucha al poder.',
    ),
    const Slide.timeline(
      title: 'Los hitos del relato',
      events: [
        TimelineEvent(
          date: 'Cap. 1',
          title: 'Opresión',
          detail: 'Un rey nuevo',
        ),
        TimelineEvent(date: 'Cap. 3', title: 'La zarza', detail: 'El llamado'),
        TimelineEvent(date: 'Cap. 12', title: 'Pascua', detail: 'La salida'),
        TimelineEvent(date: 'Cap. 14', title: 'El mar', detail: 'El paso'),
        TimelineEvent(date: 'Cap. 20', title: 'Sinaí', detail: 'La Ley'),
      ],
    ),
    Slide.imageText(
      title: 'El paso del mar',
      body:
          'El momento central del libro: el pueblo cruza entre las aguas y '
          'el ejército que lo persigue queda atrás.',
      bullets: const [
        'Signo de la nueva creación',
        'Origen del canto de María',
      ],
      illustrationPrompt: illustrations ? 'Las aguas abiertas' : null,
    ),
    const Slide.conceptGrid(
      title: 'Conceptos clave',
      concepts: [
        SlideConcept(
          title: 'Alianza',
          detail: 'Un pacto que obliga a las dos partes',
          icon: 'handshake',
        ),
        SlideConcept(
          title: 'Pascua',
          detail: 'La fiesta que recuerda la salida',
          icon: 'calendar',
        ),
        SlideConcept(
          title: 'Ley',
          detail: 'Las palabras que ordenan la vida',
          icon: 'gavel',
        ),
        SlideConcept(
          title: 'Desierto',
          detail: 'El lugar de la prueba',
          icon: 'landscape',
        ),
        SlideConcept(
          title: 'Libertad',
          detail: 'Salir para servir',
          icon: 'flag',
        ),
        SlideConcept(
          title: 'Presencia',
          detail: 'La nube y el fuego',
          icon: 'fire',
        ),
      ],
    ),
    const Slide.closing(
      title: 'Para llevarse',
      subtitle: 'Gracias por acompañar el recorrido',
      takeaways: [
        'La liberación es el comienzo, no el final',
        'La alianza da forma a la libertad',
        'El relato se vuelve memoria viva en la Pascua',
      ],
    ),
  ],
);

String _long(String base, int words) {
  final parts = <String>[];
  var i = 0;
  while (parts.length < words) {
    parts.add(i.isEven ? base : 'extraordinariamente');
    i++;
  }
  return parts.join(' ');
}

/// El peor caso: cada campo en su tope de [SlideLimits] y cada lista con lo
/// máximo que se acepta, con palabras largas. Acá sí puede cortarse con «…»,
/// pero nunca desbordar.
SlideDeck longDeck() {
  String text(int limit) =>
      SlideDeckJson.clamp(_long('Constantinopla', limit), limit);
  final title = text(SlideLimits.title);
  final bullets = [
    for (var i = 0; i < SlideLimits.bullets; i++) text(SlideLimits.bullet),
  ];
  final column = SlideColumn(
    heading: text(SlideLimits.label),
    points: [
      for (var i = 0; i < SlideLimits.columnPoints; i++)
        text(SlideLimits.bullet),
    ],
  );
  return SlideDeck(
    title: title,
    subtitle: text(SlideLimits.subtitle),
    slides: [
      Slide.cover(
        title: title,
        subtitle: text(SlideLimits.subtitle),
        kicker: text(SlideLimits.kicker),
        illustrationPrompt: 'algo',
      ),
      Slide.section(
        title: title,
        subtitle: text(SlideLimits.subtitle),
        illustrationPrompt: 'algo',
      ),
      Slide.bullets(title: title, bullets: bullets, illustrationPrompt: 'algo'),
      Slide.twoColumns(title: title, left: column, right: column),
      Slide.quote(
        quote: text(SlideLimits.quote),
        author: text(SlideLimits.attribution),
        source: text(SlideLimits.attribution),
        illustrationPrompt: 'algo',
      ),
      Slide.bigNumber(
        title: title,
        value: '3.000.000.000.000',
        label: text(SlideLimits.label),
        detail: text(SlideLimits.detail),
      ),
      Slide.steps(
        title: title,
        steps: [
          for (var i = 0; i < SlideLimits.steps; i++)
            SlideStep(
              title: text(SlideLimits.label),
              detail: text(SlideLimits.detail),
            ),
        ],
      ),
      Slide.comparison(
        title: title,
        left: column,
        right: column,
        conclusion: text(SlideLimits.detail),
      ),
      Slide.timeline(
        title: title,
        events: [
          for (var i = 0; i < SlideLimits.events; i++)
            TimelineEvent(
              date: text(SlideLimits.label),
              title: text(SlideLimits.label),
              detail: text(SlideLimits.detail),
            ),
        ],
      ),
      Slide.imageText(
        title: title,
        body: text(SlideLimits.body),
        bullets: bullets.take(4).toList(),
      ),
      Slide.conceptGrid(
        title: title,
        concepts: [
          for (var i = 0; i < SlideLimits.concepts; i++)
            SlideConcept(
              title: text(SlideLimits.label),
              detail: text(SlideLimits.detail),
              icon: 'no-existe',
            ),
        ],
      ),
      Slide.closing(
        title: title,
        subtitle: text(SlideLimits.subtitle),
        takeaways: [
          for (var i = 0; i < SlideLimits.takeaways; i++)
            text(SlideLimits.bullet),
        ],
        illustrationPrompt: 'algo',
      ),
    ],
  );
}

/// Un mazo mínimo: cada diseño con lo justo (sin bajadas, sin detalles, dos
/// elementos en las listas).
SlideDeck minimalDeck() => const SlideDeck(
  title: 'Mínimo',
  slides: [
    Slide.cover(title: 'Uno'),
    Slide.section(title: 'Dos'),
    Slide.bullets(title: 'Tres', bullets: ['a', 'b']),
    Slide.twoColumns(
      title: '',
      left: SlideColumn(points: ['a']),
      right: SlideColumn(points: ['b']),
    ),
    Slide.quote(quote: 'Breve'),
    Slide.bigNumber(value: '7'),
    Slide.steps(
      title: '',
      steps: [
        SlideStep(title: 'a'),
        SlideStep(title: 'b'),
      ],
    ),
    Slide.comparison(
      title: '',
      left: SlideColumn(heading: 'A'),
      right: SlideColumn(heading: 'B'),
    ),
    Slide.timeline(
      title: '',
      events: [
        TimelineEvent(date: '1', title: 'a'),
        TimelineEvent(date: '2', title: 'b'),
      ],
    ),
    Slide.imageText(title: 'Imagen'),
    Slide.conceptGrid(
      title: '',
      concepts: [
        SlideConcept(title: 'a'),
        SlideConcept(title: 'b'),
      ],
    ),
    Slide.closing(title: 'Fin'),
  ],
);
