import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

/// Las voces neuronales que leen sin conexión (F47, paso 3, decisión B): las
/// de Piper y la de Kokoro que publica sherpa-onnx en su versión `tts-models`
/// de GitHub, para el motor que la app ya trae (`sherpa_onnx`, el de Whisper).
///
/// **Qué se puso y de dónde sale** (relevado el 30/10/2026):
///
/// - El **tamaño y la huella** de cada paquete, de la versión `tts-models`
///   (`api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/tts-models`): se
///   comprueban al bajarlo, como los de Whisper. Si sherpa-onnx vuelve a
///   subir un paquete, la huella deja de coincidir y la descarga falla en vez
///   de dejar un modelo distinto del verificado.
/// - De Piper, el modelo **original** de cada voz (`.onnx` de 32 bits), el que
///   documenta sherpa-onnx en la página de cada una. Hay también versiones
///   `-int8` y `-fp16`, más livianas, sin documentar ni medir: no se ofrecen
///   hasta probar en el teléfono que suenan igual.
/// - El **idioma, el acento y la calidad** de Piper, de su `voices.json`
///   (`rhasspy/piper-voices`); el **género**, solo donde el modelo lo dice: el
///   nombre del hablante («hfc_female», «northern_english_male») o el mapa de
///   hablantes («M», «F» en Sharvard). Las fichas de Piper no dicen el género
///   de los demás, y el nombre de pila no alcanza: queda sin poner.
/// - De Kokoro (v1.0, 82M, en 8 bits: el que corre en un teléfono), el
///   número de cada hablante (`sid`), de la tabla de sherpa-onnx
///   (`tts/pretrained_models/kokoro.html`, con `em_santa` en el 53); el género
///   y la nota, de `VOICES.md` de `hexgrad/Kokoro-82M`. Cómo pronuncia cada
///   idioma —el `lang` de espeak-ng, o el léxico en inglés— también de ahí.
/// - El **tono**, el **timbre**, el **estilo**, la **edad** y **para qué es
///   ideal** no los publica nadie: no se ponen. Lo dicen las voces que se
///   creen (paso 4b).
///
/// **Lo que se dejó afuera, y por qué:**
///
/// - Las voces «GLaDOS» y «glados_turret»: imitan a un personaje.
/// - De Kokoro, las de nota D o F —en Kokoro, las de menos de una hora de
///   entrenamiento— y todas las de chino, que tienen D; y las de japonés:
///   Kokoro las pronuncia con `misaki[ja]`, y sherpa-onnx con espeak-ng, que no
///   se pudo comprobar que alcance.
/// - Las voces «miro» y «dii», que no traen ficha que diga de dónde salen.
abstract final class OfflineVoiceCatalog {
  /// De donde se bajan los paquetes: la versión `tts-models` de sherpa-onnx.
  static const releaseBase =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

  /// Las muestras publicadas de Piper, una por hablante, en su idioma.
  static const _piperSamples =
      'https://k2-fsa.github.io/sherpa/onnx/tts/all/piper/mp3';

  /// Kokoro, una sola descarga para todas sus voces.
  static const kokoro = OfflineVoicePackage(
    id: 'kokoro-int8-multi-lang-v1_0',
    family: OfflineVoiceFamily.kokoro,
    bytes: 132353410,
    sha256: '72c347230107ef8a31098ec4d468a605244beef5f1ed00db97efa13518800653',
  );

  static const packages = <OfflineVoicePackage>[kokoro, ..._piperPackages];

  /// Todas las voces, en el orden de la lista: por idioma, y en cada uno
  /// primero las de Piper —un hablante por paquete, cada una con su acento—
  /// y después las de Kokoro.
  static final List<OfflineVoice> voices = List.unmodifiable([
    for (final (package, speaker, name, locale, gender, quality)
        in _piperVoices)
      OfflineVoice(
        package: _piperPackage(package),
        speakerId: speaker,
        name: name,
        locale: locale,
        gender: gender,
        quality: quality,
        sampleUrl: _piperSampleOf(package, speaker),
      ),
    for (final (speaker, name, locale, gender, quality) in _kokoroVoices)
      OfflineVoice(
        package: kokoro,
        speakerId: speaker,
        name: name,
        locale: locale,
        gender: gender,
        quality: quality,
        kokoroPhonemes: _kokoroPhonemesOf(locale),
      ),
  ]);

  static final Map<String, OfflineVoice> _byId = {
    for (final voice in voices) voice.id: voice,
  };

  /// La voz [id] del catálogo, o `null` si no está —una voz que se quitó del
  /// catálogo y había quedado elegida—.
  static OfflineVoice? byId(String id) => _byId[id];

  static OfflineVoicePackage _piperPackage(String id) =>
      _piperPackages.firstWhere((p) => p.id == id);

  /// `vits-piper-es_AR-daniela-high` → `…/mp3/es_AR/vits-piper-es_AR-daniela-high/0.mp3`.
  static String _piperSampleOf(String package, int speaker) {
    final locale = package.split('-')[2];
    return '$_piperSamples/$locale/$package/$speaker.mp3';
  }

  /// Cómo pronuncia Kokoro cada idioma: el inglés con su léxico —el de
  /// Estados Unidos o el británico—, el resto con la voz de espeak-ng que
  /// usa Kokoro para ese idioma (`VOICES.md`).
  static KokoroPhonemes _kokoroPhonemesOf(String locale) => switch (locale) {
    'en-US' => const KokoroPhonemes.lexicon('lexicon-us-en.txt'),
    'en-GB' => const KokoroPhonemes.lexicon('lexicon-gb-en.txt'),
    'es' => const KokoroPhonemes.espeak('es'),
    'fr-FR' => const KokoroPhonemes.espeak('fr-fr'),
    'it' => const KokoroPhonemes.espeak('it'),
    'pt-BR' => const KokoroPhonemes.espeak('pt-br'),
    'hi' => const KokoroPhonemes.espeak('hi'),
    _ => throw ArgumentError.value(locale, 'locale', 'sin pronunciación'),
  };

  static const _piperPackages = <OfflineVoicePackage>[
    OfflineVoicePackage.piper(
      'vits-piper-es_AR-daniela-high',
      115562134,
      '71cbf6b7f646ab74f3c51336151abef41e6c54467ac929ffdb19ed706a07dd7b',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-es_ES-davefx-medium',
      67184952,
      'a3f6beb54a9cb893279f72978a22f807a4d9fc9c7848157b524d5cc7b7f58b22',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-es_ES-sharvard-medium',
      80318184,
      'b30a7a83df0518f0ee1c7039506648cade99f1f9b498fc49ed2ced2e2536bb5a',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-es_ES-carlfm-x_low',
      26520563,
      '15585c5add2ab1915ce69e8c966c7c9fb0b6afb21f9b92f18110fda5a4787f99',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-es_MX-claude-high',
      67207890,
      'ec33fb689c248fe64810aab564cba97babf0f506672cfd404928d46e751a4721',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-es_MX-ald-medium',
      67196497,
      'c60cf7bc853eb01a875fba0756523fecf9d9f46c763b19785d223fc981fb4fb6',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-en_US-lessac-high',
      115545841,
      '8619d204c7005866fe4f420181dfa79622af6a6222389f0b0818d2af31e0db0e',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-en_US-ryan-high',
      115630708,
      '6a71edf4d308b9cb2eaeadc8d1f3c6bf96120ecb7fe52c29a2b6e139c59760ed',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-en_US-hfc_female-medium',
      67228166,
      '3fffdceb0c65bd9415a085d09c3cb88cc82f9d74a6ca453f8ce7fc5eaee81ff8',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-en_US-hfc_male-medium',
      67214049,
      '76388f84acfca8ba5c0ed1636a26ada14c598abd52e76f110d4756fe326fc5f2',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-en_GB-cori-high',
      115574061,
      '42922f07738fcde2e49eed4e959635692f73b933de35a6b7c1010162ff566292',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-en_GB-alba-medium',
      67212349,
      'fcd45962906933eec4431d3688f7d74aaac8713c87c6717f91fd3b23463aa1a1',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-en_GB-northern_english_male-medium',
      67210490,
      '2bb2c1e709f58c11f17c693b3b38f500e110e7f54f2651774ec48b8d41f12c55',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-pt_BR-faber-medium',
      67183065,
      '7add3f923ad6bc25ca8a192805fd1a64d1b3893e4611c4a9719545a825039a83',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-pt_BR-cadu-medium',
      67207562,
      'aba78157d4b89acc17ddef15a70f4b2474f4c189d4de6035002ac7fec9d5d303',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-pt_BR-jeff-medium',
      67207052,
      'da4c870fc7b20600c74261b3e1dd1c816da2ce063e18c46e1f2cd86dea88f3f0',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-pt_PT-tugao-medium',
      67195014,
      '6b4f0a7bfc957bef26d6ac0703a8fa1ba659c8ab2df8b294f20206551859070c',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-fr_FR-siwis-medium',
      67207459,
      '375909aa30842b3a4efa10b1beb1d761af792960ae6873b4d53889f96c66195b',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-fr_FR-tom-medium',
      67202955,
      '3d8258ef8466b5d5f2cc46c06e1415d3d01c9cbaeed8b6d5b3d152073672472c',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-fr_FR-upmc-medium',
      80422639,
      'e9830a331a16f6cc5ef3116a287065e015d3495c3f56b974889a266da7f89a7f',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-it_IT-paola-medium',
      67221173,
      '7541f75778afa164e44e34baaef63befad7698595df26a95ca944b63ef1a16b4',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-it_IT-riccardo-x_low',
      26496614,
      '8ad0791558ae2b3e96054fc5756ae3ae2f6457fb1765bc01f43bbab85e0a7021',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-de_DE-thorsten-high',
      115591546,
      'dd4ed1b0d42c30a1a4862fc2b243e8044d52b8889c9ff3d1e99e92028888bc4a',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-de_DE-eva_k-x_low',
      26521242,
      'daec8658456d8e5ec714972f2e5a71f8a84d58b974db396f4eaeace0df06455a',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-de_DE-kerstin-low',
      67107768,
      '4bfe121d5f690a3b87acecd7ae1e70b48f4589ce6ae9f45a1809e6eb19fad97b',
    ),
    OfflineVoicePackage.piper(
      'vits-piper-de_DE-ramona-low',
      67084795,
      '79f985c10f86c4d58205b519abc488aa65eb713d54665ff729880a02e2625a42',
    ),
  ];

  /// Las voces de Piper: el paquete, el hablante, el nombre, el acento, el
  /// género (si el modelo lo dice) y la calidad (`x_low` y `low` son baja).
  static const _piperVoices =
      <(String, int, String, String, VoiceGender?, VoiceQuality)>[
        (
          'vits-piper-es_AR-daniela-high',
          0,
          'Daniela',
          'es-AR',
          null,
          VoiceQuality.high,
        ),
        (
          'vits-piper-es_ES-davefx-medium',
          0,
          'Davefx',
          'es-ES',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-es_ES-sharvard-medium',
          1,
          'Sharvard F',
          'es-ES',
          VoiceGender.female,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-es_ES-sharvard-medium',
          0,
          'Sharvard M',
          'es-ES',
          VoiceGender.male,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-es_ES-carlfm-x_low',
          0,
          'Carlfm',
          'es-ES',
          null,
          VoiceQuality.low,
        ),
        (
          'vits-piper-es_MX-claude-high',
          0,
          'Claude',
          'es-MX',
          null,
          VoiceQuality.high,
        ),
        (
          'vits-piper-es_MX-ald-medium',
          0,
          'Ald',
          'es-MX',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-en_US-lessac-high',
          0,
          'Lessac',
          'en-US',
          null,
          VoiceQuality.high,
        ),
        (
          'vits-piper-en_US-ryan-high',
          0,
          'Ryan',
          'en-US',
          null,
          VoiceQuality.high,
        ),
        (
          'vits-piper-en_US-hfc_female-medium',
          0,
          'HFC',
          'en-US',
          VoiceGender.female,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-en_US-hfc_male-medium',
          0,
          'HFC',
          'en-US',
          VoiceGender.male,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-en_GB-cori-high',
          0,
          'Cori',
          'en-GB',
          null,
          VoiceQuality.high,
        ),
        (
          'vits-piper-en_GB-alba-medium',
          0,
          'Alba',
          'en-GB',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-en_GB-northern_english_male-medium',
          0,
          'Northern English',
          'en-GB',
          VoiceGender.male,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-pt_BR-faber-medium',
          0,
          'Faber',
          'pt-BR',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-pt_BR-cadu-medium',
          0,
          'Cadu',
          'pt-BR',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-pt_BR-jeff-medium',
          0,
          'Jeff',
          'pt-BR',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-pt_PT-tugao-medium',
          0,
          'Tugão',
          'pt-PT',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-fr_FR-siwis-medium',
          0,
          'Siwis',
          'fr-FR',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-fr_FR-tom-medium',
          0,
          'Tom',
          'fr-FR',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-fr_FR-upmc-medium',
          0,
          'Jessica',
          'fr-FR',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-fr_FR-upmc-medium',
          1,
          'Pierre',
          'fr-FR',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-it_IT-paola-medium',
          0,
          'Paola',
          'it-IT',
          null,
          VoiceQuality.medium,
        ),
        (
          'vits-piper-it_IT-riccardo-x_low',
          0,
          'Riccardo',
          'it-IT',
          null,
          VoiceQuality.low,
        ),
        (
          'vits-piper-de_DE-thorsten-high',
          0,
          'Thorsten',
          'de-DE',
          null,
          VoiceQuality.high,
        ),
        (
          'vits-piper-de_DE-kerstin-low',
          0,
          'Kerstin',
          'de-DE',
          null,
          VoiceQuality.low,
        ),
        (
          'vits-piper-de_DE-ramona-low',
          0,
          'Ramona',
          'de-DE',
          null,
          VoiceQuality.low,
        ),
        (
          'vits-piper-de_DE-eva_k-x_low',
          0,
          'Eva K',
          'de-DE',
          null,
          VoiceQuality.low,
        ),
      ];

  /// Las voces de Kokoro: el `sid`, el nombre, el acento, el género (la letra
  /// de su prefijo: `af_` es mujer de Estados Unidos) y la calidad (A y A−,
  /// alta; B− y C+, media; C, baja). Las de español y portugués no tienen
  /// nota en `VOICES.md`: queda sin poner.
  static const _kokoroVoices =
      <(int, String, String, VoiceGender, VoiceQuality?)>[
        (3, 'Heart', 'en-US', VoiceGender.female, VoiceQuality.high),
        (2, 'Bella', 'en-US', VoiceGender.female, VoiceQuality.high),
        (6, 'Nicole', 'en-US', VoiceGender.female, VoiceQuality.medium),
        (1, 'Aoede', 'en-US', VoiceGender.female, VoiceQuality.medium),
        (5, 'Kore', 'en-US', VoiceGender.female, VoiceQuality.medium),
        (9, 'Sarah', 'en-US', VoiceGender.female, VoiceQuality.medium),
        (0, 'Alloy', 'en-US', VoiceGender.female, VoiceQuality.low),
        (7, 'Nova', 'en-US', VoiceGender.female, VoiceQuality.low),
        (14, 'Fenrir', 'en-US', VoiceGender.male, VoiceQuality.medium),
        (16, 'Michael', 'en-US', VoiceGender.male, VoiceQuality.medium),
        (18, 'Puck', 'en-US', VoiceGender.male, VoiceQuality.medium),
        (21, 'Emma', 'en-GB', VoiceGender.female, VoiceQuality.medium),
        (22, 'Isabella', 'en-GB', VoiceGender.female, VoiceQuality.low),
        (25, 'Fable', 'en-GB', VoiceGender.male, VoiceQuality.low),
        (26, 'George', 'en-GB', VoiceGender.male, VoiceQuality.low),
        (28, 'Dora', 'es', VoiceGender.female, null),
        (29, 'Alex', 'es', VoiceGender.male, null),
        (53, 'Santa', 'es', VoiceGender.male, null),
        (30, 'Siwis', 'fr-FR', VoiceGender.female, VoiceQuality.medium),
        (35, 'Sara', 'it', VoiceGender.female, VoiceQuality.low),
        (36, 'Nicola', 'it', VoiceGender.male, VoiceQuality.low),
        (42, 'Dora', 'pt-BR', VoiceGender.female, null),
        (43, 'Alex', 'pt-BR', VoiceGender.male, null),
        (44, 'Santa', 'pt-BR', VoiceGender.male, null),
        (31, 'Alpha', 'hi', VoiceGender.female, VoiceQuality.low),
        (32, 'Beta', 'hi', VoiceGender.female, VoiceQuality.low),
        (33, 'Omega', 'hi', VoiceGender.male, VoiceQuality.low),
        (34, 'Psi', 'hi', VoiceGender.male, VoiceQuality.low),
      ];
}

/// La familia de un modelo: cómo se arma el motor para leerlo.
enum OfflineVoiceFamily {
  /// VITS de Piper: un hablante (o pocos) por paquete.
  piper,

  /// Kokoro: muchos hablantes en un solo paquete, que se eligen por su `sid`.
  kokoro,
}

/// Un paquete de sherpa-onnx (`<id>.tar.bz2`): lo que se baja de una vez y,
/// abierto, trae el modelo, sus fichas y los datos de espeak-ng.
@immutable
class OfflineVoicePackage {
  const OfflineVoicePackage({
    required this.id,
    required this.family,
    required this.bytes,
    required this.sha256,
  });

  const OfflineVoicePackage.piper(this.id, this.bytes, this.sha256)
    : family = OfflineVoiceFamily.piper;

  /// El nombre del paquete sin `.tar.bz2`: `vits-piper-es_AR-daniela-high`.
  final String id;
  final OfflineVoiceFamily family;

  /// Lo que pesa el paquete comprimido, verificado.
  final int bytes;

  /// La huella SHA-256 del paquete comprimido, verificada.
  final String sha256;

  String get archiveName => '$id.tar.bz2';

  String get url => '${OfflineVoiceCatalog.releaseBase}/$archiveName';

  @override
  bool operator ==(Object other) =>
      other is OfflineVoicePackage && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'OfflineVoicePackage($id)';
}

/// Cómo pronuncia Kokoro el texto de una voz: con un léxico (el inglés) o con
/// una voz de espeak-ng (los demás idiomas). sherpa-onnx lo fija al armar el
/// motor, no al leer: dos voces de Kokoro de idiomas distintos son dos motores.
@immutable
class KokoroPhonemes {
  const KokoroPhonemes.lexicon(String this.lexicon) : espeakVoice = null;

  const KokoroPhonemes.espeak(String this.espeakVoice) : lexicon = null;

  /// El archivo del léxico, dentro del paquete: `lexicon-us-en.txt`.
  final String? lexicon;

  /// La voz de espeak-ng: `es`, `fr-fr`, `pt-br`…
  final String? espeakVoice;

  /// Lo que distingue un motor de Kokoro de otro.
  String get key => lexicon ?? 'espeak:$espeakVoice';

  @override
  bool operator ==(Object other) =>
      other is KokoroPhonemes &&
      other.lexicon == lexicon &&
      other.espeakVoice == espeakVoice;

  @override
  int get hashCode => Object.hash(lexicon, espeakVoice);
}

/// Una voz neuronal del catálogo: un hablante de un paquete.
@immutable
class OfflineVoice {
  const OfflineVoice({
    required this.package,
    required this.speakerId,
    required this.name,
    required this.locale,
    this.gender,
    this.quality,
    this.kokoroPhonemes,
    this.sampleUrl,
  });

  final OfflineVoicePackage package;

  /// El `sid` del hablante en el paquete.
  final int speakerId;

  /// El nombre que muestra su tarjeta: el del hablante en el modelo.
  final String name;

  /// El idioma y su acento: `es-AR`; solo el idioma (`es`) si el modelo no
  /// dice de dónde es.
  final String locale;

  final VoiceGender? gender;
  final VoiceQuality? quality;

  /// Solo en las de Kokoro.
  final KokoroPhonemes? kokoroPhonemes;

  /// Una muestra corta publicada, en su idioma, para oírla antes de bajarla.
  /// Solo en las de Piper: las muestras de Kokoro dicen un texto en chino y en
  /// inglés con cada voz, y no dirían cómo suena en su idioma.
  final String? sampleUrl;

  /// Qué voz es, para siempre: lo que se guarda al elegirla o marcarla
  /// favorita. `<paquete>#<sid>`.
  String get id => '${package.id}#$speakerId';

  /// El idioma, sin el acento: `es`.
  String get language => locale.split('-').first;

  @override
  bool operator ==(Object other) => other is OfflineVoice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'OfflineVoice($id)';
}
