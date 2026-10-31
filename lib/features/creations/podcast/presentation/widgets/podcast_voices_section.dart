import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_labels.dart';
import 'package:sinapsis/features/creations/podcast/presentation/providers/podcast_voices.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Elegí las voces» en la hoja del podcast (F47, punto 5 del plan): una voz
/// por persona que habla —una, o dos en la conversación—, de las del idioma
/// elegido arriba (decisión L: la voz sigue al idioma).
///
/// Lo elegido se guarda como dato en las opciones
/// ([PodcastOptionKeys.voices]): el id de cada voz y quién habla. Al abrir, y
/// cada vez que cambian el idioma, el formato o las voces que hay, se ajusta
/// ([PodcastCast.fit]): una voz de otro idioma se suelta, y quien no tiene voz
/// recibe una del idioma —en la conversación, dos distintas si hay—.
class PodcastVoicesSection extends ConsumerStatefulWidget {
  const PodcastVoicesSection({required this.context, super.key});

  /// Las opciones de la hoja, cómo cambiarlas y el idioma elegido.
  final CreationOptionsContext context;

  @override
  ConsumerState<PodcastVoicesSection> createState() =>
      _PodcastVoicesSectionState();
}

class _PodcastVoicesSectionState extends ConsumerState<PodcastVoicesSection> {
  /// Lo último que se pidió guardar al ajustar, para no pedirlo dos veces
  /// mientras la hoja se vuelve a dibujar.
  List<PodcastVoiceChoice>? _fitted;

  CreationOptionsContext get _options => widget.context;

  PodcastFormat get _format => PodcastFormat.of(_options.options);

  List<PodcastVoiceChoice> get _cast =>
      PodcastCast.of(_options.options, _format);

  void _save(List<PodcastVoiceChoice> cast) =>
      _options.set(PodcastOptionKeys.voices, PodcastCast.toOptions(cast));

  /// Ajusta lo guardado a las voces que hay, después de dibujar: cambiar las
  /// opciones mientras se dibuja la hoja no se puede.
  void _fit(List<PodcastVoiceOption> voices) {
    final cast = _cast;
    final fitted = PodcastCast.fit(
      cast,
      available: [for (final v in voices) v.id],
    );
    if (listEquals(fitted, cast) || listEquals(fitted, _fitted)) return;
    _fitted = fitted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _save(fitted);
    });
  }

  void _choose(PodcastSpeaker speaker, String? voiceId) => _save([
    for (final choice in _cast)
      if (choice.speaker == speaker)
        PodcastVoiceChoice(speaker: speaker, voiceId: voiceId)
      else
        choice,
  ]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final language = _options.languageCode;
    final voices = ref.watch(podcastVoiceOptionsProvider(language)).valueOrNull;
    if (voices != null) _fit(voices);
    final cast = _cast;
    final conversation = _format.speakerCount == 2;
    final same =
        conversation &&
        cast.length == 2 &&
        cast[0].voiceId != null &&
        cast[0].voiceId == cast[1].voiceId;
    // La misma voz para las dos personas: un aviso para cambiarla si hay
    // otra; si es la única del idioma, solo se dice.
    final note = voices == null
        ? null
        : voices.isEmpty
        ? l10n.f47P6VoicesNone
        : same && voices.length >= 2
        ? l10n.f47P6VoicesSame
        : same
        ? l10n.f47P6VoicesOnlyOne
        : null;
    final warn = same && (voices?.length ?? 0) >= 2;
    return Column(
      key: const Key('podcast-voices'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CreationSectionLabel(conversation ? l10n.f47P6Voices : l10n.f47P6Voice),
        Text(
          l10n.f47P6VoicesHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final choice in cast)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _VoicePicker(
              key: ValueKey('podcast-voice-${choice.speaker.storageKey}'),
              label: podcastSpeakerRole(l10n, _format, choice.speaker),
              choice: choice,
              voices: voices ?? const [],
              onChanged: (id) => _choose(choice.speaker, id),
            ),
          ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(
            note,
            key: const Key('podcast-voices-note'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: warn ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// La voz de una persona: quién es y la voz elegida, que abre la lista.
class _VoicePicker extends StatelessWidget {
  const _VoicePicker({
    required this.label,
    required this.choice,
    required this.voices,
    required this.onChanged,
    super.key,
  });

  final String label;
  final PodcastVoiceChoice choice;
  final List<PodcastVoiceOption> voices;
  final ValueChanged<String?> onChanged;

  static const _defaultId = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final names = {
      for (final (i, voice) in voices.indexed)
        voice.id: podcastVoiceName(l10n, voice, i),
    };
    final current = choice.voiceId == null
        ? l10n.f47P6VoiceDefault
        : names[choice.voiceId] ?? l10n.f47P6VoiceDefault;
    // «La del teléfono» va con un id vacío: un menú que devuelve `null` se
    // toma como cerrado sin elegir. Para el lector de pantalla, un solo botón
    // que dice de quién es y cuál quedó.
    return MergeSemantics(
      child: Semantics(
        label: '$label: $current',
        child: PopupMenuButton<String>(
          initialValue: choice.voiceId ?? _defaultId,
          tooltip: label,
          onSelected: (id) => onChanged(id == _defaultId ? null : id),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              key: const ValueKey('podcast-voice-option-default'),
              value: _defaultId,
              child: Text(l10n.f47P6VoiceDefault),
            ),
            for (final voice in voices)
              PopupMenuItem<String>(
                key: ValueKey('podcast-voice-option-${voice.id}'),
                value: voice.id,
                child: Text(names[voice.id]!),
              ),
          ],
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  PodcastSpeakerDot(speaker: choice.speaker),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(current, style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
