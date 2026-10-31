import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';

/// Una voz que se puede elegir para el podcast, en «Elegí las voces».
@immutable
class PodcastVoiceOption {
  const PodcastVoiceOption({
    required this.id,
    required this.name,
    required this.locale,
    this.onDevice,
  });

  /// Su id estable, el que se guarda (`PodcastVoiceId`).
  final String id;

  /// Su nombre, como lo da quien la tiene: en Android, un código.
  final String name;

  /// Su acento: `es-AR`.
  final String locale;

  /// Si se sabe que anda sin conexión (`true`), o `null` si no se sabe. Las
  /// que necesitan internet no se ofrecen.
  final bool? onDevice;

  /// Si [name] es un código y no un nombre —`es-us-x-esd-local`—: mejor
  /// «Voz 1» que eso.
  bool get nameIsCode => RegExp(
    r'^[a-z]{2,3}[-_][a-z]{2,3}([-_]|$)',
    caseSensitive: false,
  ).hasMatch(name);

  /// El nombre de su acento, en su idioma: «Español (Argentina)».
  String get accent => accentDisplayName(locale);

  @override
  bool operator ==(Object other) =>
      other is PodcastVoiceOption &&
      other.id == id &&
      other.name == name &&
      other.locale == locale &&
      other.onDevice == onDevice;

  @override
  int get hashCode => Object.hash(id, name, locale, onDevice);
}

/// Las voces que se ofrecen para un podcast en el idioma `languageCode`, en
/// el orden en que conviene elegirlas: las que se sabe que andan sin conexión
/// primero, después por acento y por nombre. **Las que leen por internet no
/// se ofrecen** (decisiones B y F de F47: todo en el teléfono, nada se sube a
/// la nube por defecto): mandarían el guion a quien hace la voz.
///
/// **El único lugar que sabe de dónde salen las voces del podcast.** Por ahora
/// son las del teléfono, por la interfaz de la narración
/// (`narrationVoicesProvider`); cuando llegue la biblioteca de voces (F47,
/// paso 3), suma acá las suyas con su propio prefijo de id, y la hoja, lo
/// guardado y el audio no cambian.
final podcastVoiceOptionsProvider = FutureProvider.autoDispose
    .family<List<PodcastVoiceOption>, String>((ref, languageCode) async {
      final voices = await ref.watch(narrationVoicesProvider.future);
      final options = [
        for (final voice in voices)
          if (accentLanguage(voice.locale) == languageCode &&
              (_runsOnDevice(voice.name) ?? true))
            PodcastVoiceOption(
              id: PodcastVoiceId.device(
                locale: normalizeAccent(voice.locale),
                name: voice.name,
              ),
              name: voice.name,
              locale: normalizeAccent(voice.locale),
              onDevice: _runsOnDevice(voice.name),
            ),
      ];
      int rank(PodcastVoiceOption o) => (o.onDevice ?? false) ? 0 : 1;
      options.sort((a, b) {
        final byRuns = rank(a).compareTo(rank(b));
        if (byRuns != 0) return byRuns;
        final byAccent = a.accent.compareTo(b.accent);
        return byAccent != 0 ? byAccent : a.name.compareTo(b.name);
      });
      return options;
    });

/// Android nombra sus voces con un código —`es-us-x-esd-local`,
/// `es-us-x-esd-network`—: lo de al final dice si anda sin conexión.
bool? _runsOnDevice(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('network')) return false;
  if (lower.contains('local')) return true;
  return null;
}
