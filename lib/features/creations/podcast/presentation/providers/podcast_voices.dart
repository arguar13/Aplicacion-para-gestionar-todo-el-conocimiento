import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';

/// Una voz que se puede elegir para el podcast, en «Elegí las voces».
@immutable
class PodcastVoiceOption {
  const PodcastVoiceOption({
    required this.id,
    required this.name,
    required this.locale,
    required this.origin,
    this.ready = true,
    this.offline,
  });

  /// Su id estable, el que se guarda, con su prefijo de origen
  /// (`SpeechVoiceIds`): `offline:` una sin conexión, `device:` una del
  /// teléfono.
  final String id;

  /// Su nombre: el de la voz sin conexión («Daniela») o, en una del
  /// teléfono, como lo da Android —un código, casi siempre—.
  final String name;

  /// Su acento: `es-AR`.
  final String locale;

  /// De dónde es: del teléfono, sin conexión y, en el paso 4, clonada o
  /// creada.
  final VoiceOrigin origin;

  /// Si ya puede generar audio, sin bajar nada: una sin conexión que todavía
  /// no se bajó no.
  final bool ready;

  /// La voz del catálogo, si es una sin conexión: para bajarla.
  final OfflineVoice? offline;

  /// Si [name] es un código y no un nombre —`es-us-x-esd-local`—: mejor
  /// «Voz 1» que eso.
  bool get nameIsCode => looksLikeVoiceCode(name);

  /// El nombre de su acento, en su idioma: «Español (Argentina)».
  String get accent => accentDisplayName(locale);

  @override
  bool operator ==(Object other) =>
      other is PodcastVoiceOption &&
      other.id == id &&
      other.name == name &&
      other.locale == locale &&
      other.origin == origin &&
      other.ready == ready &&
      other.offline == offline;

  @override
  int get hashCode => Object.hash(id, name, locale, origin, ready, offline);
}

/// Las voces que se ofrecen para un podcast en el idioma `languageCode`
/// (F47, paso 6b), **las de la biblioteca de voces** (`voiceLibraryProvider`),
/// cada idioma con sus voces nativas (decisión L) y en el orden en que
/// conviene elegirlas:
///
/// 1. las que ya pueden generar: las sin conexión bajadas —las de mejor
///    calidad primero— y después las del teléfono que andan sin conexión;
/// 2. las sin conexión del idioma que falta bajar, para ofrecer bajarlas.
///
/// **Las que leen por internet no se ofrecen** (decisiones B y F de F47,
/// que todo quede en el teléfono): una del teléfono `…-network` mandaría el
/// guion a quien hace la voz.
///
/// **El enganche del paso 4**: las clonadas y las creadas llegan por la
/// biblioteca con su propio id (con su prefijo), y se ofrecen tal cual; si
/// leen en la nube, quien las hace (`speechVoiceRenderersProvider`) dice su
/// precio, y la hoja avisa el costo y pide confirmación antes de generar.
final podcastVoiceOptionsProvider = FutureProvider.autoDispose
    .family<List<PodcastVoiceOption>, String>((ref, languageCode) async {
      final library = await ref.watch(voiceLibraryProvider.future);
      // Qué paquetes están bajados, ya sabido: con lo de antes de saberlo,
      // ninguna sin conexión estaría lista y se elegirían otras.
      final installed = await ref.watch(installedVoicePackagesProvider.future);
      final renderer = ref.watch(speechAudioRendererProvider);
      final options = <PodcastVoiceOption>[];
      for (final voice in library) {
        if (voice.language != languageCode || voice.needsInternet) continue;
        final option = switch (voice.origin) {
          VoiceOrigin.offline => PodcastVoiceOption(
            id: SpeechVoiceIds.offline(voice.offline!.id),
            name: voice.offline!.name,
            locale: voice.locale,
            origin: VoiceOrigin.offline,
            ready: installed.contains(voice.offline!.package.id),
            offline: voice.offline,
          ),
          VoiceOrigin.device => PodcastVoiceOption(
            id: PodcastVoiceId.device(
              locale: voice.locale,
              name: voice.voice.name,
            ),
            name: voice.voice.name,
            locale: voice.locale,
            origin: VoiceOrigin.device,
          ),
          VoiceOrigin.cloned || VoiceOrigin.created => PodcastVoiceOption(
            id: voice.id,
            name: voice.label,
            locale: voice.locale,
            origin: voice.origin,
            ready: await renderer.isReady(voice.id),
          ),
        };
        // Lo que nadie sabe hacer en este dispositivo no se ofrece: elegirla
        // sería un podcast sin audio.
        if (renderer.rendererOf(option.id) == null) continue;
        options.add(option);
      }
      int rank(PodcastVoiceOption o) => switch (o) {
        PodcastVoiceOption(ready: false) => 3,
        PodcastVoiceOption(origin: VoiceOrigin.device) => 2,
        PodcastVoiceOption(origin: VoiceOrigin.offline) => 0,
        _ => 1,
      };
      int quality(PodcastVoiceOption o) =>
          o.offline?.quality?.index ?? VoiceQuality.values.length;
      options.sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        final byQuality = quality(a).compareTo(quality(b));
        if (byQuality != 0) return byQuality;
        final byAccent = a.accent.compareTo(b.accent);
        return byAccent != 0 ? byAccent : a.name.compareTo(b.name);
      });
      return options;
    });
