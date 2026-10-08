import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/domain/sample_library_notes.dart';

/// La biblioteca de ejemplo: recursos reales, públicos y de uso libre, para
/// llenar la bóveda de una flavor de desarrollo y recorrer toda la app sin
/// cargar nada a mano.
///
/// Los temas son los que el usuario ya guarda —espiritualidad católica,
/// historia, filosofía y ciencia— y los tipos, todos los que la app sabe
/// leer: páginas, videos cortos y de horas, PDF, libros EPUB, texto, audios
/// para transcribir, imágenes para reconocer el texto y notas enlazadas.
///
/// Cada dirección se comprobó a mano antes de ponerla acá (2026-10-03): que
/// exista, que responda con el User-Agent de la app y que sea lo que dice
/// —un PDF que empieza con `%PDF-`, un audio con su firma—; cada video, con
/// el oEmbed de YouTube, con el título y el canal que figuran. Los tamaños
/// son los que informó el servidor; los de las páginas y los videos son una
/// estimación: lo que pesa el HTML, y el audio a unos 1,2 MB por minuto.
///
/// El orden es el de carga, y va por tandas: primero lo liviano —páginas y
/// videos cortos—, para que la biblioteca tenga algo que mirar enseguida, y
/// lo pesado después. Las notas al final, cuando ya existe casi todo lo que
/// enlazan.
///
/// Un `id` no se cambia ni se reusa nunca: es lo que se recuerda para no
/// cargar dos veces lo mismo.
const sampleLibrary = <SampleResource>[
  ..._webArticles,
  ..._shortVideos,
  ..._files,
  ..._longVideos,
  ...sampleLibraryNotes,
];

/// Lo que un video baja de audio, aproximado, por minuto: la pista de solo
/// audio de mayor calidad que ofrece YouTube ronda los 160 kbps.
const _audioBytesPerMinute = 1200 * 1024;

const _kb = 1024;

/// Cuánto pesa cada artículo incluye lo que «Bajar todo» (F30) baja de él: sus
/// fotos, los archivos que enlaza y los audios que trae, medidos el 08/10/2026
/// con pedidos HEAD sobre los artículos reales. Casi todo son PDF: el del
/// Imperio romano trae 237 MB y el de Sócrates 152. Cambia con la página.
const _webArticles = <SampleLink>[
  SampleLink(
    id: 'web-imperio-romano',
    title: 'Imperio romano (Wikipedia)',
    why: 'Artículo muy largo: modo lectura, índice y búsqueda en el texto.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Imperio_romano',
    approxBytes: 244800 * _kb,
  ),
  SampleLink(
    id: 'web-agustin-de-hipona',
    title: 'Agustín de Hipona (Wikipedia)',
    why: 'Padre de la Iglesia: relaciones con las notas y con el video.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Agust%C3%ADn_de_Hipona',
    approxBytes: 3844 * _kb,
  ),
  SampleLink(
    id: 'web-tomas-de-aquino',
    title: 'Tomás de Aquino (Wikipedia)',
    why: 'Mismo tema en español y en inglés (SEP): posibles duplicados.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Tom%C3%A1s_de_Aquino',
    approxBytes: 10496 * _kb,
  ),
  SampleLink(
    id: 'web-socrates',
    title: 'Sócrates (Wikipedia)',
    why: 'Artículo mediano de filosofía: resumen y tarjetas de repaso.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/S%C3%B3crates',
    approxBytes: 156140 * _kb,
  ),
  SampleLink(
    id: 'web-revolucion-francesa',
    title: 'Revolución francesa (Wikipedia)',
    why: 'Muchas fechas: la línea de tiempo y el quiz.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Revoluci%C3%B3n_francesa',
    approxBytes: 21502 * _kb,
  ),
  SampleLink(
    id: 'web-fotosintesis',
    title: 'Fotosíntesis (Wikipedia)',
    why: 'Ciencia con fórmulas e imágenes: el archivado de la página.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Fotos%C3%ADntesis',
    approxBytes: 1891 * _kb,
  ),
  SampleLink(
    id: 'web-agujero-negro',
    title: 'Agujero negro (Wikipedia)',
    why: 'Astronomía: relaciones con los videos de agujeros negros.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Agujero_negro',
    approxBytes: 1461 * _kb,
  ),
  SampleLink(
    id: 'web-concilio-de-nicea',
    title: 'Concilio de Nicea I (Wikipedia)',
    why: 'Mismo tema que una nota de ejemplo: sugerencias de vínculos.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Primer_Concilio_de_Nicea',
    approxBytes: 625 * _kb,
  ),
  SampleLink(
    id: 'web-benito-de-nursia',
    title: 'Benito de Nursia (Wikipedia)',
    why: 'Santo: lo relaciona con la nota y el manuscrito de la Regla.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Benito_de_Nursia',
    approxBytes: 3777 * _kb,
  ),
  SampleLink(
    id: 'web-edad-media',
    title: 'Edad Media (Wikipedia)',
    why: 'Artículo largo de historia: la IA que organiza por temas.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Edad_Media',
    approxBytes: 8947 * _kb,
  ),
  SampleLink(
    id: 'web-platon',
    title: 'Platón (Wikipedia)',
    why: 'Filosofía: el mapa de temas junto a Sócrates y Aristóteles.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Plat%C3%B3n',
    approxBytes: 19057 * _kb,
  ),
  SampleLink(
    id: 'web-aristoteles',
    title: 'Aristóteles (Wikipedia)',
    why: 'Uno de los artículos más largos: fragmentado y chat con fuentes.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Arist%C3%B3teles',
    approxBytes: 21713 * _kb,
  ),
  SampleLink(
    id: 'web-francisco-de-asis',
    title: 'Francisco de Asís (Wikipedia)',
    why: 'Santo con video propio: relaciones entre tipos distintos.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Francisco_de_As%C3%ADs',
    approxBytes: 3869 * _kb,
  ),
  SampleLink(
    id: 'web-teresa-de-jesus',
    title: 'Teresa de Jesús (Wikipedia)',
    why: 'Santa y escritora: citas y referencias bibliográficas.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Teresa_de_Jes%C3%BAs',
    approxBytes: 4447 * _kb,
  ),
  SampleLink(
    id: 'web-padres-de-la-iglesia',
    title: 'Padres de la Iglesia (Wikipedia)',
    why: 'Panorama: la nota mapa y el Atlas de temas.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Padres_de_la_Iglesia',
    approxBytes: 1237 * _kb,
  ),
  SampleLink(
    id: 'web-republica-romana',
    title: 'República romana (Wikipedia)',
    why: 'Historia de Roma junto al documental de dos horas.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Rep%C3%BAblica_romana',
    approxBytes: 46276 * _kb,
  ),
  SampleLink(
    id: 'web-carlomagno',
    title: 'Carlomagno (Wikipedia)',
    why: 'Puede completar el enlace roto de una nota de ejemplo.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Carlomagno',
    approxBytes: 2890 * _kb,
  ),
  SampleLink(
    id: 'web-toma-de-la-bastilla',
    title: 'Toma de la Bastilla (Wikipedia)',
    why: 'Artículo corto: procesamiento rápido y una fecha para repasar.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Toma_de_la_Bastilla',
    approxBytes: 2191 * _kb,
  ),
  SampleLink(
    id: 'web-sistema-solar',
    title: 'Sistema solar (Wikipedia)',
    why: 'Astronomía con tablas: cómo se ven en el modo lectura.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Sistema_solar',
    approxBytes: 4841 * _kb,
  ),
  SampleLink(
    id: 'web-evolucion-biologica',
    title: 'Evolución biológica (Wikipedia)',
    why: 'El más pesado de los artículos: archivado completo de la página.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Evoluci%C3%B3n_biol%C3%B3gica',
    approxBytes: 12252 * _kb,
  ),
  SampleLink(
    id: 'web-adn',
    title: 'Ácido desoxirribonucleico (Wikipedia)',
    why: 'Biología: relaciones con la teoría celular y la fotosíntesis.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/%C3%81cido_desoxirribonucleico',
    approxBytes: 6137 * _kb,
  ),
  SampleLink(
    id: 'web-jeronimo',
    title: 'Jerónimo (santo) (Wikipedia)',
    why: 'El traductor de la Vulgata: relaciones con la nota de los Padres.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Jer%C3%B3nimo_de_Estrid%C3%B3n',
    approxBytes: 4224 * _kb,
  ),
  SampleLink(
    id: 'web-escolastica',
    title: 'Escolástica (Wikipedia)',
    why: 'Filosofía medieval: el puente entre los temas de la IA.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Escol%C3%A1stica',
    approxBytes: 1524 * _kb,
  ),
  SampleLink(
    id: 'web-galileo',
    title: 'Galileo Galilei (Wikipedia)',
    why: 'Astronomía e historia a la vez: un elemento con dos temas.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Galileo_Galilei',
    approxBytes: 2705 * _kb,
  ),
  SampleLink(
    id: 'web-charles-darwin',
    title: 'Charles Darwin (Wikipedia)',
    why: 'Relaciones con la portada de El origen de las especies.',
    kind: SampleLinkKind.webArticle,
    url: 'https://es.wikipedia.org/wiki/Charles_Darwin',
    approxBytes: 3060 * _kb,
  ),
  SampleLink(
    id: 'web-allegory-of-the-cave',
    title: 'Allegory of the cave (Wikipedia, inglés)',
    why: 'En inglés: el idioma de la fuente, la traducción y el vocabulario.',
    kind: SampleLinkKind.webArticle,
    url: 'https://en.wikipedia.org/wiki/Allegory_of_the_cave',
    approxBytes: 802 * _kb,
  ),
  SampleLink(
    id: 'web-sep-aquinas',
    title: 'Thomas Aquinas (Stanford Encyclopedia of Philosophy)',
    why: 'Otro sitio que Wikipedia, en inglés: el lector y las citas.',
    kind: SampleLinkKind.webArticle,
    url: 'https://plato.stanford.edu/entries/aquinas/',
    approxBytes: 145 * _kb,
  ),
  SampleLink(
    id: 'web-fides-et-ratio',
    title: 'Fides et ratio (vatican.va)',
    why: 'Encíclica en la página del Vaticano: un sitio que no es Wikipedia.',
    kind: SampleLinkKind.webArticle,
    url:
        'https://www.vatican.va/content/john-paul-ii/es/encyclicals/'
        'documents/hf_jp-ii_enc_14091998_fides-et-ratio.html',
    approxBytes: 310 * _kb,
  ),
];

const _shortVideos = <SampleLink>[
  SampleLink(
    id: 'yt-caverna-platon',
    title: 'La alegoría de la caverna de Platón - Alex Gendler',
    why: 'Video corto con subtítulos: transcripción en un solo tramo.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=h3UJWsIfwsg',
    channel: 'Sé Curioso — TED-Ed',
    minutes: 5,
    approxBytes: 5 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-socrates-5-minutos',
    title:
        'Sócrates en 5 minutos (Animación) Mayéutica. Sofistas. Juicio. '
        'Critón ¿Por qué mataron a Sócrates?',
    why: 'Corto con subtítulos automáticos: resumen y tarjetas.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=YduLzweRXjk',
    channel: 'Filosofía en Minutos',
    minutes: 6,
    approxBytes: 6 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-tomas-de-aquino',
    title: 'El pensamiento de Santo Tomás de Aquino',
    why: 'Corto con dos pistas de audio (original y doblada).',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=kTIdZ6j9l7c',
    channel: 'unProfesor',
    minutes: 5,
    approxBytes: 5 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-teoria-celular',
    title: 'La extraña historia de la teoría celular - Lauren Royal-Woods',
    why: 'Biología en video: relaciones con el artículo del ADN.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=59N9Jfwv4vI',
    channel: 'Sé Curioso — TED-Ed',
    minutes: 6,
    approxBytes: 6 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-destruir-agujero-negro',
    title: '¿Se puede destruir un agujero negro? - Fabio Pacucci',
    why: 'Mismo tema que un artículo: relaciones entre video y página.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=cB15UY-mD18',
    channel: 'Sé Curioso — TED-Ed',
    minutes: 5,
    approxBytes: 5 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-causas-revolucion-francesa',
    title: '¿Qué causó la Revolución Francesa? - Tom Mullaney',
    why: 'Historia corta: citar un minuto del video.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=XygZjE5pkqA',
    channel: 'Sé Curioso — TED-Ed',
    minutes: 6,
    approxBytes: 6 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-reliquias-san-francisco',
    title: 'Las reliquias de San Francisco de Asís que han fascinado al mundo',
    why: 'Corto con cuatro pistas de audio: la bajada elige la original.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=Ex1dxYutVYw',
    channel: 'EWTNespanol',
    minutes: 6,
    approxBytes: 6 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-edad-media-10-minutos',
    title: 'Edad Media en 10 minutos',
    why: 'Diez minutos: el límite entre corto y mediano.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=DjdFLJT5lhY',
    channel: 'Academia Play',
    minutes: 11,
    approxBytes: 11 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-filosofia-aristoteles',
    title: 'La Filosofía de Aristóteles - Todos los conceptos fundamentales',
    why: 'El único sin subtítulos: transcripción desde el audio.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=K0Dn-_ZhmyM',
    channel: 'La Travesía',
    minutes: 18,
    approxBytes: 18 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-san-agustin-papa-leon',
    title: 'Descubriendo a San Agustín con el Papa León',
    why: 'Mediano, de un Padre de la Iglesia: relaciones con las notas.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=gH85IbV_bx0',
    channel: 'EWTNespanol',
    minutes: 27,
    approxBytes: 27 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-canon-nuevo-testamento',
    title: 'CANON del NUEVO TESTAMENTO: historia de su formación | BITE',
    why: 'Media hora sobre la Biblia: transcripción en pocas partes.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=g2QOdcYBWkw',
    channel: 'BITE',
    minutes: 28,
    approxBytes: 28 * _audioBytesPerMinute,
  ),
];

const _longVideos = <SampleLink>[
  SampleLink(
    id: 'yt-sofistas-juan-march',
    title:
        'Sofistas (I): Filosofía política y moral en la Grecia clásica | '
        'La March',
    why: 'Conferencia de una hora: el carril largo y retomar a medias.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=4l-KmPnh5Dk',
    channel: 'Fundación Juan March',
    minutes: 65,
    approxBytes: 65 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-universo-invisible',
    title:
        'El 85% del universo es invisible y no sabemos qué es | Doctor '
        'Fisión, divulgador científico.',
    why: 'Una hora con varias pistas de audio: carril largo y bajada.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=9077zQqT300',
    channel: 'AprendemosJuntos',
    minutes: 62,
    approxBytes: 62 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-antigua-roma-documental',
    title:
        'ANTIGUA ROMA - Toda su Historia - Monarquía, República Romana e '
        'Imperio Romano (Documental)',
    why: 'Más de dos horas: la bajada de audio pesada y muchas partes.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=UtTMIPSc7kE',
    channel: 'Pero eso es otra Historia',
    minutes: 135,
    approxBytes: 135 * _audioBytesPerMinute,
  ),
  SampleLink(
    id: 'yt-edelstein-universo',
    title:
        'Historias asombrosas sobre la ciencia y el universo | José '
        'Edelstein, físico',
    why: 'Dos horas de charla: el servicio en primer plano un rato largo.',
    kind: SampleLinkKind.youtubeVideo,
    url: 'https://www.youtube.com/watch?v=L08-xy6cyYY',
    channel: 'AprendemosJuntos',
    minutes: 124,
    approxBytes: 124 * _audioBytesPerMinute,
  ),
];

/// Los archivos van intercalados por tipo —un PDF, una imagen, un audio…—
/// para que cada tanda pruebe un poco de todo y ninguna sea solo de lo
/// pesado.
const _files = <SampleFile>[
  SampleFile(
    id: 'img-portada-quijote-1605',
    title: 'Portada del Quijote, primera edición (1605)',
    why: 'Página impresa antigua: el reconocimiento de texto en imágenes.',
    kind: SampleFileKind.image,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/d/d8/'
        'El_ingenioso_hidalgo_don_Quijote_de_la_Mancha.jpg',
    fileName: 'portada_quijote_1605.jpg',
    approxBytes: 761623,
  ),
  SampleFile(
    id: 'pdf-ddhc-1789-es',
    title: 'Declaración de los Derechos del Hombre y del Ciudadano (1789)',
    why: 'PDF corto y en español: la lectura por páginas más simple.',
    kind: SampleFileKind.pdf,
    url:
        'https://www.conseil-constitutionnel.fr/sites/default/files/as/root/'
        'bank_mm/espagnol/es_ddhc.pdf',
    fileName: 'declaracion_derechos_1789.pdf',
    approxBytes: 26971,
  ),
  SampleFile(
    id: 'audio-imitacion-de-cristo-1',
    title: 'De la imitación de Cristo, capítulo 1 (LibriVox)',
    why: 'Audio de tres minutos: la transcripción más rápida.',
    kind: SampleFileKind.audio,
    url:
        'https://archive.org/download/de_la_imitacion_de_cristo_2109_librivox/'
        'imitaciondecristo_001_dekempis_64kb.mp3',
    fileName: 'imitacion_de_cristo_01.mp3',
    approxBytes: 1621513,
  ),
  SampleFile(
    id: 'txt-lazarillo',
    title: 'Lazarillo de Tormes (texto plano)',
    why: 'El mismo libro que un EPUB de la lista: posibles duplicados.',
    kind: SampleFileKind.text,
    url: 'https://www.gutenberg.org/ebooks/320.txt.utf-8',
    fileName: 'lazarillo_de_tormes.txt',
    approxBytes: 131215,
  ),
  SampleFile(
    id: 'img-regla-benito-san-galo',
    title: 'Regla de san Benito, manuscrito de San Galo',
    why:
        'Manuscrito medieval: reconocimiento de texto difícil. Lo enlaza '
        'una nota.',
    kind: SampleFileKind.image,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/1/14/'
        'Stiftsbibliothek_St._Gallen._Cod._Sang._914._S._13.jpg',
    fileName: 'regla_benito_cod_sang_914.jpg',
    approxBytes: 245984,
  ),
  SampleFile(
    id: 'epub-lazarillo',
    title: 'Lazarillo de Tormes (EPUB)',
    why: 'Libro corto en EPUB: capítulos, lectura y progreso.',
    kind: SampleFileKind.epub,
    url: 'https://www.gutenberg.org/ebooks/320.epub3.images',
    fileName: 'lazarillo_de_tormes.epub',
    approxBytes: 148874,
  ),
  SampleFile(
    id: 'audio-evangelio-juan-1',
    title: 'Evangelio según san Juan, capítulo 1 (LibriVox)',
    why: 'Audio de la Biblia: transcripción y citas con su minuto.',
    kind: SampleFileKind.audio,
    url:
        'https://archive.org/download/san_juan_0808_librivox/'
        'sanjuan_01_reina-valera_64kb.mp3',
    fileName: 'evangelio_san_juan_01.mp3',
    approxBytes: 3535016,
  ),
  SampleFile(
    id: 'pdf-origin-of-life',
    title: 'Milestones at the Origin of Life (arXiv)',
    why: 'Artículo científico en inglés: el idioma y las referencias.',
    kind: SampleFileKind.pdf,
    url: 'https://arxiv.org/pdf/2412.14754',
    fileName: 'milestones_origin_of_life.pdf',
    approxBytes: 335265,
  ),
  SampleFile(
    id: 'img-declaracion-1789',
    title: 'Declaración de los Derechos del Hombre, 1789',
    why:
        'Cuadro con el texto de la Declaración: OCR en francés. Lo enlaza '
        'una nota.',
    kind: SampleFileKind.image,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6c/'
        'Declaration_of_the_Rights_of_Man_and_of_the_Citizen_in_1789.jpg/'
        '1280px-Declaration_of_the_Rights_of_Man_and_of_the_Citizen_in_'
        '1789.jpg',
    fileName: 'declaracion_derechos_1789.jpg',
    approxBytes: 787200,
  ),
  SampleFile(
    id: 'audio-romancero-cid-1',
    title: 'Romancero selecto del Cid, parte 1 (LibriVox)',
    why: 'Poesía medieval leída: la transcripción con verso.',
    kind: SampleFileKind.audio,
    url:
        'https://archive.org/download/romancero_selecto_del_cid_1906_librivox/'
        'romancero_01_anonimo_64kb.mp3',
    fileName: 'romancero_cid_01.mp3',
    approxBytes: 3657148,
  ),
  SampleFile(
    id: 'txt-romancero-cid',
    title: 'Romancero selecto del Cid (texto plano)',
    why: 'El texto del mismo audio: relaciones entre un audio y su texto.',
    kind: SampleFileKind.text,
    url: 'https://www.gutenberg.org/ebooks/57648.txt.utf-8',
    fileName: 'romancero_selecto_del_cid.txt',
    approxBytes: 249987,
  ),
  SampleFile(
    id: 'pdf-ligo-gw150914',
    title:
        'Observation of Gravitational Waves from a Binary Black Hole '
        'Merger (arXiv)',
    why: 'Física con fórmulas: cómo se extrae un PDF a dos columnas.',
    kind: SampleFileKind.pdf,
    url: 'https://arxiv.org/pdf/1602.03837',
    fileName: 'ligo_gw150914.pdf',
    approxBytes: 935476,
  ),
  SampleFile(
    id: 'img-sidereus-nuncius',
    title: 'Sidereus Nuncius de Galileo (1610)',
    why: 'Página impresa en latín con dibujos: OCR mezclado con imagen.',
    kind: SampleFileKind.image,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/7/77/'
        'Sidereus_Nuncius_1610.Galileo.jpg',
    fileName: 'sidereus_nuncius_1610.jpg',
    approxBytes: 450285,
  ),
  SampleFile(
    id: 'audio-herschel-wikipedia-hablada',
    title: 'Carolina Herschel (Wikipedia hablada)',
    why: 'Audio OGG, no mp3: el otro formato de audio.',
    kind: SampleFileKind.audio,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/8/83/'
        'Es-Carolina_Herschel-article_%281%29.ogg',
    fileName: 'carolina_herschel_wikipedia_hablada.ogg',
    approxBytes: 3606362,
  ),
  SampleFile(
    id: 'epub-herodoto-historia-1',
    title: 'Los nueve libros de la Historia, de Heródoto (1 de 2)',
    why: 'Libro de historia antigua: relaciones con el audio de Heródoto.',
    kind: SampleFileKind.epub,
    url: 'https://www.gutenberg.org/ebooks/72753.epub3.images',
    fileName: 'herodoto_historia_1.epub',
    approxBytes: 557816,
  ),
  SampleFile(
    id: 'img-origen-de-las-especies',
    title: 'Portada de El origen de las especies (1859)',
    why: 'Portada en inglés, nítida: el OCR que debería salir perfecto.',
    kind: SampleFileKind.image,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/c/cd/'
        'Origin_of_Species_title_page.jpg/1280px-Origin_of_Species_title_'
        'page.jpg',
    fileName: 'origin_of_species_1859.jpg',
    approxBytes: 449068,
  ),
  SampleFile(
    id: 'audio-herodoto-1',
    title: 'Historia de Heródoto, libro I, parte 1 (LibriVox)',
    why: 'Quince minutos: transcripción por tramos.',
    kind: SampleFileKind.audio,
    url:
        'https://archive.org/download/historia_herodoto_i_1109_librivox/'
        'historia_01_herodoto_64kb.mp3',
    fileName: 'herodoto_libro_1_01.mp3',
    approxBytes: 7225475,
  ),
  SampleFile(
    id: 'pdf-laudato-si',
    title: "Laudato si' (encíclica, vatican.va)",
    why: 'PDF largo en español: lectura por páginas y búsqueda.',
    kind: SampleFileKind.pdf,
    url:
        'https://www.vatican.va/content/dam/francesco/pdf/encyclicals/'
        'documents/papa-francesco_20150524_enciclica-laudato-si_sp.pdf',
    fileName: 'laudato_si.pdf',
    approxBytes: 2437889,
  ),
  SampleFile(
    id: 'img-suma-teologica-basilea',
    title: 'Suma teológica, manuscrito de Basilea (f. 53r)',
    why: 'Manuscrito en latín con abreviaturas: el OCR en su peor caso.',
    kind: SampleFileKind.image,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/thumb/9/97/'
        'Basel%2C_Universit%C3%A4tsbibliothek%2C_A_I_14%2C_f._53r_%E2%80%93_'
        'Thomas_Aquinas%2C_Summa_theologiae_%28prima_pars.JPG/1280px-Basel'
        '%2C_Universit%C3%A4tsbibliothek%2C_A_I_14%2C_f._53r_%E2%80%93_'
        'Thomas_Aquinas%2C_Summa_theologiae_%28prima_pars.JPG',
    fileName: 'suma_teologica_basilea_f53r.jpg',
    approxBytes: 621184,
  ),
  SampleFile(
    id: 'audio-monacato-femenino',
    title: 'Monacato femenino, parte 1 (Wikipedia hablada)',
    why: 'Audio de 18 minutos en OGG: transcripción por tramos.',
    kind: SampleFileKind.audio,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/2/2b/'
        'Monacato_femenino_1_article%2C_Wikipedia_espa%C3%B1ol.oga',
    fileName: 'monacato_femenino_1.oga',
    approxBytes: 10059531,
  ),
  SampleFile(
    id: 'pdf-santa-teresa-poema',
    title: 'Santa Teresa de Jesús: poema (escaneo, 102 páginas)',
    why: 'PDF escaneado sin texto: el reconocimiento de páginas.',
    kind: SampleFileKind.pdf,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/3/3d/'
        'Santa_Teresa_de_Jes%C3%BAs_-_poema_%28IA_A11404202%29.pdf',
    fileName: 'santa_teresa_poema.pdf',
    approxBytes: 2718481,
  ),
  SampleFile(
    id: 'audio-pasion-introduccion',
    title: 'Historia de la Sagrada Pasión, introducción (LibriVox)',
    why: 'Audio de 26 minutos: el carril largo de la transcripción.',
    kind: SampleFileKind.audio,
    url:
        'https://archive.org/download/historia_pasion_v1_1211/'
        'pasion_00_palma_64kb.mp3',
    fileName: 'sagrada_pasion_00.mp3',
    approxBytes: 12409856,
  ),
  SampleFile(
    id: 'epub-quijote',
    title: 'Don Quijote de la Mancha (EPUB completo)',
    why: 'Libro larguísimo: el EPUB por partes y la memoria del teléfono.',
    kind: SampleFileKind.epub,
    url: 'https://www.gutenberg.org/ebooks/2000.epub3.images',
    fileName: 'don_quijote.epub',
    approxBytes: 920553,
  ),
  SampleFile(
    id: 'pdf-nociones-historia-grecia',
    title: 'Nociones de historia de Grecia (escaneo, 184 páginas)',
    why: 'El PDF más pesado: escaneo largo, retomable si se corta.',
    kind: SampleFileKind.pdf,
    url:
        'https://upload.wikimedia.org/wikipedia/commons/e/e8/'
        'Nociones_de_historia_de_Grecia_%28IA_nocionesdehistor00fyff_0%29.pdf',
    fileName: 'nociones_historia_grecia.pdf',
    approxBytes: 9996101,
  ),
  SampleFile(
    id: 'audio-apologia-socrates-1',
    title: 'Apología de Sócrates, parte 1 (LibriVox)',
    why: 'Audio de 46 minutos: la transcripción larga y retomable.',
    kind: SampleFileKind.audio,
    url:
        'https://archive.org/download/apologiadesocrates_2511_librivox/'
        'apologiadesocrates_01_platon_64kb.mp3',
    fileName: 'apologia_de_socrates_01.mp3',
    approxBytes: 22108742,
  ),
];
