import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';

/// Las notas escritas para la biblioteca de ejemplo: de bloques, sobre los
/// mismos temas que lo que se baja, y enlazadas entre ellas con `[[ ]]`.
///
/// Casi todos los enlaces apuntan a otra nota de esta lista, así que
/// resuelven apenas se guardan las dos y arman un grafo de verdad. Unos
/// pocos apuntan a lo que se baja —el manuscrito de la Regla, el cuadro de
/// la Declaración de 1789— con el título con que se guarda; y dos a propósito
/// a notas que no existen (`La alegoría de la caverna`, `Carlomagno y el
/// renacimiento carolingio`), para que haya algo en «Enlaces rotos» y se
/// pueda probar crear la nota desde ahí.
const sampleLibraryNotes = <SampleNote>[
  SampleNote(
    id: 'nota-padres-de-la-iglesia',
    title: 'Mapa: Padres de la Iglesia',
    why: 'Nota índice con muchos enlaces: el grafo, los vínculos y el Atlas.',
    blocks: [
      ContentBlock.heading(text: 'Padres de la Iglesia'),
      ContentBlock.paragraph(
        text:
            'Los escritores cristianos de los primeros siglos cuya doctrina '
            'y santidad la Iglesia reconoce como testimonio de la fe. Se '
            'suelen dividir en griegos y latinos.',
      ),
      ContentBlock.heading(text: 'Latinos', level: 2),
      ContentBlock.bulletItem(
        text:
            'Agustín de Hipona (354–430): Confesiones, La ciudad de Dios. '
            'Ver [[La fe y la razón]].',
      ),
      ContentBlock.bulletItem(
        text: 'Jerónimo (c. 347–420): tradujo la Biblia al latín, la Vulgata.',
      ),
      ContentBlock.bulletItem(
        text: 'Ambrosio de Milán (c. 340–397): bautizó a Agustín.',
      ),
      ContentBlock.heading(text: 'Griegos', level: 2),
      ContentBlock.bulletItem(
        text:
            'Atanasio de Alejandría (c. 296–373): defendió en Nicea la '
            'divinidad del Hijo. Ver [[El Concilio de Nicea en una página]].',
      ),
      ContentBlock.bulletItem(
        text:
            'Basilio, Gregorio de Nisa y Gregorio Nacianceno: los Padres '
            'capadocios.',
      ),
      ContentBlock.heading(text: 'Después', level: 2),
      ContentBlock.paragraph(
        text:
            'La vida monástica de Occidente sigue en [[Benito y la regla '
            'monástica]], y la síntesis medieval de fe y filosofía en '
            '[[Las cinco vías]].',
      ),
    ],
  ),
  SampleNote(
    id: 'nota-concilio-de-nicea',
    title: 'El Concilio de Nicea en una página',
    why: 'Nota corta con fechas: la línea de tiempo y las tarjetas de repaso.',
    blocks: [
      ContentBlock.heading(text: 'Nicea, 325'),
      ContentBlock.paragraph(
        text:
            'Primer concilio ecuménico, convocado por el emperador '
            'Constantino. Unos trescientos obispos se reunieron en Nicea, '
            'en Bitinia.',
      ),
      ContentBlock.heading(text: 'Qué resolvió', level: 2),
      ContentBlock.numberedItem(
        text:
            'Contra Arrio, que el Hijo es «consustancial» (homoousios) al '
            'Padre.',
      ),
      ContentBlock.numberedItem(
        text: 'La primera forma del Credo, completada en Constantinopla (381).',
      ),
      ContentBlock.numberedItem(
        text: 'Un criterio común para fijar la fecha de la Pascua.',
      ),
      ContentBlock.quote(
        text:
            'Creemos en un solo Dios, Padre todopoderoso, creador de todas '
            'las cosas visibles e invisibles.',
      ),
      ContentBlock.paragraph(
        text:
            'Contexto: [[Mapa: Padres de la Iglesia]] y [[De Roma a la Edad '
            'Media]].',
      ),
    ],
  ),
  SampleNote(
    id: 'nota-fe-y-razon',
    title: 'La fe y la razón',
    why: 'Nota con cita y enlaces cruzados: vínculos, chat con la bóveda.',
    blocks: [
      ContentBlock.quote(
        text:
            'La fe y la razón son como las dos alas con las cuales el '
            'espíritu humano se eleva hacia la contemplación de la verdad.',
      ),
      ContentBlock.paragraph(
        text:
            'Así empieza la encíclica Fides et ratio de Juan Pablo II '
            '(1998). La idea tiene una historia larga: Agustín decía «cree '
            'para entender, entiende para creer», y Tomás de Aquino mostró '
            'que la filosofía de Aristóteles podía servir a la teología sin '
            'confundirse con ella.',
      ),
      ContentBlock.heading(text: 'Para seguir', level: 2),
      ContentBlock.bulletItem(text: '[[Las cinco vías]]'),
      ContentBlock.bulletItem(text: '[[Aristóteles y el motor inmóvil]]'),
      ContentBlock.bulletItem(text: '[[Mapa: Padres de la Iglesia]]'),
    ],
  ),
  SampleNote(
    id: 'nota-cinco-vias',
    title: 'Las cinco vías',
    why: 'Lista numerada para estudiar: tarjetas, quiz y lectura en voz alta.',
    blocks: [
      ContentBlock.paragraph(
        text:
            'En la Suma teológica (I, q. 2, a. 3), Tomás de Aquino propone '
            'cinco caminos para mostrar que Dios existe, todos a partir de '
            'lo que se ve en el mundo.',
      ),
      ContentBlock.numberedItem(
        text: 'Por el movimiento: hace falta un primer motor inmóvil.',
      ),
      ContentBlock.numberedItem(
        text: 'Por la causa eficiente: hace falta una primera causa.',
      ),
      ContentBlock.numberedItem(
        text:
            'Por lo contingente y lo necesario: hace falta un ser necesario '
            'por sí mismo.',
      ),
      ContentBlock.numberedItem(
        text: 'Por los grados de perfección: hace falta un máximo.',
      ),
      ContentBlock.numberedItem(
        text:
            'Por el gobierno del mundo: lo que no tiene inteligencia obra '
            'hacia un fin, y alguien lo ordena.',
      ),
      ContentBlock.paragraph(
        text:
            'La primera vía viene de [[Aristóteles y el motor inmóvil]]. '
            'Contexto en [[La fe y la razón]].',
      ),
    ],
  ),
  SampleNote(
    id: 'nota-motor-inmovil',
    title: 'Aristóteles y el motor inmóvil',
    why: 'Puente entre filosofía antigua y medieval: relaciones sugeridas.',
    blocks: [
      ContentBlock.paragraph(
        text:
            'En la Física (libro VIII) y la Metafísica (libro XII), '
            'Aristóteles razona que todo lo que se mueve es movido por '
            'otro, y que la serie no puede ir al infinito: tiene que haber '
            'un primer motor que mueve sin ser movido.',
      ),
      ContentBlock.quote(
        text: 'Mueve como lo amado mueve al amante. (Metafísica XII, 7)',
      ),
      ContentBlock.paragraph(
        text:
            'Tomás lo retoma en la primera de [[Las cinco vías]]. Para el '
            'camino que va de Sócrates a Aristóteles, ver [[Sócrates, '
            'Platón y Aristóteles]].',
      ),
    ],
  ),
  SampleNote(
    id: 'nota-socrates-platon-aristoteles',
    title: 'Sócrates, Platón y Aristóteles',
    why: 'Tabla mental de tres filósofos y un enlace roto a propósito.',
    blocks: [
      ContentBlock.heading(text: 'Maestro, discípulo y discípulo'),
      ContentBlock.bulletItem(
        text:
            'Sócrates (470–399 a. C.): no escribió nada; pregunta hasta que '
            'el otro descubre que no sabe. Condenado a beber cicuta.',
      ),
      ContentBlock.bulletItem(
        text:
            'Platón (c. 427–347 a. C.): las Ideas, la Academia, los '
            'diálogos. Ver [[La alegoría de la caverna]].',
      ),
      ContentBlock.bulletItem(
        text:
            'Aristóteles (384–322 a. C.): el Liceo, la lógica, la ética de '
            'la virtud. Ver [[Aristóteles y el motor inmóvil]].',
      ),
      ContentBlock.quote(
        text: 'Una vida sin examen no merece ser vivida. (Apología, 38a)',
      ),
    ],
  ),
  SampleNote(
    id: 'nota-benito-regla',
    title: 'Benito y la regla monástica',
    why: 'Nota con casilleros: la vista de lectura y los bloques marcables.',
    blocks: [
      ContentBlock.paragraph(
        text:
            'Benito de Nursia (c. 480–547) fundó Montecassino y escribió una '
            'Regla breve y equilibrada que organizó la vida monástica de '
            'Occidente: oración, trabajo y lectura, bajo un abad.',
      ),
      ContentBlock.quote(text: 'Ora et labora.'),
      ContentBlock.paragraph(
        text:
            'El manuscrito más antiguo que se conserva está en la biblioteca '
            'de San Galo: ver [[Regla de san Benito, manuscrito de San '
            'Galo]].',
      ),
      ContentBlock.checklistItem(text: 'Leer el prólogo de la Regla'),
      ContentBlock.checklistItem(
        text: 'Leer los capítulos 4 a 7',
        checked: true,
      ),
      ContentBlock.checklistItem(text: 'Comparar con la vida de Francisco'),
      ContentBlock.paragraph(
        text:
            'Los monasterios fueron la memoria de [[Edad Media: lo que no es '
            'oscuro]].',
      ),
    ],
  ),
  SampleNote(
    id: 'nota-edad-media',
    title: 'Edad Media: lo que no es oscuro',
    why: 'Nota de historia con enlaces a otras y uno roto a propósito.',
    blocks: [
      ContentBlock.paragraph(
        text:
            'Mil años, del 476 a 1453 o 1492 según quién cuente. Lo que '
            'dejó: las universidades, el canto gregoriano, las catedrales, '
            'la escolástica.',
      ),
      ContentBlock.bulletItem(text: '[[De Roma a la Edad Media]]'),
      ContentBlock.bulletItem(text: '[[Benito y la regla monástica]]'),
      ContentBlock.bulletItem(
        text: '[[Carlomagno y el renacimiento carolingio]]',
      ),
      ContentBlock.bulletItem(text: '[[Las cinco vías]]'),
    ],
  ),
  SampleNote(
    id: 'nota-roma-a-edad-media',
    title: 'De Roma a la Edad Media',
    why: 'Nota con fechas: la línea de tiempo y las relaciones entre temas.',
    blocks: [
      ContentBlock.numberedItem(
        text: '27 a. C.: Octavio recibe el título de Augusto.',
      ),
      ContentBlock.numberedItem(
        text: '313: Edicto de Milán, libertad de culto para los cristianos.',
      ),
      ContentBlock.numberedItem(
        text: '325: [[El Concilio de Nicea en una página]].',
      ),
      ContentBlock.numberedItem(
        text: '380: Edicto de Tesalónica, el cristianismo religión oficial.',
      ),
      ContentBlock.numberedItem(
        text: '476: Odoacro depone a Rómulo Augústulo.',
      ),
      ContentBlock.paragraph(
        text: 'Lo que sigue: [[Edad Media: lo que no es oscuro]].',
      ),
    ],
  ),
  SampleNote(
    id: 'nota-revolucion-francesa',
    title: '1789: la Revolución francesa en cinco fechas',
    why: 'Fechas para repasar: tarjetas, quiz y línea de tiempo.',
    blocks: [
      ContentBlock.numberedItem(
        text: '5 de mayo de 1789: se reúnen los Estados Generales.',
      ),
      ContentBlock.numberedItem(
        text: '14 de julio de 1789: toma de la Bastilla.',
      ),
      ContentBlock.numberedItem(
        text:
            '26 de agosto de 1789: Declaración de los Derechos del Hombre y '
            'del Ciudadano.',
      ),
      ContentBlock.numberedItem(
        text: '21 de enero de 1793: ejecución de Luis XVI.',
      ),
      ContentBlock.numberedItem(
        text: '9 de noviembre de 1799: golpe del 18 de brumario, Napoleón.',
      ),
      ContentBlock.paragraph(
        text:
            'La Declaración impresa de 1789 está entre lo cargado: ver '
            '[[Declaración de los Derechos del Hombre, 1789]].',
      ),
    ],
  ),
  SampleNote(
    id: 'nota-fotosintesis',
    title: 'Fotosíntesis y respiración',
    why: 'Ciencia con una ecuación: búsqueda y explicación con la IA.',
    blocks: [
      ContentBlock.paragraph(
        text:
            'La fotosíntesis guarda la energía de la luz en azúcar; la '
            'respiración celular la libera. Una es casi la inversa de la '
            'otra.',
      ),
      ContentBlock.quote(text: '6 CO₂ + 6 H₂O + luz → C₆H₁₂O₆ + 6 O₂'),
      ContentBlock.bulletItem(
        text: 'Fase luminosa: en los tilacoides; rompe el agua y libera O₂.',
      ),
      ContentBlock.bulletItem(
        text: 'Ciclo de Calvin: en el estroma; fija el CO₂ en azúcar.',
      ),
      ContentBlock.paragraph(text: 'Preguntas en [[Preguntas para repasar]].'),
    ],
  ),
  SampleNote(
    id: 'nota-preguntas',
    title: 'Preguntas para repasar',
    why: 'Casilleros con preguntas sueltas: el hábito y el repaso.',
    blocks: [
      ContentBlock.heading(text: 'Para la semana'),
      ContentBlock.checklistItem(
        text:
            '¿Qué resolvió Nicea contra Arrio? [[El Concilio de Nicea en '
            'una página]]',
      ),
      ContentBlock.checklistItem(
        text:
            '¿Cuál de las cinco vías viene de Aristóteles? [[Las cinco vías]]',
      ),
      ContentBlock.checklistItem(
        text:
            '¿Dónde ocurre el ciclo de Calvin? [[Fotosíntesis y respiración]]',
      ),
      ContentBlock.checklistItem(
        text:
            '¿Qué pasó el 14 de julio de 1789? [[1789: la Revolución '
            'francesa en cinco fechas]]',
        checked: true,
      ),
      ContentBlock.checklistItem(
        text:
            '¿Qué quiere decir «ora et labora»? '
            '[[Benito y la regla monástica]]',
      ),
    ],
  ),
];
