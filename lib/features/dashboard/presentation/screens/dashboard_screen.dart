import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/features/dashboard/presentation/widgets/dashboard_bottom_nav_bar.dart';
import 'package:sinapsis/features/dashboard/presentation/widgets/dashboard_nav_drawer.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Ancho a partir del cual se usa `Drawer` (Web/Tablet) en vez de
/// `BottomNavigationBar` (móvil). 600 es el breakpoint estándar de
/// Material 3 para "compact" vs "medium" window size class.
const _wideLayoutBreakpoint = 600.0;

/// La pantalla a la que se llega con la bóveda abierta.
///
/// Antes pedía el perfil del usuario a `GET /user` para demostrar que el
/// token viajaba en cada petición. Sin backend esa demostración no tiene
/// objeto, así que ya no hace ninguna llamada de red: lo que queda es el
/// esqueleto de navegación —que estaba bien resuelto y el producto va a
/// reusar— y el estado vacío que describe para qué sirve la app.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedNavIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle),
        actions: [
          const _LanguageToggleButton(),
          const _ThemeModeToggleButton(),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: l10n.lockVaultTooltip,
            // Ni redirección manual ni conocimiento del router acá: solo se
            // le avisa al controlador de la bóveda. El router, que lo
            // escucha, lleva al desbloqueo por su cuenta.
            onPressed: () =>
                ref.read(vaultSessionControllerProvider.notifier).lock(),
          ),
        ],
      ),
      drawer: isWide
          ? DashboardNavDrawer(
              selectedIndex: _selectedNavIndex,
              onSelect: (index) => setState(() => _selectedNavIndex = index),
            )
          : null,
      bottomNavigationBar: isWide
          ? null
          : DashboardBottomNavBar(
              selectedIndex: _selectedNavIndex,
              onSelect: (index) => setState(() => _selectedNavIndex = index),
            ),
      body: const _EmptyLibrary(),
    );
  }
}

/// El estado inicial: todavía no hay nada capturado.
///
/// Un vacío mudo deja al usuario adivinando qué hacer. Este explica en una
/// frase qué acepta la app y qué hace con ello, que es justamente lo que
/// alguien necesita saber la primera vez que entra.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.emptyLibraryTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.emptyLibraryMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cicla sistema -> claro -> oscuro -> sistema. El ícono refleja el modo
/// actual; el cambio persiste solo (ver `ThemeModeNotifier`), no hace
/// falta guardarlo a mano acá.
class _ThemeModeToggleButton extends ConsumerWidget {
  const _ThemeModeToggleButton();

  static const _cycle = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];

  IconData _iconFor(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeNotifierProvider);

    return IconButton(
      icon: Icon(_iconFor(themeMode)),
      tooltip: AppLocalizations.of(context)!.themeModeTooltip,
      onPressed: () {
        final next = _cycle[(_cycle.indexOf(themeMode) + 1) % _cycle.length];
        ref.read(themeModeNotifierProvider.notifier).setThemeMode(next);
      },
    );
  }
}

/// Cicla sistema -> Español -> English -> sistema. Muestra el código del
/// idioma *efectivo* (resuelve "sistema" a es/en real), no un ícono
/// ambiguo — más claro para probar que el cambio realmente ocurrió.
class _LanguageToggleButton extends ConsumerWidget {
  const _LanguageToggleButton();

  static const _cycle = <Locale?>[null, Locale('es'), Locale('en')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(localeNotifierProvider);
    final effective = ref.watch(effectiveLocaleProvider);

    return IconButton(
      icon: Text(
        effective.languageCode.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      tooltip: AppLocalizations.of(context)!.languageTooltip,
      onPressed: () {
        final next = _cycle[(_cycle.indexOf(preference) + 1) % _cycle.length];
        ref.read(localeNotifierProvider.notifier).setLocale(next);
      },
    );
  }
}
