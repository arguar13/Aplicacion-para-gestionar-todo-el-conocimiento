import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_face_view.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «Voces por idioma» (F47, paso 3, decisión L).
Future<void> showVoicesByLanguage(BuildContext context) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => const VoicesByLanguageSheet(),
  );
}

/// La voz elegida para cada idioma: con ella se lee lo que está en ese
/// idioma, aunque el documento esté en otro. Cada una se puede volver a la del
/// teléfono, y la biblioteca de voces está a un toque para elegir otra.
class VoicesByLanguageSheet extends ConsumerWidget {
  const VoicesByLanguageSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final byLanguage = ref.watch(
      narrationSettingsNotifierProvider.select((s) => s.voicesByLanguage),
    );
    final languages = byLanguage.keys.toList()
      ..sort(
        (a, b) => languageNameIn(a, l10n).compareTo(languageNameIn(b, l10n)),
      );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.f47P3SettingsByLanguage,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.f47P3ByLanguageHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (languages.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(
                  l10n.f47P3ByLanguageEmpty,
                  key: const Key('voices-by-language-empty'),
                ),
              ),
            for (final language in languages)
              _LanguageTile(
                language: language,
                profile: voiceProfileOf(byLanguage[language]!),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: Text(l10n.f47P3LibraryTitle),
                  onPressed: () => unawaited(showVoiceLibrary(context)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends ConsumerWidget {
  const _LanguageTile({required this.language, required this.profile});

  final String language;

  /// `null` si es una voz sin conexión que el catálogo ya no tiene.
  final VoiceProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final profile = this.profile;
    final name = languageNameIn(language, l10n);
    return ListTile(
      key: Key('voices-by-language-$language'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: profile == null
          ? const Icon(Icons.smartphone_outlined)
          : VoiceFaceView.of(profile, size: 40),
      title: Text('${name[0].toUpperCase()}${name.substring(1)}'),
      subtitle: Text(
        profile == null ? l10n.f47P3ByLanguageNone : voiceTitle(profile, l10n),
      ),
      trailing: IconButton(
        key: Key('voices-by-language-reset-$language'),
        tooltip: l10n.f47P3ByLanguageReset,
        icon: const Icon(Icons.close_rounded),
        onPressed: () => unawaited(
          ref
              .read(narrationSettingsNotifierProvider.notifier)
              .clearLanguage(language),
        ),
      ),
    );
  }
}
