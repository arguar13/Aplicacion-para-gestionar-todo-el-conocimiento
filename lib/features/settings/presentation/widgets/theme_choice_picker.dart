import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El nombre de [choice], en el idioma de la app.
String themeChoiceLabel(AppLocalizations l10n, AppThemeChoice choice) =>
    switch (choice) {
      AppThemeChoice.system => l10n.themeModeSystem,
      AppThemeChoice.light => l10n.themeModeLight,
      AppThemeChoice.dark => l10n.themeModeDark,
      AppThemeChoice.sepia => l10n.themeSepia,
      AppThemeChoice.night => l10n.themeNight,
      AppThemeChoice.forest => l10n.themeForest,
      AppThemeChoice.ocean => l10n.themeOcean,
      AppThemeChoice.lavender => l10n.themeLavender,
      AppThemeChoice.graphite => l10n.themeGraphite,
    };

/// «Cambiar tema» (F39, decisión E): el tema de ahora y, debajo, una muestra
/// con los colores de cada uno —el del sistema, el claro, el oscuro y los seis
/// con nombre— para elegir viendo. Tocar una muestra aplica ese tema al
/// instante en toda la app y lo guarda.
class ThemeChoicePicker extends ConsumerWidget {
  const ThemeChoicePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(themeChoiceNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(_icon(current)),
          title: Text(l10n.themeModeTooltip),
          subtitle: Text(themeChoiceLabel(l10n, current)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final choice in AppThemeChoice.values)
                _Swatch(
                  choice: choice,
                  label: themeChoiceLabel(l10n, choice),
                  selected: choice == current,
                  onTap: () => ref
                      .read(themeChoiceNotifierProvider.notifier)
                      .setChoice(choice),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _icon(AppThemeChoice choice) => switch (choice) {
    AppThemeChoice.system => Icons.brightness_auto,
    AppThemeChoice.light => Icons.light_mode,
    AppThemeChoice.dark => Icons.dark_mode,
    _ => Icons.palette_outlined,
  };
}

/// La muestra de un tema: una pantallita con los colores del tema —fondo,
/// tarjeta, texto y los dos acentos— y su nombre abajo. Los colores son los
/// del tema que muestra, no los del que está puesto.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.choice,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const _width = 88.0;
  static const _height = 60.0;

  final AppThemeChoice choice;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: Key('theme-swatch-${choice.name}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: _width,
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    key: Key('theme-swatch-preview-${choice.name}'),
                    width: _width,
                    height: _height,
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.outline,
                        width: selected ? 3 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        for (final preview in choice.previews)
                          Expanded(child: _MiniScreen(theme: preview)),
                      ],
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El fondo del tema [theme] con una tarjeta encima —su superficie—, dos
/// renglones de texto y los puntos de sus dos acentos.
class _MiniScreen extends StatelessWidget {
  const _MiniScreen({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;

    Widget bar(Color color, double fraction) => FractionallySizedBox(
      widthFactor: fraction,
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    Widget dot(Color color) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(scheme.onSurface, 1),
                const SizedBox(height: 3),
                bar(scheme.onSurfaceVariant, 0.65),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(scheme.primary),
                    const SizedBox(width: 3),
                    dot(scheme.secondary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
