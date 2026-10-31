/// Cómo se dice cada cosa del podcast (F47) en el idioma de la app: un solo
/// lugar para la hoja, el visor y «Ver petición y fuentes».
library;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/presentation/providers/podcast_voices.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El nombre de [format]: «Conversación».
String podcastFormatLabel(AppLocalizations l10n, PodcastFormat format) =>
    switch (format) {
      PodcastFormat.brief => l10n.f47P6FormatBrief,
      PodcastFormat.lesson => l10n.f47P6FormatLesson,
      PodcastFormat.story => l10n.f47P6FormatStory,
      PodcastFormat.conversation => l10n.f47P6FormatConversation,
    };

/// Quién es [speaker] en [format], para elegir su voz: «Voz 1 · conduce» en
/// la conversación, «Voz» en los demás.
String podcastSpeakerRole(
  AppLocalizations l10n,
  PodcastFormat format,
  PodcastSpeaker speaker,
) {
  if (format.speakerCount == 1) return l10n.f47P6VoiceNarrator;
  return switch (speaker) {
    PodcastSpeaker.a => l10n.f47P6VoiceHost,
    PodcastSpeaker.b => l10n.f47P6VoiceExpert,
  };
}

/// Cómo se nombra [speaker] en la transcripción: «Voz 1», «Voz 2».
String podcastSpeakerName(AppLocalizations l10n, PodcastSpeaker speaker) =>
    switch (speaker) {
      PodcastSpeaker.a => l10n.f47P6SpeakerA,
      PodcastSpeaker.b => l10n.f47P6SpeakerB,
    };

/// El nombre de [voice], la [index]-ésima de la lista: el suyo si es un
/// nombre, «Voz 3» si es un código; con su acento.
String podcastVoiceName(
  AppLocalizations l10n,
  PodcastVoiceOption voice,
  int index,
) {
  final name = voice.nameIsCode
      ? l10n.readAloudVoiceNumber(index + 1)
      : voice.name;
  return '$name · ${voice.accent}';
}

/// Por qué se quitó un tramo.
String podcastDiscardReasonLabel(
  AppLocalizations l10n,
  PodcastDiscardReason reason,
) => switch (reason) {
  PodcastDiscardReason.noCitation => l10n.f47P6DiscardNoCitation,
  PodcastDiscardReason.quoteNotInMaterial => l10n.f47P6DiscardQuote,
  PodcastDiscardReason.numberNotInMaterial => l10n.f47P6DiscardNumber,
};

/// Los minutos de [duration], redondeados y nunca menos de uno.
int podcastMinutes(Duration duration) =>
    (duration.inSeconds / 60).round().clamp(1, 999);

/// El color de cada voz en la transcripción: la primera con el primario del
/// tema y la segunda con el terciario, para que se distingan de un vistazo
/// en claro y en oscuro.
Color podcastSpeakerColor(ColorScheme scheme, PodcastSpeaker speaker) =>
    switch (speaker) {
      PodcastSpeaker.a => scheme.primary,
      PodcastSpeaker.b => scheme.tertiary,
    };

/// El punto de color de una voz, con su número adentro.
class PodcastSpeakerDot extends StatelessWidget {
  const PodcastSpeakerDot({required this.speaker, this.size = 28, super.key});

  final PodcastSpeaker speaker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = podcastSpeakerColor(scheme, speaker);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          speaker == PodcastSpeaker.a ? '1' : '2',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.45,
          ),
        ),
      ),
    );
  }
}
