import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

/// Una voz de la biblioteca (F47, paso 3): cualquiera de las que pueden leer
/// —del teléfono, sin conexión y, en el paso 4, clonadas o creadas—, con lo
/// que dice su tarjeta y lo que se filtra.
///
/// Es lo mismo para todas: la lista, Filtrar, Favoritas y la cara no
/// preguntan de dónde sale una voz, salvo para decirlo ([origin]).
@immutable
class VoiceProfile {
  const VoiceProfile({
    required this.id,
    required this.voice,
    required this.origin,
    required this.locale,
    this.name,
    this.number,
    this.offline,
    this.gender,
    this.quality,
    this.purposes = const {},
    this.timbre,
    this.styles = const {},
    this.age,
    this.needsInternet = false,
    this.mine,
    this.noRoom = false,
  }) : assert(name != null || number != null, 'una voz sin nombre ni número');

  /// Qué voz es, para siempre: lo que se guarda al marcarla favorita.
  final String id;

  /// Con qué se le pide al motor que lea.
  final NarrationVoice voice;

  final VoiceOrigin origin;

  /// El acento, normalizado: `es-AR`, o solo `es` si no se sabe de dónde es.
  final String locale;

  /// El nombre que se muestra; `null` en una voz del teléfono que solo tiene
  /// un código por nombre (`es-us-x-esd-local`): se muestra «Voz [number]».
  final String? name;

  /// El número de la voz dentro de su acento, cuando no tiene nombre.
  final int? number;

  /// La voz del catálogo, si es una sin conexión: su paquete, su tamaño.
  final OfflineVoice? offline;

  final VoiceGender? gender;
  final VoiceQuality? quality;
  final Set<VoicePurpose> purposes;
  final VoiceTimbre? timbre;
  final Set<VoiceStyle> styles;
  final VoiceAge? age;

  /// Una voz del teléfono que lee desde internet (`…-network` en Android), o
  /// una propia que vive en ElevenLabs (F47, paso 4).
  final bool needsInternet;

  /// La voz propia, si es una clonada o creada (F47, paso 4): dónde vive, su
  /// consentimiento y su cara elegida.
  final MyVoice? mine;

  /// Una creada en el teléfono que no cabe en el `voices.bin` de las creadas
  /// (ver [blendSlots]): está, pero no lee hasta que se borre otra.
  final bool noRoom;

  /// Si leer con ella pasa por la nube y gasta cuota (F47, paso 4).
  bool get inCloud => mine?.home == MyVoiceHome.elevenLabs;

  /// De dónde sale su cara: el id, o la cara que se le eligió.
  String get faceKey => mine?.faceKey ?? id;

  /// El idioma, sin el acento: `es`.
  String get language => accentLanguage(locale);

  /// Lo que dice la cara: el nombre o, sin él, el número.
  String get label => name ?? '$number';

  @override
  bool operator ==(Object other) => other is VoiceProfile && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VoiceProfile($id)';
}

/// Con qué se le pide al motor sin conexión que lea [voice].
NarrationVoice narrationVoiceOf(OfflineVoice voice) => NarrationVoice(
  name: voice.id,
  locale: voice.locale,
  engine: NarrationEngine.offline,
);

/// Las voces del catálogo sin conexión, como voces de la biblioteca.
List<VoiceProfile> offlineVoiceProfiles(Iterable<OfflineVoice> voices) => [
  for (final voice in voices)
    VoiceProfile(
      id: voice.id,
      voice: narrationVoiceOf(voice),
      origin: VoiceOrigin.offline,
      locale: normalizeAccent(voice.locale),
      name: voice.name,
      offline: voice,
      gender: voice.gender,
      quality: voice.quality,
    ),
];

/// Las voces de la pestaña Mías, como voces de la biblioteca (F47, paso 4):
/// con los rasgos que eligió quien las creó, que Filtrar ofrece.
List<VoiceProfile> myVoiceProfiles(Iterable<MyVoice> voices) {
  final slots = blendSlots(voices);
  return [
    for (final voice in voices)
      VoiceProfile(
        id: voice.narrationVoice.name,
        voice: voice.narrationVoice,
        origin: voice.origin,
        locale: voice.locale,
        name: voice.name,
        gender: voice.gender,
        age: voice.age,
        timbre: voice.timbre,
        styles: voice.styles,
        purposes: voice.purposes,
        needsInternet: voice.home == MyVoiceHome.elevenLabs,
        mine: voice,
        noRoom: voice.home == MyVoiceHome.phone && !slots.containsKey(voice.id),
      ),
  ];
}

/// La voz de la biblioteca de una voz del teléfono —la elegida, que puede no
/// estar en la lista de ahora—, o la de una sin conexión del catálogo. `null`
/// si es una sin conexión que el catálogo ya no tiene, o una propia que no
/// está en [mine] (F47, paso 4).
VoiceProfile? voiceProfileOf(
  NarrationVoice voice, {
  int number = 1,
  Iterable<MyVoice> mine = const [],
}) {
  if (isMyVoice(voice)) {
    final id = myVoiceIdOf(voice);
    final own = mine.where((candidate) => candidate.id == id);
    return own.isEmpty ? null : myVoiceProfiles(own).single;
  }
  if (voice.engine == NarrationEngine.offline) {
    final offline = OfflineVoiceCatalog.byId(voice.name);
    return offline == null ? null : offlineVoiceProfiles([offline]).single;
  }
  final code = looksLikeVoiceCode(voice.name);
  return VoiceProfile(
    id: deviceVoiceId(voice),
    voice: voice,
    origin: VoiceOrigin.device,
    locale: normalizeAccent(voice.locale),
    name: code ? null : voice.name,
    number: code ? number : null,
    needsInternet: _runsOf(voice) == _Runs.online,
  );
}

/// El identificador de una voz del teléfono: su nombre y su acento.
String deviceVoiceId(NarrationVoice voice) =>
    'device:${voice.name}@${normalizeAccent(voice.locale)}';

/// Las voces del teléfono, como voces de la biblioteca: en cada acento,
/// primero las que andan sin conexión, y las que solo tienen un código por
/// nombre, numeradas en ese orden («Voz 1», «Voz 2»).
List<VoiceProfile> deviceVoiceProfiles(Iterable<NarrationVoice> voices) {
  final byAccent = <String, List<NarrationVoice>>{};
  for (final voice in voices) {
    (byAccent[normalizeAccent(voice.locale)] ??= []).add(voice);
  }
  return [
    for (final accent in byAccent.keys)
      for (final (index, voice)
          in (byAccent[accent]!..sort((a, b) {
                final byRuns = _runsOf(a).index.compareTo(_runsOf(b).index);
                return byRuns != 0 ? byRuns : a.name.compareTo(b.name);
              }))
              .indexed)
        voiceProfileOf(voice, number: index + 1)!,
  ];
}

enum _Runs { onDevice, online, unknown }

/// Android nombra sus voces con un código —`es-us-x-esd-local`,
/// `es-us-x-esd-network`—: lo de al final dice si anda sin conexión.
_Runs _runsOf(NarrationVoice voice) {
  final name = voice.name.toLowerCase();
  if (name.contains('network')) return _Runs.online;
  if (name.contains('local')) return _Runs.onDevice;
  return _Runs.unknown;
}

/// Un nombre que es un código y no un nombre —`es-us-x-esd-local`—: mejor
/// «Voz 1» que eso. Las voces con nombre de verdad —«Mónica» en iOS— se
/// muestran tal cual.
bool looksLikeVoiceCode(String name) => RegExp(
  r'^[a-z]{2,3}[-_][a-z]{2,3}([-_]|$)',
  caseSensitive: false,
).hasMatch(name);
