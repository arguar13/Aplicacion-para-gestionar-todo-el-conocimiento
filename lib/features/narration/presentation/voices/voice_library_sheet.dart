import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/library/presentation/widgets/list_controls.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_filter.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_card.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_filters_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la biblioteca de voces (F47, paso 3), desde abajo y casi a pantalla
/// completa. Es la entrada única: la abren el reproductor —«la cara de la
/// voz»—, el reproductor de los visores de Repasar y Ajustes.
Future<void> showVoiceLibrary(BuildContext context) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => const VoiceLibrarySheet(),
  );
}

/// La biblioteca de voces (F47, paso 3, capturas 10 a 13): las pestañas
/// **Todas · Favoritas · Mías**, «Te puede interesar» arriba de Todas, y
/// Filtrar.
///
/// Tocar una voz que ya puede leer la elige para leer, en el acto; una sin
/// conexión se baja solo con su botón. Las voces se ordenan por idioma: el
/// de lo que se lee primero, después el de la app, después los demás; y en
/// cada idioma, las neuronales antes que las del teléfono.
class VoiceLibrarySheet extends ConsumerStatefulWidget {
  const VoiceLibrarySheet({super.key});

  @override
  ConsumerState<VoiceLibrarySheet> createState() => _VoiceLibrarySheetState();
}

class _VoiceLibrarySheetState extends ConsumerState<VoiceLibrarySheet>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: VoiceLibraryTab.values.length,
    vsync: this,
  );
  final _scrolls = [for (final _ in VoiceLibraryTab.values) ScrollController()];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  VoiceLibraryTab get _tab => VoiceLibraryTab.values[_tabs.index];

  Future<void> _openFilters() async {
    final tab = _tab;
    final showResults = await showListFiltersSheet(
      context,
      builder: (_) => VoiceFiltersSheet(tab: tab),
    );
    // Cerrado con el pie, la lista se ve desde arriba.
    final scroll = _scrolls[tab.index];
    if (showResults && mounted && scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final filterCount = ref.watch(voiceFilterProvider.select((f) => f.count));
    final current = ref.watch(currentVoiceProfileProvider);

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            // `Wrap` y no una fila: con la letra al doble, Filtrar baja a su
            // propia línea en vez de apretar el título.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.f47P3LibraryTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Badge(
                  label: Text('$filterCount'),
                  isLabelVisible: filterCount > 0,
                  child: TextButton.icon(
                    key: const Key('voice-library-filter'),
                    icon: const Icon(Icons.tune),
                    label: Text(l10n.f47P3Filter),
                    onPressed: () => unawaited(_openFilters()),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              current == null
                  ? l10n.f47P3NowReadingSystem
                  : l10n.f47P3NowReading(voiceName(current, l10n)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: [
              Tab(text: l10n.f47P3TabAll),
              Tab(text: l10n.f47P3TabFavorites),
              Tab(text: l10n.f47P3TabMine),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final tab in VoiceLibraryTab.values)
                  _VoiceList(tab: tab, scroll: _scrolls[tab.index]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Las voces de una pestaña, con lo que pasa Filtrar.
class _VoiceList extends ConsumerWidget {
  const _VoiceList({required this.tab, required this.scroll});

  final VoiceLibraryTab tab;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final library = ref.watch(voiceLibraryProvider);
    final filter = ref.watch(voiceFilterProvider);
    final favorites = ref.watch(voiceFavoritesProvider);
    final installed = ref.watch(installedVoiceIdsProvider);
    final reading = ref.watch(readingLanguageProvider);
    final chosen = ref.watch(narrationSettingsNotifierProvider);
    final appLanguage = Localizations.localeOf(context).languageCode;

    return library.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Message(text: l10n.readAloudNoVoices),
      data: (all) {
        final ordered = orderVoices(
          all,
          readingLanguage: reading,
          appLanguage: appLanguage,
        );
        final shown = voicesIn(
          ordered,
          tab: tab,
          filter: filter,
          favorites: favorites,
        );
        final recommended = tab == VoiceLibraryTab.all && filter.isEmpty
            ? recommendedVoices(all, language: reading, installed: installed)
            : const <VoiceProfile>[];
        final missingInLanguage =
            recommended.isNotEmpty &&
            !all.any(
              (voice) =>
                  voice.language == reading &&
                  voice.origin == VoiceOrigin.offline &&
                  installed.contains(voice.id),
            );

        // Una voz queda elegida para su idioma (decisión L): si no es el de
        // lo que se lee, lo dice —no traduce nada, lee cuando el texto esté
        // en su idioma—.
        void select(VoiceProfile? voice) {
          unawaited(
            ref
                .read(readAloudControllerProvider.notifier)
                .setVoice(voice?.voice),
          );
          if (voice == null || reading == null || voice.language == reading) {
            return;
          }
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  l10n.f47P3ChosenForLanguage(
                    voiceName(voice, l10n),
                    languageNameIn(voice.language, l10n),
                  ),
                ),
              ),
            );
        }

        // Elegida: la de su idioma. Sin idioma que se lea, «La voz del
        // sistema» es la elegida si no se eligió ninguna.
        Widget card(VoiceProfile voice) => VoiceCard(
          voice: voice,
          selected: chosen.voicesByLanguage[voice.language] == voice.voice,
          onSelect: () => select(voice),
        );

        if (shown.isEmpty && tab == VoiceLibraryTab.mine && filter.isEmpty) {
          return _Message(
            key: const Key('voice-library-mine-empty'),
            title: l10n.f47P3MineEmptyTitle,
            text: l10n.f47P3MineEmpty,
            icon: Icons.record_voice_over_outlined,
          );
        }
        if (shown.isEmpty &&
            tab == VoiceLibraryTab.favorites &&
            filter.isEmpty) {
          return _Message(
            key: const Key('voice-library-favorites-empty'),
            text: l10n.f47P3FavoritesEmpty,
            icon: Icons.favorite_border_rounded,
          );
        }

        return ListView(
          key: Key('voice-library-list-${tab.name}'),
          controller: scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (recommended.isNotEmpty) ...[
              _SectionTitle(
                l10n.f47P3Recommended,
                hint: l10n.f47P3RecommendedHint(languageNameIn(reading!, l10n)),
              ),
              if (missingInLanguage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    l10n.f47P3NoOfflineVoiceFor(languageNameIn(reading, l10n)),
                    key: const Key('voice-library-missing-language'),
                  ),
                ),
              for (final voice in recommended)
                KeyedSubtree(
                  key: Key('voice-recommended-${voice.id}'),
                  child: card(voice),
                ),
              _SectionTitle(l10n.f47P3AllVoices),
            ],
            if (tab == VoiceLibraryTab.all && filter.isEmpty)
              _SystemVoiceTile(
                selected: reading == null
                    ? chosen.voice == null
                    : !chosen.voicesByLanguage.containsKey(reading),
                onTap: () => select(null),
              ),
            if (shown.isEmpty)
              _Message(text: l10n.f47P3NothingMatches, compact: true)
            else
              for (final voice in shown) card(voice),
          ],
        );
      },
    );
  }
}

/// El orden de la lista: primero el idioma de lo que se lee, después el de la
/// app y después los demás por su código; en cada idioma, las neuronales
/// antes que las del teléfono, y dentro de eso, como vienen —el catálogo ya
/// trae sus voces en orden—.
@visibleForTesting
List<VoiceProfile> orderVoices(
  List<VoiceProfile> voices, {
  required String? readingLanguage,
  required String appLanguage,
}) {
  int languageRank(VoiceProfile voice) {
    if (voice.language == readingLanguage) return 0;
    if (voice.language == appLanguage) return 1;
    return 2;
  }

  final indexed = voices.indexed.toList()
    ..sort((a, b) {
      final (ai, av) = a;
      final (bi, bv) = b;
      final byRank = languageRank(av).compareTo(languageRank(bv));
      if (byRank != 0) return byRank;
      final byLanguage = av.language.compareTo(bv.language);
      if (byLanguage != 0) return byLanguage;
      final byOrigin = _originRank(av).compareTo(_originRank(bv));
      return byOrigin != 0 ? byOrigin : ai.compareTo(bi);
    });
  return [for (final (_, voice) in indexed) voice];
}

int _originRank(VoiceProfile voice) => switch (voice.origin) {
  VoiceOrigin.created || VoiceOrigin.cloned => 0,
  VoiceOrigin.offline => 1,
  VoiceOrigin.device => 2,
};

/// «La del teléfono»: la voz que tenga elegida el sistema.
class _SystemVoiceTile extends StatelessWidget {
  const _SystemVoiceTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: const Key('read-aloud-system-voice'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(l10n.readAloudSystemVoice),
      subtitle: Text(l10n.readAloudSystemVoiceHint),
      selected: selected,
      onTap: onTap,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
          if (hint case final hint?)
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Una pestaña sin voces: qué va a haber y cómo llegar.
class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    this.title,
    this.icon,
    this.compact = false,
    super.key,
  });

  final String text;
  final String? title;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
          ],
          if (title case final title?) ...[
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    if (compact) return body;
    // Con la letra al doble, el mensaje se desplaza en vez de desbordar.
    return SingleChildScrollView(child: body);
  }
}
