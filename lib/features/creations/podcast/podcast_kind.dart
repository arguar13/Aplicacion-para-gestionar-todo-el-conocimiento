import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_generator.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_labels.dart';
import 'package:sinapsis/features/creations/podcast/presentation/widgets/podcast_viewer.dart';
import 'package:sinapsis/features/creations/podcast/presentation/widgets/podcast_voices_section.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Quien escribe el guion de los podcasts: lo que suma
/// `creationGeneratorsProvider`.
final podcastGeneratorProvider = Provider<CreationGenerator>(
  (ref) => const PodcastGenerator(),
);

/// El podcast en Repasar (F47, paso 6): la tarjeta y la hoja de fábrica
/// (`podcastKindSpecBase`) con «Elegí las voces» y su visor. Lo que suma
/// `creationKindSpecsProvider`.
final podcastKindSpecProvider = Provider<CreationKindSpec>(
  (ref) => podcastKindSpec(),
);

/// Lo de [podcastKindSpecProvider], suelto: lo que usan las pruebas.
CreationKindSpec podcastKindSpec() =>
    defaultCreationKindSpec(StudyCreationKind.podcast).copyWith(
      optionsBuilder: (context, options) =>
          PodcastVoicesSection(context: options),
      requestLines: podcastRequestLines,
      viewerBuilder: (context, creation) =>
          PodcastViewer(key: ValueKey(creation.id), creation: creation),
    );

/// Las voces elegidas, para «Ver petición y fuentes»: quién habla y con qué
/// voz —el acento y el nombre, si tiene uno—.
List<(String, String)> podcastRequestLines(
  AppLocalizations l10n,
  Map<String, Object?> options,
) {
  final format = PodcastFormat.of(options);
  return [
    for (final choice in PodcastCast.of(options, format))
      (
        podcastSpeakerRole(l10n, format, choice.speaker),
        _voiceName(l10n, choice.voiceId),
      ),
  ];
}

String _voiceName(AppLocalizations l10n, String? id) {
  if (id == null) return l10n.f47P6VoiceDefault;
  final device = PodcastVoiceId.parseDevice(id);
  if (device == null) return id;
  final accent = accentDisplayName(device.locale);
  final code = RegExp(
    r'^[a-z]{2,3}[-_][a-z]{2,3}([-_]|$)',
    caseSensitive: false,
  ).hasMatch(device.name);
  return code ? accent : '${device.name} · $accent';
}
