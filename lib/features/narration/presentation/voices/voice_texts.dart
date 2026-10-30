import 'package:flutter/material.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se nombra cada rasgo de una voz en la biblioteca (F47, paso 3).
extension VoicePurposeText on VoicePurpose {
  String label(AppLocalizations l10n) => switch (this) {
    VoicePurpose.narrate => l10n.f47P3PurposeNarrate,
    VoicePurpose.inform => l10n.f47P3PurposeInform,
    VoicePurpose.learn => l10n.f47P3PurposeLearn,
    VoicePurpose.converse => l10n.f47P3PurposeConverse,
    VoicePurpose.relax => l10n.f47P3PurposeRelax,
  };

  /// El ícono de para qué es ideal, en la tarjeta.
  IconData get icon => switch (this) {
    VoicePurpose.narrate => Icons.auto_stories_outlined,
    VoicePurpose.inform => Icons.campaign_outlined,
    VoicePurpose.learn => Icons.school_outlined,
    VoicePurpose.converse => Icons.forum_outlined,
    VoicePurpose.relax => Icons.spa_outlined,
  };
}

extension VoiceTimbreText on VoiceTimbre {
  String label(AppLocalizations l10n) => switch (this) {
    VoiceTimbre.deep => l10n.f47P3TimbreDeep,
    VoiceTimbre.clear => l10n.f47P3TimbreClear,
    VoiceTimbre.velvety => l10n.f47P3TimbreVelvety,
    VoiceTimbre.bright => l10n.f47P3TimbreBright,
  };
}

extension VoiceStyleText on VoiceStyle {
  String label(AppLocalizations l10n) => switch (this) {
    VoiceStyle.warm => l10n.f47P3StyleWarm,
    VoiceStyle.calm => l10n.f47P3StyleCalm,
    VoiceStyle.expressive => l10n.f47P3StyleExpressive,
    VoiceStyle.energetic => l10n.f47P3StyleEnergetic,
    VoiceStyle.authoritative => l10n.f47P3StyleAuthoritative,
  };
}

extension VoiceGenderText on VoiceGender {
  String label(AppLocalizations l10n) => switch (this) {
    VoiceGender.female => l10n.f47P3GenderFemale,
    VoiceGender.male => l10n.f47P3GenderMale,
  };
}

extension VoiceAgeText on VoiceAge {
  String label(AppLocalizations l10n) => switch (this) {
    VoiceAge.young => l10n.f47P3AgeYoung,
    VoiceAge.adult => l10n.f47P3AgeAdult,
    VoiceAge.senior => l10n.f47P3AgeSenior,
  };
}

extension VoiceQualityText on VoiceQuality {
  String label(AppLocalizations l10n) => switch (this) {
    VoiceQuality.high => l10n.f47P3QualityHigh,
    VoiceQuality.medium => l10n.f47P3QualityMedium,
    VoiceQuality.low => l10n.f47P3QualityLow,
  };
}

/// El nombre de una voz: el suyo, o «Voz 2» si solo tiene un código.
String voiceName(VoiceProfile voice, AppLocalizations l10n) =>
    voice.name ?? l10n.readAloudVoiceNumber(voice.number!);

/// El nombre con la bandera de su acento: «Daniela 🇦🇷».
String voiceTitle(VoiceProfile voice, AppLocalizations l10n) {
  final flag = accentFlag(voice.locale);
  final name = voiceName(voice, l10n);
  return flag == null ? name : '$name $flag';
}

/// La línea de rasgos de la tarjeta: «ES · Mujer · Cálido · Calidad alta»,
/// con lo que la voz dice y nada más.
String voiceTraitsLine(VoiceProfile voice, AppLocalizations l10n) => [
  voice.language.toUpperCase(),
  if (accentRegionName(voice.locale) case final region?) region,
  if (voice.gender case final gender?) gender.label(l10n),
  if (voice.age case final age?) age.label(l10n),
  if (voice.timbre case final timbre?) timbre.label(l10n),
  for (final style in VoiceStyle.values)
    if (voice.styles.contains(style)) style.label(l10n),
  if (voice.quality case final quality?) quality.label(l10n),
].join(' · ');

/// De dónde es la voz: «Teléfono», «Sin conexión · 110 MB»…
String voiceOriginLine(
  VoiceProfile voice,
  AppLocalizations l10n, {
  required bool ready,
}) {
  final package = ready ? null : voice.offline?.package;
  return switch (voice.origin) {
    VoiceOrigin.device when voice.needsInternet => l10n.f47P3OriginDeviceOnline,
    VoiceOrigin.device => l10n.f47P3OriginDevice,
    // Ya bajada —o sin paquete que bajar—: solo de dónde es.
    VoiceOrigin.offline when package == null => l10n.f47P3OriginOffline,
    VoiceOrigin.offline when package!.family == OfflineVoiceFamily.kokoro =>
      l10n.f47P3OriginKokoroSize(
        formatFileSize(package.bytes, l10n.localeName),
        _kokoroVoices,
      ),
    VoiceOrigin.offline => l10n.f47P3OriginOfflineSize(
      formatFileSize(package!.bytes, l10n.localeName),
    ),
    VoiceOrigin.cloned => l10n.f47P3OriginCloned,
    VoiceOrigin.created => l10n.f47P3OriginCreated,
  };
}

final int _kokoroVoices = OfflineVoiceCatalog.voices
    .where((voice) => voice.package == OfflineVoiceCatalog.kokoro)
    .length;

/// Cuántas voces trae el paquete de Kokoro.
int get kokoroVoiceCount => _kokoroVoices;

/// El ícono de dónde es una voz.
IconData voiceOriginIcon(VoiceOrigin origin) => switch (origin) {
  VoiceOrigin.device => Icons.smartphone_outlined,
  VoiceOrigin.offline => Icons.offline_bolt_outlined,
  VoiceOrigin.cloned => Icons.content_copy_outlined,
  VoiceOrigin.created => Icons.auto_awesome_outlined,
};

/// El nombre de un idioma en el idioma de la app: «español», «inglés». Se
/// usa en frases —«Voces en español»—; los que la app no sabe nombrar, en
/// su propio idioma.
String languageNameIn(String language, AppLocalizations l10n) {
  final names = l10n.localeName.startsWith('es') ? _spanish : _english;
  return names[language] ?? languageDisplayName(language);
}

const _spanish = {
  'es': 'español',
  'en': 'inglés',
  'pt': 'portugués',
  'fr': 'francés',
  'it': 'italiano',
  'de': 'alemán',
  'hi': 'hindi',
  'zh': 'chino',
  'ja': 'japonés',
  'ru': 'ruso',
  'ar': 'árabe',
  'ca': 'catalán',
  'nl': 'neerlandés',
  'ko': 'coreano',
  'el': 'griego',
};

const _english = {
  'es': 'Spanish',
  'en': 'English',
  'pt': 'Portuguese',
  'fr': 'French',
  'it': 'Italian',
  'de': 'German',
  'hi': 'Hindi',
  'zh': 'Chinese',
  'ja': 'Japanese',
  'ru': 'Russian',
  'ar': 'Arabic',
  'ca': 'Catalan',
  'nl': 'Dutch',
  'ko': 'Korean',
  'el': 'Greek',
};
