import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/core/session/session_providers.dart';
import 'package:sinapsis/features/dashboard/presentation/providers/dashboard_notifier.dart';
import 'package:sinapsis/features/dashboard/presentation/providers/dashboard_state.dart';
import 'package:sinapsis/features/dashboard/presentation/widgets/dashboard_bottom_nav_bar.dart';
import 'package:sinapsis/features/dashboard/presentation/widgets/dashboard_nav_drawer.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Ancho a partir del cual se usa `Drawer` (Web/Tablet) en vez de
/// `BottomNavigationBar` (móvil). 600 es el breakpoint estándar de
/// Material 3 para "compact" vs "medium" window size class.
const _wideLayoutBreakpoint = 600.0;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    // Diferido al post-frame: `loadCurrentUser()` muta el estado de forma
    // síncrona antes de cualquier `await` (pasa a `loading` de inmediato).
    // Hacerlo directo en `initState` viola la regla de Riverpod de no
    // modificar providers mientras el árbol de widgets se está
    // construyendo — el propio mensaje de error de Riverpod sugiere este
    // patrón.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(dashboardNotifierProvider.notifier).loadCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    final state = ref.watch(dashboardNotifierProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle),
        actions: [
          const _LanguageToggleButton(),
          const _ThemeModeToggleButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.logoutTooltip,
            // Ni redirección manual ni conocimiento del router acá: solo se
            // le avisa al SessionController. El router (que lo escucha)
            // expulsa a /login por su cuenta.
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
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
      body: _DashboardBody(state: state),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return switch (state) {
      DashboardInitial() ||
      DashboardLoading() => const Center(child: CircularProgressIndicator()),
      DashboardError(:final message) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref
                  .read(dashboardNotifierProvider.notifier)
                  .loadCurrentUser(),
              child: Text(l10n.loadErrorRetry),
            ),
          ],
        ),
      ),
      // El nombre viaja dentro del propio mensaje traducido
      // (welcomeMessage(name)) en vez de mostrarse dos veces — ver
      // app_en.arb/app_es.arb, es el ejemplo de string con parámetro
      // dinámico que pidió el requerimiento.
      DashboardLoaded(:final user) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.welcomeMessage(user.name),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(user.email, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    };
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
