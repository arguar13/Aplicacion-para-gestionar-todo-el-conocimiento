import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

/// Lo que va antes del id de una voz propia en [NarrationVoice.name]: así el
/// lector, las preferencias y el podcast la reconocen sin preguntarle a nadie
/// (F47, paso 4).
const myVoicePrefix = 'mia:';

/// Si [voice] es una voz propia —clonada o creada—.
bool isMyVoice(NarrationVoice? voice) =>
    voice != null && voice.name.startsWith(myVoicePrefix);

/// El id de la voz propia que nombra [voice], o `null` si no es una.
String? myVoiceIdOf(NarrationVoice voice) =>
    isMyVoice(voice) ? voice.name.substring(myVoicePrefix.length) : null;

/// Dónde vive una voz propia, y por lo tanto con qué lee (decisión C).
enum MyVoiceHome {
  /// En el teléfono, gratis: una mezcla de voces de Kokoro.
  phone,

  /// En ElevenLabs, con la cuenta y la clave de la persona: leer con ella
  /// gasta su cuota, y el texto sale del teléfono (decisión F).
  elevenLabs,
}

/// De quién es la voz que se clona.
enum VoiceConsentKind {
  /// La de quien usa la app.
  own,

  /// La de otra persona que dio su permiso.
  permission,
}

/// El consentimiento para clonar una voz (F47, paso 4, decisión C): quién es,
/// cómo se llama y cuándo se confirmó. Se guarda **junto a la voz**, en su
/// ficha, y viaja con ella en la copia de la bóveda.
///
/// No hay un consentimiento para «alguien famoso» o «sin permiso»: esa voz no
/// se clona, y la app no deja llegar a grabarla.
@immutable
class VoiceConsent {
  const VoiceConsent({
    required this.kind,
    required this.personName,
    required this.grantedAt,
    this.statementVersion = currentStatementVersion,
  });

  /// La versión del texto que se confirmó: si cambia, se sabe cuál leyó.
  static const currentStatementVersion = 1;

  final VoiceConsentKind kind;

  /// El nombre de la persona dueña de la voz.
  final String personName;

  /// Cuándo se confirmó, en UTC.
  final DateTime grantedAt;
  final int statementVersion;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'personName': personName,
    'grantedAt': grantedAt.toUtc().toIso8601String(),
    'statementVersion': statementVersion,
  };

  static VoiceConsent? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = _enumByName(VoiceConsentKind.values, json['kind']);
    final name = json['personName'];
    final at = DateTime.tryParse('${json['grantedAt']}');
    if (kind == null || name is! String || name.trim().isEmpty || at == null) {
      return null;
    }
    return VoiceConsent(
      kind: kind,
      personName: name,
      grantedAt: at.toUtc(),
      statementVersion: (json['statementVersion'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceConsent &&
      other.kind == kind &&
      other.personName == personName &&
      other.grantedAt == grantedAt &&
      other.statementVersion == statementVersion;

  @override
  int get hashCode =>
      Object.hash(kind, personName, grantedAt, statementVersion);
}

/// La muestra con que se clonó una voz: el archivo, en la carpeta de la voz
/// dentro de la bóveda, y lo que se midió de ella.
@immutable
class MyVoiceRecording {
  const MyVoiceRecording({
    required this.file,
    required this.report,
    required this.uploaded,
  });

  /// El nombre del archivo dentro de la carpeta de la voz: `muestra.wav`.
  final String file;
  final RecordingReport report;

  /// Si se subió un audio en vez de grabarlo.
  final bool uploaded;

  Map<String, Object?> toJson() => {
    'file': file,
    'report': report.toJson(),
    'uploaded': uploaded,
  };

  static MyVoiceRecording? fromJson(Object? json) {
    if (json is! Map) return null;
    final file = json['file'];
    final report = RecordingReport.fromJson(json['report']);
    if (file is! String || file.isEmpty || report == null) return null;
    return MyVoiceRecording(
      file: file,
      report: report,
      uploaded: json['uploaded'] == true,
    );
  }
}

/// Una voz de la pestaña Mías (F47, paso 4): clonada con permiso, o creada
/// describiéndola. Es lo que se guarda en su ficha, `voz.json`.
@immutable
class MyVoice {
  const MyVoice({
    required this.id,
    required this.name,
    required this.origin,
    required this.home,
    required this.locale,
    required this.createdAt,
    this.gender,
    this.age,
    this.timbre,
    this.styles = const {},
    this.purposes = const {},
    this.description,
    this.blend,
    this.cloudVoiceId,
    this.consent,
    this.recording,
    this.sampleFile,
    this.faceSeed = 0,
  }) : assert(
         origin == VoiceOrigin.cloned || origin == VoiceOrigin.created,
         'una voz propia es clonada o creada',
       );

  final String id;
  final String name;

  /// [VoiceOrigin.cloned] o [VoiceOrigin.created].
  final VoiceOrigin origin;
  final MyVoiceHome home;

  /// El idioma y su acento, normalizado: `es`, `en-US`.
  final String locale;
  final DateTime createdAt;

  final VoiceGender? gender;
  final VoiceAge? age;
  final VoiceTimbre? timbre;
  final Set<VoiceStyle> styles;
  final Set<VoicePurpose> purposes;

  /// Lo que se escribió para crearla, si se la describió con palabras.
  final String? description;

  /// La mezcla de Kokoro de una creada en el teléfono. Su lugar —su `sid`—
  /// en el `voices.bin` de las creadas no se guarda: se asigna al armarlo
  /// ([blendSlots]), así dos voces que llegan de bóvedas distintas nunca
  /// chocan por el mismo lugar.
  final KokoroBlend? blend;

  /// Su id en ElevenLabs, si vive allá.
  final String? cloudVoiceId;

  /// Solo en las clonadas.
  final VoiceConsent? consent;

  /// Solo en las clonadas: la grabación o el audio subido.
  final MyVoiceRecording? recording;

  /// Una muestra de cómo suena, ya generada, en la carpeta de la voz: la de
  /// las que viven en la nube, para no gastar cuota cada vez que se la oye.
  final String? sampleFile;

  /// Con qué cara se la eligió: cambiarla no cambia la voz.
  final int faceSeed;

  /// El idioma, sin el acento.
  String get language => accentLanguage(locale);

  /// Con qué se le pide al lector que lea con ella.
  NarrationVoice get narrationVoice => NarrationVoice(
    name: '$myVoicePrefix$id',
    locale: locale,
    engine: home == MyVoiceHome.phone
        ? NarrationEngine.offline
        : NarrationEngine.cloud,
  );

  /// De dónde sale su cara: el id y la cara elegida.
  String get faceKey => faceSeed == 0 ? id : '$id#$faceSeed';

  MyVoice copyWith({String? name, int? faceSeed, String? sampleFile}) =>
      MyVoice(
        id: id,
        name: name ?? this.name,
        origin: origin,
        home: home,
        locale: locale,
        createdAt: createdAt,
        gender: gender,
        age: age,
        timbre: timbre,
        styles: styles,
        purposes: purposes,
        description: description,
        blend: blend,
        cloudVoiceId: cloudVoiceId,
        consent: consent,
        recording: recording,
        sampleFile: sampleFile ?? this.sampleFile,
        faceSeed: faceSeed ?? this.faceSeed,
      );

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'origin': origin.name,
    'home': home.name,
    'locale': locale,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'gender': gender?.name,
    'age': age?.name,
    'timbre': timbre?.name,
    'styles': [for (final style in styles) style.name],
    'purposes': [for (final purpose in purposes) purpose.name],
    'description': description,
    'blend': blend?.toJson(),
    'cloudVoiceId': cloudVoiceId,
    'consent': consent?.toJson(),
    'recording': recording?.toJson(),
    'sampleFile': sampleFile,
    'faceSeed': faceSeed,
  };

  /// La voz de una ficha, o `null` si no se entiende o le falta lo que la
  /// hace leer: una creada en el teléfono sin mezcla o sin lugar, una de la
  /// nube sin su id allá, una clonada sin consentimiento.
  static MyVoice? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final locale = json['locale'];
    final origin = _enumByName(VoiceOrigin.values, json['origin']);
    final home = _enumByName(MyVoiceHome.values, json['home']);
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        locale is! String ||
        createdAt == null ||
        home == null ||
        (origin != VoiceOrigin.cloned && origin != VoiceOrigin.created)) {
      return null;
    }
    final blend = KokoroBlend.fromJson(json['blend']);
    final cloudVoiceId = json['cloudVoiceId'];
    final consent = VoiceConsent.fromJson(json['consent']);
    if (home == MyVoiceHome.phone && blend == null) {
      return null;
    }
    if (home == MyVoiceHome.elevenLabs &&
        (cloudVoiceId is! String || cloudVoiceId.isEmpty)) {
      return null;
    }
    if (origin == VoiceOrigin.cloned && consent == null) return null;
    return MyVoice(
      id: id,
      name: name,
      origin: origin!,
      home: home,
      locale: normalizeAccent(locale),
      createdAt: createdAt.toUtc(),
      gender: _enumByName(VoiceGender.values, json['gender']),
      age: _enumByName(VoiceAge.values, json['age']),
      timbre: _enumByName(VoiceTimbre.values, json['timbre']),
      styles: _enumSet(VoiceStyle.values, json['styles']),
      purposes: _enumSet(VoicePurpose.values, json['purposes']),
      description: json['description'] as String?,
      blend: blend,
      cloudVoiceId: cloudVoiceId as String?,
      consent: consent,
      recording: MyVoiceRecording.fromJson(json['recording']),
      sampleFile: json['sampleFile'] as String?,
      faceSeed: (json['faceSeed'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MyVoice &&
      other.id == id &&
      other.name == name &&
      other.faceSeed == faceSeed &&
      other.sampleFile == sampleFile;

  @override
  int get hashCode => Object.hash(id, name, faceSeed, sampleFile);

  @override
  String toString() => 'MyVoice($id, $name)';
}

/// El lugar —el `sid`— de cada voz creada en el teléfono en el `voices.bin`
/// de las creadas, por su id: de la más vieja a la más nueva (y por id, si
/// nacieron a la vez), hasta [kokoroSpeakerSlots]. Las que no caben no leen
/// hasta que se borre otra.
///
/// Se calcula cada vez y no se guarda en la ficha: al unir dos bóvedas,
/// las creadas de las dos entran sin pisarse, y el `voices.bin` se arma de
/// nuevo con todas, porque cambió su firma.
Map<String, int> blendSlots(Iterable<MyVoice> voices) {
  final phone =
      [
        for (final voice in voices)
          if (voice.home == MyVoiceHome.phone && voice.blend != null) voice,
      ]..sort((a, b) {
        final byAge = a.createdAt.compareTo(b.createdAt);
        return byAge != 0 ? byAge : a.id.compareTo(b.id);
      });
  return {
    for (final (slot, voice) in phone.take(kokoroSpeakerSlots).indexed)
      voice.id: slot,
  };
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

Set<T> _enumSet<T extends Enum>(List<T> values, Object? names) => {
  if (names is List)
    for (final name in names) ?_enumByName(values, name),
};
