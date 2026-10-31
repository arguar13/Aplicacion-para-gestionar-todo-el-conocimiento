import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

/// Una voz de Kokoro y cuánto pesa en una mezcla.
@immutable
class BlendPart {
  const BlendPart(this.speakerId, this.weight);

  /// El `sid` de la voz en el `voices.bin` de Kokoro v1.0.
  final int speakerId;

  /// De 0 a 1; las partes de una mitad suman 1.
  final double weight;

  Map<String, Object?> toJson() => {'sid': speakerId, 'weight': weight};

  static BlendPart? fromJson(Object? json) {
    if (json is! Map) return null;
    final sid = json['sid'];
    final weight = json['weight'];
    if (sid is! num || weight is! num || weight <= 0) return null;
    return BlendPart(sid.toInt(), weight.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is BlendPart &&
      other.speakerId == speakerId &&
      other.weight == weight;

  @override
  int get hashCode => Object.hash(speakerId, weight);

  @override
  String toString() => 'BlendPart($speakerId, $weight)';
}

/// Una voz creada en el teléfono (F47, paso 4, decisión C): una mezcla de
/// voces de Kokoro, gratis y sin conexión, que no es la de nadie.
///
/// **Cómo se mezcla** —lo que hace el propio Kokoro con `af_bella,af_sky`:
/// el promedio de los estilos de cada voz (`torch.mean` en `KPipeline`)—,
/// pero con dos pesos distintos, uno por cada mitad del estilo:
///
/// - el estilo de Kokoro es un vector de 256 números por largo de texto; los
///   primeros 128 los usa el **decodificador**, que da el timbre, y los
///   últimos 128 el **predictor de prosodia**, que da la duración y la
///   entonación (`ref_s[:, :128]` y `ref_s[:, 128:]` en `model.py` de
///   `hexgrad/kokoro`). Por eso [timbre] y [prosody] se mezclan aparte: el
///   timbre de unas voces con la forma de hablar de otras;
/// - [pace] multiplica la velocidad de lectura: el ritmo propio de la voz.
///
/// El idioma ([locale]) dice cómo se pronuncia: el léxico o la voz de
/// espeak-ng de Kokoro para ese idioma, como en las voces del catálogo.
@immutable
class KokoroBlend {
  KokoroBlend({
    required this.locale,
    required List<BlendPart> timbre,
    required List<BlendPart> prosody,
    this.pace = 1,
  }) : timbre = _normalized(timbre),
       prosody = _normalized(prosody) {
    if (!OfflineVoiceCatalog.kokoroLocales.contains(locale)) {
      throw ArgumentError.value(locale, 'locale', 'Kokoro no lo pronuncia');
    }
  }

  final String locale;
  final List<BlendPart> timbre;
  final List<BlendPart> prosody;
  final double pace;

  /// Cómo pronuncia Kokoro el texto de esta voz.
  KokoroPhonemes get phonemes => OfflineVoiceCatalog.kokoroPhonemesFor(locale);

  /// Las voces que entran en la mezcla, con cuánto pesan en promedio de las
  /// dos mitades, de la que más a la que menos: lo que dice la pantalla.
  List<BlendPart> get summary {
    final weights = <int, double>{};
    for (final part in timbre) {
      weights[part.speakerId] =
          (weights[part.speakerId] ?? 0) + part.weight / 2;
    }
    for (final part in prosody) {
      weights[part.speakerId] =
          (weights[part.speakerId] ?? 0) + part.weight / 2;
    }
    return [
      for (final MapEntry(:key, :value) in weights.entries)
        BlendPart(key, value),
    ]..sort((a, b) => b.weight.compareTo(a.weight));
  }

  Map<String, Object?> toJson() => {
    'locale': locale,
    'timbre': [for (final part in timbre) part.toJson()],
    'prosody': [for (final part in prosody) part.toJson()],
    'pace': pace,
  };

  static KokoroBlend? fromJson(Object? json) {
    if (json is! Map) return null;
    final locale = json['locale'];
    final timbre = _parts(json['timbre']);
    final prosody = _parts(json['prosody']);
    final pace = json['pace'];
    if (locale is! String ||
        !OfflineVoiceCatalog.kokoroLocales.contains(locale) ||
        timbre.isEmpty ||
        prosody.isEmpty ||
        pace is! num ||
        pace <= 0) {
      return null;
    }
    return KokoroBlend(
      locale: locale,
      timbre: timbre,
      prosody: prosody,
      pace: pace.toDouble(),
    );
  }

  static List<BlendPart> _parts(Object? json) => [
    if (json is List)
      for (final part in json) ?BlendPart.fromJson(part),
  ];

  /// Los pesos de una mitad, sumando 1, y la misma voz una sola vez.
  static List<BlendPart> _normalized(List<BlendPart> parts) {
    final weights = <int, double>{};
    for (final part in parts) {
      if (part.weight <= 0) continue;
      weights[part.speakerId] = (weights[part.speakerId] ?? 0) + part.weight;
    }
    final total = weights.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      throw ArgumentError.value(parts, 'parts', 'una mezcla sin voces');
    }
    return List.unmodifiable([
      for (final MapEntry(:key, :value) in weights.entries)
        BlendPart(key, value / total),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is KokoroBlend &&
      other.locale == locale &&
      other.pace == pace &&
      listEquals(other.timbre, timbre) &&
      listEquals(other.prosody, prosody);

  @override
  int get hashCode => Object.hash(
    locale,
    pace,
    Object.hashAll(timbre),
    Object.hashAll(prosody),
  );
}

/// Cómo se pide una voz nueva con los controles (F47, paso 4b): el idioma y
/// el acento, el género, la edad, el timbre, el estilo y el ritmo. [variant]
/// elige otra combinación de las mismas voces: «Otra variante».
@immutable
class VoiceDesign {
  const VoiceDesign({
    required this.locale,
    this.gender,
    this.age,
    this.timbre,
    this.style,
    this.pace = 1,
    this.variant = 0,
  });

  /// Uno de [OfflineVoiceCatalog.kokoroLocales].
  final String locale;
  final VoiceGender? gender;
  final VoiceAge? age;
  final VoiceTimbre? timbre;
  final VoiceStyle? style;

  /// El ritmo elegido, de [minPace] a [maxPace].
  final double pace;
  final int variant;

  static const minPace = 0.8;
  static const maxPace = 1.25;

  VoiceDesign copyWith({
    String? locale,
    VoiceGender? gender,
    VoiceAge? age,
    VoiceTimbre? timbre,
    VoiceStyle? style,
    double? pace,
    int? variant,
    bool clearGender = false,
    bool clearAge = false,
    bool clearTimbre = false,
    bool clearStyle = false,
  }) => VoiceDesign(
    locale: locale ?? this.locale,
    gender: clearGender ? null : gender ?? this.gender,
    age: clearAge ? null : age ?? this.age,
    timbre: clearTimbre ? null : timbre ?? this.timbre,
    style: clearStyle ? null : style ?? this.style,
    pace: pace ?? this.pace,
    variant: variant ?? this.variant,
  );

  @override
  bool operator ==(Object other) =>
      other is VoiceDesign &&
      other.locale == locale &&
      other.gender == gender &&
      other.age == age &&
      other.timbre == timbre &&
      other.style == style &&
      other.pace == pace &&
      other.variant == variant;

  @override
  int get hashCode =>
      Object.hash(locale, gender, age, timbre, style, pace, variant);
}

/// Lo que más pesa una sola voz en la mitad del timbre: una mezcla que es casi
/// una voz del catálogo no es una voz nueva —sería la de esa voz—.
const maxTimbreShare = 0.8;

/// La mezcla con que se empieza a escuchar [design] (F47, paso 4b).
///
/// **Es una heurística, el punto de partida para escuchar y ajustar**: nadie
/// publica el timbre, el estilo ni la edad de las voces de Kokoro —solo su
/// idioma, su género y su nota—, así que la app no dice que una voz es
/// «grave» o «serena»; usa lo que sí se sabe y lo que hace la mezcla:
///
/// - **El idioma** da la pronunciación y la mitad de la prosodia: la forma de
///   hablar sale de voces nativas de ese idioma (en español, Dora, Alex y
///   Santa), del género pedido si las hay.
/// - **El género** da la mitad del timbre: voces de ese género, primero las
///   nativas y después las de mejor nota de cualquier idioma. Sin género,
///   mitad y mitad.
/// - **El timbre:** «grave» corre una parte del timbre hacia voces de hombre
///   y «brillante» hacia voces de mujer —en Kokoro es lo que más mueve la
///   altura—; «aterciopelado» reparte en tres voces —el promedio suaviza— y
///   «claro» concentra en una, sin pasar de [maxTimbreShare].
/// - **La edad:** «joven» corre una décima del timbre hacia voces de mujer y
///   acelera un poco; «mayor», hacia voces de hombre y más lento.
/// - **El estilo:** «sereno» y «cálido» reparten la prosodia entre varias
///   voces nativas —el promedio aplana la entonación— y bajan un poco el
///   ritmo; «expresivo», «enérgico» y «con autoridad» la concentran en una,
///   que conserva sus subidas y bajadas, y «enérgico» acelera.
/// - [VoiceDesign.variant] rota qué voces de cada grupo entran.
///
/// Siempre son al menos dos voces en el timbre, ninguna por encima de
/// [maxTimbreShare]: la voz creada no es la de ninguna voz del catálogo.
KokoroBlend proposeBlend(VoiceDesign design) {
  final kokoro = [
    for (final voice in OfflineVoiceCatalog.voices)
      if (voice.package == OfflineVoiceCatalog.kokoro && !voice.isBlend) voice,
  ];
  final native = [
    for (final voice in kokoro)
      if (voice.locale == design.locale) voice,
  ];
  List<OfflineVoice> ofGender(List<OfflineVoice> voices, VoiceGender gender) =>
      [
        for (final voice in voices)
          if (voice.gender == gender) voice,
      ];

  // Las voces de un género, primero las nativas y después las de mejor nota.
  List<int> timbrePool(VoiceGender gender) {
    final others =
        ofGender(
            kokoro,
            gender,
          ).where((voice) => voice.locale != design.locale).toList()
          ..sort((a, b) => _qualityRank(a).compareTo(_qualityRank(b)));
    return _rotate([
      for (final voice in [...ofGender(native, gender), ...others])
        voice.speakerId,
    ], design.variant);
  }

  final timbre = <BlendPart>[];
  void addTimbre(List<int> pool, double weight, {int skip = 0}) {
    if (pool.isEmpty) return;
    timbre.add(BlendPart(pool[skip % pool.length], weight));
  }

  final female = timbrePool(VoiceGender.female);
  final male = timbrePool(VoiceGender.male);
  // Hacia dónde corre el timbre lo que se pidió: + mujer, − hombre.
  var lean = 0.0;
  lean += switch (design.timbre) {
    VoiceTimbre.deep => -0.25,
    VoiceTimbre.bright => 0.25,
    _ => 0.0,
  };
  lean += switch (design.age) {
    VoiceAge.young => 0.1,
    VoiceAge.senior => -0.1,
    _ => 0.0,
  };
  final gender = design.gender;
  if (gender == null) {
    addTimbre(female, 0.5 + lean / 2);
    addTimbre(male, 0.5 - lean / 2);
  } else {
    final own = gender == VoiceGender.female ? female : male;
    final other = gender == VoiceGender.female ? male : female;
    // Lo que se corre hacia el otro género, y si el pedido va hacia el mismo
    // (una mujer «brillante»), se queda en el propio, con otra voz.
    final toOther = gender == VoiceGender.female ? -lean : lean;
    final shares = switch (design.timbre) {
      VoiceTimbre.velvety => [0.4, 0.3, 0.3],
      VoiceTimbre.clear => [maxTimbreShare, 1 - maxTimbreShare],
      _ => [0.65, 0.35],
    };
    final crossed = toOther > 0 ? toOther : 0.0;
    for (final (index, share) in shares.indexed) {
      addTimbre(own, share * (1 - crossed), skip: index);
    }
    if (crossed > 0) addTimbre(other, crossed);
  }

  // La forma de hablar: voces nativas, del género pedido si hay.
  final prosodyPool = _rotate([
    for (final voice
        in gender != null && ofGender(native, gender).isNotEmpty
            ? ofGender(native, gender)
            : native)
      voice.speakerId,
    // Si el género pedido tiene una sola nativa, las otras nativas suman
    // variedad al repartir.
    for (final voice in native)
      if (gender != null && voice.gender != gender) voice.speakerId,
  ], design.variant);
  final spread = switch (design.style) {
    VoiceStyle.calm || VoiceStyle.warm => true,
    _ => false,
  };
  final prosody = <BlendPart>[
    if (spread)
      for (final sid in prosodyPool.take(3)) BlendPart(sid, 1)
    else ...[
      BlendPart(prosodyPool.first, design.style == null ? 0.6 : 0.8),
      if (prosodyPool.length > 1)
        BlendPart(prosodyPool[1], design.style == null ? 0.4 : 0.2),
    ],
  ];

  final pace =
      design.pace *
      switch (design.style) {
        VoiceStyle.calm => 0.94,
        VoiceStyle.warm => 0.97,
        VoiceStyle.energetic => 1.06,
        VoiceStyle.authoritative => 0.97,
        VoiceStyle.expressive || null => 1.0,
      } *
      switch (design.age) {
        VoiceAge.young => 1.03,
        VoiceAge.senior => 0.94,
        VoiceAge.adult || null => 1.0,
      };

  return KokoroBlend(
    locale: design.locale,
    timbre: capTimbre(timbre),
    prosody: prosody,
    pace: double.parse(pace.clamp(0.7, 1.4).toStringAsFixed(3)),
  );
}

/// Si una sola voz pasa de [maxTimbreShare] —una mezcla que se repite, o un
/// grupo con una sola voz—, se reparte lo que sobra con otra.
@visibleForTesting
List<BlendPart> capTimbre(List<BlendPart> parts) {
  final weights = <int, double>{};
  for (final part in parts) {
    weights[part.speakerId] = (weights[part.speakerId] ?? 0) + part.weight;
  }
  final total = weights.values.fold<double>(0, (a, b) => a + b);
  final normalized = {
    for (final MapEntry(:key, :value) in weights.entries) key: value / total,
  };
  if (normalized.length >= 2 &&
      normalized.values.every((w) => w <= maxTimbreShare + 1e-9)) {
    return [
      for (final MapEntry(:key, :value) in normalized.entries)
        BlendPart(key, value),
    ];
  }
  // Una sola voz, o una de más: lo que sobra va a otra de la mezcla o, si no
  // hay, a otra de Kokoro del mismo género.
  final top = normalized.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final companion = normalized.keys.firstWhere(
    (sid) => sid != top.key,
    orElse: () => _companionOf(top.key),
  );
  final excess = top.value - maxTimbreShare;
  return [
    for (final MapEntry(:key, :value) in normalized.entries)
      if (key == top.key)
        BlendPart(key, maxTimbreShare)
      else if (key == companion)
        BlendPart(key, value + excess)
      else
        BlendPart(key, value),
    if (!normalized.containsKey(companion)) BlendPart(companion, excess),
  ];
}

/// Otra voz de Kokoro del mismo género que [sid], para que nunca quede sola.
int _companionOf(int sid) {
  final kokoro = [
    for (final voice in OfflineVoiceCatalog.voices)
      if (voice.package == OfflineVoiceCatalog.kokoro && !voice.isBlend) voice,
  ];
  final self = kokoro.firstWhere((voice) => voice.speakerId == sid);
  return kokoro
      .firstWhere(
        (voice) => voice.speakerId != sid && voice.gender == self.gender,
        orElse: () => kokoro.firstWhere((voice) => voice.speakerId != sid),
      )
      .speakerId;
}

int _qualityRank(OfflineVoice voice) => switch (voice.quality) {
  VoiceQuality.high => 0,
  VoiceQuality.medium => 1,
  null => 2,
  VoiceQuality.low => 3,
};

List<int> _rotate(List<int> values, int by) {
  final unique = <int>[];
  for (final value in values) {
    if (!unique.contains(value)) unique.add(value);
  }
  if (unique.isEmpty) return unique;
  final shift = by % unique.length;
  return [...unique.skip(shift), ...unique.take(shift)];
}

/// Cuántas voces creadas en el teléfono caben: tantas como hablantes trae el
/// `voices.bin` de Kokoro v1.0 —54—, porque sherpa-onnx lee el número de
/// hablantes de los metadatos del modelo y exige que el `voices.bin` tenga
/// exactamente esa cantidad (ver `KokoroStyleBank`).
const kokoroSpeakerSlots = 54;

/// Lo que mide el estilo de un hablante en el `voices.bin` de Kokoro v1.0:
/// 510 filas —una por largo de texto en fonemas— de 256 números de 32 bits
/// (`style_dim` = 510, 1, 256 en los metadatos del modelo).
const kokoroStyleRows = 510;
const kokoroStyleWidth = 256;

/// Dónde termina la mitad del timbre: el decodificador usa los primeros 128.
const kokoroTimbreWidth = 128;
