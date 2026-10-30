import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/library/presentation/widgets/list_controls.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_filter.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Filtrar de la biblioteca de voces (F47, paso 3): el marco común de los
/// filtros de la app (`ListFiltersSheet`), con «Limpiar filtros» arriba y
/// «Ver N voces» abajo, y cada filtro aplicándose al tocarlo (decisión K).
///
/// Cuenta las voces de la pestaña [tab], la que se va a ver al cerrarlo. Solo
/// ofrece lo que alguna voz dice (ver `VoiceFilterOptions`): el tono, el
/// timbre y la edad aparecen con las voces creadas; mientras tanto, una nota
/// dice por qué no están.
class VoiceFiltersSheet extends ConsumerWidget {
  const VoiceFiltersSheet({required this.tab, super.key});

  final VoiceLibraryTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final filter = ref.watch(voiceFilterProvider);
    final voices = ref.watch(voiceLibraryProvider);
    final favorites = ref.watch(voiceFavoritesProvider);
    final all = voices.valueOrNull ?? const [];
    final options = VoiceFilterOptions.of(all, filter);
    final results = voices.whenData(
      (all) =>
          voicesIn(all, tab: tab, filter: filter, favorites: favorites).length,
    );

    void update(VoiceFilter Function(VoiceFilter) change) =>
        ref.read(voiceFilterProvider.notifier).update(change);

    Widget section<T>(
      String title,
      List<T> values,
      Set<T> chosen,
      String Function(T) label,
      VoiceFilter Function(VoiceFilter, T) toggle,
    ) {
      if (values.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionLabel(title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in values)
                  FilterChip(
                    key: Key('voice-filter-$value'),
                    label: Text(label(value)),
                    selected: chosen.contains(value),
                    onSelected: (_) => update((f) => toggle(f, value)),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    final unknownTraits =
        options.purposes.isEmpty &&
        options.timbres.isEmpty &&
        options.styles.isEmpty &&
        options.ages.isEmpty;

    return ListFiltersSheet(
      results: results,
      narrowed: !filter.isEmpty,
      onClear: filter.isEmpty
          ? null
          : () => ref.read(voiceFilterProvider.notifier).state =
                const VoiceFilter(),
      texts: FilterResultsTexts(
        counting: l10n.f47P3CountingVoices,
        none: l10n.f47P3NoVoicesMatch,
        showAll: l10n.f47P3ShowAllVoices,
        show: l10n.f47P3ShowVoices,
      ),
      children: [
        section(
          l10n.f47P3FilterLanguage,
          options.languages,
          filter.languages,
          languageDisplayName,
          (f, v) => f.toggleLanguage(v),
        ),
        section(
          l10n.f47P3FilterAccent,
          options.accents,
          filter.accents,
          (accent) => accentRegionName(accent) ?? accent,
          (f, v) => f.toggleAccent(v),
        ),
        section(
          l10n.f47P3FilterPurpose,
          options.purposes,
          filter.purposes,
          (v) => v.label(l10n),
          (f, v) => f.togglePurpose(v),
        ),
        section(
          l10n.f47P3FilterTimbre,
          options.timbres,
          filter.timbres,
          (v) => v.label(l10n),
          (f, v) => f.toggleTimbre(v),
        ),
        section(
          l10n.f47P3FilterStyle,
          options.styles,
          filter.styles,
          (v) => v.label(l10n),
          (f, v) => f.toggleStyle(v),
        ),
        section(
          l10n.f47P3FilterGender,
          options.genders,
          filter.genders,
          (v) => v.label(l10n),
          (f, v) => f.toggleGender(v),
        ),
        section(
          l10n.f47P3FilterAge,
          options.ages,
          filter.ages,
          (v) => v.label(l10n),
          (f, v) => f.toggleAge(v),
        ),
        if (unknownTraits)
          Text(
            l10n.f47P3FilterUnknownTraits,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
