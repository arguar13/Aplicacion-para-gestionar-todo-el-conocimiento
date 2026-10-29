import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_json.dart';

const _s = InfographicLevel.supporting;
const _x = InfographicLevel.extra;

/// Una infografía como la que escribiría la IA sobre un documento procesado:
/// un bloque de cada tipo, con textos de largo común y los tres niveles. Con
/// esto nada debería cortarse con «…».
Infographic sampleInfographic({bool illustrations = false}) => Infographic(
  title: 'Éxodo: liberación y alianza',
  subtitle: 'Del Egipto de los faraones al pie del Sinaí',
  kicker: 'Estudio · Comentario de Alonso',
  illustrationPrompt: illustrations ? 'El mar abierto al amanecer' : null,
  takeaway: 'La libertad del Éxodo se completa en la alianza.',
  source: 'Comentario de Alonso al Éxodo',
  blocks: [
    InfographicBlock.stat(
      value: '40 años',
      label: 'de travesía por el desierto',
      detail: 'Una generación entera camina hasta la tierra prometida.',
      icon: 'hourglass',
      illustrationPrompt: illustrations ? 'Un camino en el desierto' : null,
    ),
    InfographicBlock.fact(
      title: 'La zarza que arde',
      detail: 'Moisés recibe el llamado y el nombre de Dios.',
      icon: 'fire',
      illustrationPrompt: illustrations ? 'Una zarza en llamas' : null,
    ),
    const InfographicBlock.step(
      title: 'Salida de Egipto',
      detail: 'Después de las diez plagas, el pueblo parte de noche.',
      icon: 'route',
    ),
    const InfographicBlock.comparison(
      title: 'Moisés y el faraón',
      left: InfographicSide(
        heading: 'Moisés',
        points: ['Duda y pide ayuda', 'Habla por su pueblo'],
        icon: 'person',
      ),
      right: InfographicSide(
        heading: 'Faraón',
        points: ['Endurece su corazón', 'Habla por su poder'],
        icon: 'government',
      ),
      conclusion: 'La fragilidad que escucha vence al poder.',
      level: _s,
    ),
    const InfographicBlock.event(
      date: 'Cap. 14',
      title: 'El paso del mar',
      detail: 'El pueblo cruza entre las aguas.',
      icon: 'water',
      level: _s,
    ),
    const InfographicBlock.concept(
      title: 'Alianza',
      detail: 'Un pacto que obliga a las dos partes.',
      icon: 'handshake',
      level: _s,
    ),
    const InfographicBlock.quote(
      quote: 'Deja ir a mi pueblo, para que me sirva en el desierto',
      author: 'Moisés ante el faraón',
      source: 'Éxodo 7, 16',
      level: _x,
    ),
    const InfographicBlock.chart(
      title: 'Capítulos por parte',
      chartKind: InfographicChartKind.bars,
      data: [
        InfographicDatum(label: 'Egipto', value: 15),
        InfographicDatum(label: 'Desierto', value: 3),
        InfographicDatum(label: 'Sinaí', value: 22),
      ],
      unit: 'cap.',
      level: _x,
    ),
  ],
);

/// Una cronología: cinco hitos y una cifra.
Infographic timelineInfographic() => const Infographic(
  title: 'Los hitos del Éxodo',
  subtitle: 'Del capítulo 1 al 20',
  blocks: [
    InfographicBlock.event(
      date: 'Cap. 1',
      title: 'Opresión',
      detail: 'Un rey nuevo que no conocía a José',
    ),
    InfographicBlock.event(
      date: 'Cap. 3',
      title: 'La zarza',
      detail: 'El llamado de Moisés',
    ),
    InfographicBlock.event(
      date: 'Cap. 12',
      title: 'Pascua',
      detail: 'La noche de la salida',
    ),
    InfographicBlock.event(
      date: 'Cap. 14',
      title: 'El mar',
      detail: 'El paso entre las aguas',
      level: _s,
    ),
    InfographicBlock.event(
      date: 'Cap. 20',
      title: 'Sinaí',
      detail: 'Los diez mandamientos',
      level: _s,
    ),
  ],
);

/// Un proceso de cuatro pasos.
Infographic processInfographic() => const Infographic(
  title: 'De la esclavitud a la alianza',
  blocks: [
    InfographicBlock.step(title: 'Opresión', detail: 'Trabajo forzado'),
    InfographicBlock.step(title: 'Llamado', detail: 'La zarza que arde'),
    InfographicBlock.step(title: 'Liberación', detail: 'El paso del mar'),
    InfographicBlock.step(title: 'Alianza', detail: 'La Ley en el Sinaí'),
  ],
);

/// Cifras y gráficos de los cuatro tipos.
Infographic dataInfographic() => const Infographic(
  title: 'El Éxodo en números',
  subtitle: 'Lo que dice el texto, contado',
  blocks: [
    InfographicBlock.stat(
      value: '600.000',
      label: 'hombres a pie',
      icon: 'groups',
    ),
    InfographicBlock.stat(value: '40 %', label: 'del libro en el Sinaí'),
    InfographicBlock.chart(
      title: 'Las plagas',
      chartKind: InfographicChartKind.pictogram,
      data: [InfographicDatum(label: 'plagas', value: 10)],
      total: 10,
    ),
    InfographicBlock.chart(
      title: 'Capítulos por parte',
      chartKind: InfographicChartKind.bars,
      data: [
        InfographicDatum(label: 'Egipto', value: 15),
        InfographicDatum(label: 'Desierto', value: 3),
        InfographicDatum(label: 'Sinaí', value: 22),
      ],
    ),
    InfographicBlock.chart(
      title: 'Leyes y relato',
      chartKind: InfographicChartKind.ring,
      data: [
        InfographicDatum(label: 'Relato', value: 55),
        InfographicDatum(label: 'Leyes', value: 45),
      ],
      unit: '%',
      level: _s,
    ),
    InfographicBlock.chart(
      title: 'Camino recorrido',
      chartKind: InfographicChartKind.progress,
      data: [InfographicDatum(label: 'Hasta el Sinaí', value: 3)],
      total: 40,
      unit: 'años',
      level: _s,
    ),
  ],
);

/// Conceptos sueltos, para el mapa y el radial.
Infographic conceptsInfographic() => const Infographic(
  title: 'Conceptos clave del Éxodo',
  blocks: [
    InfographicBlock.concept(
      title: 'Alianza',
      detail: 'Un pacto que obliga a las dos partes',
      icon: 'handshake',
    ),
    InfographicBlock.concept(
      title: 'Pascua',
      detail: 'La fiesta que recuerda la salida',
      icon: 'calendar',
    ),
    InfographicBlock.concept(
      title: 'Ley',
      detail: 'Las diez palabras del Sinaí',
      icon: 'gavel',
    ),
    InfographicBlock.concept(
      title: 'Desierto',
      detail: 'El lugar de la prueba',
      icon: 'landscape',
    ),
    InfographicBlock.concept(
      title: 'Libertad',
      detail: 'Salir para servir',
      icon: 'flag',
      level: _s,
    ),
  ],
);

/// El peor caso: cada campo en su tope y palabras largas. Puede cortarse con
/// «…», pero nunca desbordar.
Infographic longInfographic() {
  String words(int n) => List.generate(
    n,
    (i) => i.isEven ? 'interdisciplinariedad' : 'consideraciones',
  ).join(' ');
  String clip(String text, int limit) =>
      text.length <= limit ? text : text.substring(0, limit);
  final label = clip(words(12), InfographicLimits.label);
  final detail = clip(words(20), InfographicLimits.detail);
  final point = clip(words(10), InfographicLimits.point);
  return Infographic(
    title: clip(words(10), InfographicLimits.title),
    subtitle: clip(words(16), InfographicLimits.subtitle),
    kicker: clip(words(4), InfographicLimits.kicker),
    takeaway: clip(words(16), InfographicLimits.takeaway),
    source: clip(words(12), InfographicLimits.source),
    blocks: [
      InfographicBlock.stat(
        value: '3.000.000.000.000',
        label: label,
        detail: detail,
      ),
      InfographicBlock.fact(title: label, detail: detail),
      InfographicBlock.step(title: label, detail: detail),
      InfographicBlock.comparison(
        title: label,
        left: InfographicSide(heading: label, points: List.filled(5, point)),
        right: InfographicSide(heading: label, points: List.filled(5, point)),
        conclusion: detail,
      ),
      InfographicBlock.event(date: label, title: label, detail: detail),
      InfographicBlock.concept(title: label, detail: detail),
      InfographicBlock.quote(
        quote: clip(words(24), InfographicLimits.quote),
        author: clip(words(8), InfographicLimits.attribution),
        source: clip(words(8), InfographicLimits.attribution),
      ),
      InfographicBlock.chart(
        title: label,
        data: [
          for (var i = 0; i < InfographicLimits.data; i++)
            InfographicDatum(
              label: label,
              value: 1000000.0 * (i + 1),
              display: '${i + 1}.000.000',
            ),
        ],
        detail: detail,
      ),
      InfographicBlock.fact(title: label, detail: detail),
    ],
  );
}

/// Lo mínimo: un título y un bloque.
Infographic minimalInfographic() => const Infographic(
  title: 'Éxodo',
  blocks: [InfographicBlock.fact(title: 'Un pueblo sale de Egipto')],
);
