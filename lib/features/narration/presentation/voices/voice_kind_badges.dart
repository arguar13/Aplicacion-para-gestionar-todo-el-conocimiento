import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que el reproductor dice de la voz que lee, si es propia (F47, paso 4):
/// «Voz clonada» o «Voz creada», y «En la nube» si lo que se lee sale a
/// ElevenLabs y gasta su cuota. Con una voz del teléfono o del catálogo, nada.
List<String> voiceKindBadges(VoiceProfile voice, AppLocalizations l10n) => [
  if (voice.origin == VoiceOrigin.cloned) l10n.f47P4BadgeCloned,
  if (voice.origin == VoiceOrigin.created) l10n.f47P4BadgeCreated,
  if (voice.inCloud) l10n.f47P4BadgeCloud,
];

/// Las marcas de la voz que lee ahora, en una línea que baja si no entra. La
/// lee el lector de pantalla como una frase: «Voz clonada, En la nube».
class CurrentVoiceBadges extends ConsumerWidget {
  const CurrentVoiceBadges({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(currentVoiceProfileProvider);
    if (voice == null) return const SizedBox.shrink();
    return VoiceKindBadgeRow(voice: voice);
  }
}

class VoiceKindBadgeRow extends StatelessWidget {
  const VoiceKindBadgeRow({required this.voice, super.key});

  final VoiceProfile voice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final badges = voiceKindBadges(voice, l10n);
    if (badges.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall;
    return Semantics(
      key: const Key('voice-kind-badges'),
      label: badges.join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final badge in badges)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: badge == l10n.f47P4BadgeCloud
                      ? scheme.tertiaryContainer
                      : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Text(
                    badge,
                    style: style?.copyWith(
                      color: badge == l10n.f47P4BadgeCloud
                          ? scheme.onTertiaryContainer
                          : scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
