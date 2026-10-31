import 'package:flutter/material.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_face.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_face_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo común de las pantallas de clonar y crear una voz (F47, paso 4).

/// Una sección de la presentación: un ícono, un título y su explicación.
class IntroSection extends StatelessWidget {
  const IntroSection({
    required this.icon,
    required this.title,
    required this.text,
    super.key,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
                const SizedBox(height: 2),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un aviso en una tarjeta de color: un error, o algo a tener en cuenta.
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    required this.text,
    this.error = false,
    this.action,
    super.key,
  });

  final String text;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: error ? scheme.errorContainer : scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                text,
                style: TextStyle(
                  color: error
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
              ),
            ),
            if (action case final action?) ...[
              const SizedBox(height: 8),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// La cara que va a tener la voz, con «Otra cara»: cambia el dibujo, no la
/// voz.
class FacePicker extends StatelessWidget {
  const FacePicker({
    required this.faceKey,
    required this.name,
    required this.onNext,
    super.key,
  });

  final String faceKey;
  final String name;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        VoiceFaceView(
          face: VoiceFace.of(faceKey, name.trim().isEmpty ? '?' : name),
          size: 64,
        ),
        OutlinedButton.icon(
          key: const Key('my-voice-next-face'),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.f47P4OtherFace),
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Los idiomas y acentos en que puede leer una voz clonada o creada en la
/// nube: los de la app, con su acento.
const cloudVoiceLocales = [
  'es-AR',
  'es-ES',
  'es-MX',
  'es-CO',
  'es-CL',
  'en-US',
  'en-GB',
  'pt-BR',
  'pt-PT',
  'fr-FR',
  'it-IT',
  'de-DE',
];

/// Elegir un idioma y acento entre [locales], con fichas que bajan de línea:
/// cada uno en su propio idioma, como en la biblioteca («Español
/// (Argentina)», «English (United Kingdom)»).
class LocaleChips extends StatelessWidget {
  const LocaleChips({
    required this.locales,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<String> locales;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final locale in locales)
          ChoiceChip(
            key: Key('my-voice-locale-$locale'),
            label: Text(accentDisplayName(locale)),
            selected: locale == selected,
            onSelected: (_) => onSelected(locale),
          ),
      ],
    );
  }
}
