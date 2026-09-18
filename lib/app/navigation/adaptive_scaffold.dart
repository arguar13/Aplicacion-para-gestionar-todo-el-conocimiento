import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/navigation/nav_destinations.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Bajo este ancho, `NavigationBar` abajo; en o por encima, `NavigationRail`
/// al costado. El mismo corte que usa Material 3 entre la clase de ventana
/// "compacta" (celular) y "mediana o más" (tablet, escritorio) — no un
/// número inventado para esta app.
const kNavRailBreakpoint = 600.0;

/// El shell de navegación principal: biblioteca, grafo, chat, repaso y
/// ajustes, cada uno con su propio `Navigator` —vía
/// `StatefulShellRoute.indexedStack` en `app_router.dart`— para que cambiar
/// de pestaña y volver conserve el scroll y los filtros de cada una.
///
/// Reemplaza al AppBar de nueve íconos que tenía antes la biblioteca (ver la
/// decisión 22 en docs/arquitectura.md): cada función pasa a tener su propio
/// lugar, en vez de competir por espacio en una sola fila que en un celular
/// real desbordaba.
class AdaptiveScaffold extends ConsumerWidget {
  const AdaptiveScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dueCount = ref.watch(dueFlashcardCountProvider).valueOrNull ?? 0;
    final pendingInboxCount =
        ref.watch(inboxPendingIdsProvider).valueOrNull?.length ?? 0;
    final destinations = buildNavDestinations(
      l10n: l10n,
      dueFlashcardCount: dueCount,
      pendingInboxCount: pendingInboxCount,
      includeChat: !kIsWeb,
    );

    // La posición dentro de `destinations` no es la rama activa: en la web
    // esta lista tiene un elemento menos que ramas hay (ver
    // `NavDestinationSpec.branchIndex`).
    final selectedIndex = destinations.indexWhere(
      (d) => d.branchIndex == navigationShell.currentIndex,
    );

    void onSelect(int visibleIndex) {
      final branchIndex = destinations[visibleIndex].branchIndex;
      navigationShell.goBranch(
        branchIndex,
        initialLocation: branchIndex == navigationShell.currentIndex,
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= kNavRailBreakpoint;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
              onDestinationSelected: onSelect,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon,
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: onSelect,
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: d.icon,
              selectedIcon: d.selectedIcon,
              label: d.label,
            ),
        ],
      ),
    );
  }
}
