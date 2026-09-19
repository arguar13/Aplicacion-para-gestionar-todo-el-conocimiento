import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Idioma, tema, modelo de transcripción, copia de seguridad y bloqueo de la
/// bóveda, todo en un solo lugar.
///
/// Antes eran seis de los nueve íconos amontonados en el AppBar de la
/// biblioteca — ver la decisión 22 en docs/arquitectura.md—. Son ajustes que
/// se tocan de vez en cuando, no navegación que se use todo el tiempo, así
/// que tiene sentido que compartan una sola pantalla en vez de competir por
/// un lugar en la barra principal.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _localeCycle = <Locale?>[null, Locale('es'), Locale('en')];
  static const _themeCycle = [
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final localePreference = ref.watch(localeNotifierProvider);
    final effectiveLocale = ref.watch(effectiveLocaleProvider);
    final themeMode = ref.watch(themeModeNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsSection(
            title: l10n.settingsAppearanceSection,
            children: [
              ListTile(
                leading: const Icon(Icons.translate_outlined),
                title: Text(l10n.languageTooltip),
                subtitle: Text(effectiveLocale.languageCode.toUpperCase()),
                onTap: () {
                  final next =
                      _localeCycle[(_localeCycle.indexOf(localePreference) +
                              1) %
                          _localeCycle.length];
                  ref.read(localeNotifierProvider.notifier).setLocale(next);
                },
              ),
              ListTile(
                leading: Icon(_themeIcon(themeMode)),
                title: Text(l10n.themeModeTooltip),
                subtitle: Text(_themeLabel(l10n, themeMode)),
                onTap: () {
                  final next =
                      _themeCycle[(_themeCycle.indexOf(themeMode) + 1) %
                          _themeCycle.length];
                  ref
                      .read(themeModeNotifierProvider.notifier)
                      .setThemeMode(next);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SettingsSection(
            title: l10n.settingsAiSection,
            children: [
              ListTile(
                leading: const Icon(Icons.mic_none_outlined),
                title: Text(l10n.libraryTranscriptionModelTooltip),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.transcriptionModel),
              ),
              ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: Text(l10n.relationsEmbeddingModelTooltip),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.embeddingModel),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SettingsSection(
            title: l10n.settingsVaultSection,
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text(l10n.libraryVaultBackupTooltip),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.vaultBackup),
              ),
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: Text(l10n.duplicatesSettingsTooltip),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.duplicates),
              ),
              ListTile(
                leading: const Icon(Icons.spellcheck_outlined),
                title: Text(l10n.vocabularySettingsTooltip),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.vocabulary),
              ),
              ListTile(
                leading: const Icon(Icons.link_off),
                title: Text(l10n.brokenLinksTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.brokenLinks),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SettingsSection(
            children: [
              ListTile(
                leading: Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  l10n.lockVaultTooltip,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () =>
                    ref.read(vaultSessionControllerProvider.notifier).lock(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _themeIcon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto,
    ThemeMode.light => Icons.light_mode,
    ThemeMode.dark => Icons.dark_mode,
  };

  String _themeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
    ThemeMode.system => l10n.themeModeSystem,
    ThemeMode.light => l10n.themeModeLight,
    ThemeMode.dark => l10n.themeModeDark,
  };
}

/// Un grupo de ajustes relacionados, con un encabezado opcional — mismo
/// contenedor redondeado que ya usan las tarjetas de la biblioteca
/// (`surfaceContainerLow`, radio 16), para agrupar sin volver a amontonar.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title!,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        // `Card` y no un `Container` con decoración: `ListTile` pinta su
        // color de fondo y sus efectos de tinta sobre el `Material` más
        // cercano, y un `Container` decorado no es un `Material` —los
        // dejaría invisibles—. `Card` ya trae el mismo estilo
        // (`surfaceContainerLow`, radio 16, borde sutil) definido en
        // `app_theme.dart`, así que alcanza con no ponerle margen.
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
