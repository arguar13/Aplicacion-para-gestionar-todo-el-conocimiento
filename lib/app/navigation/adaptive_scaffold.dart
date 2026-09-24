import 'dart:async';

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

/// El shell de navegación principal: biblioteca, bandeja, atlas, explorador,
/// mapa, chat, cuadernos, repaso y ajustes, cada uno con su propio
/// `Navigator` —vía `StatefulShellRoute.indexedStack` en `app_router.dart`—
/// para que cambiar de pestaña y volver conserve el scroll y los filtros de
/// cada una.
///
/// Reemplaza al AppBar de nueve íconos que tenía antes la biblioteca (ver la
/// decisión 22 en docs/arquitectura.md): cada función pasa a tener su propio
/// lugar, en vez de competir por espacio en una sola fila que en un celular
/// real desbordaba.
///
/// Con el Atlas y los cuadernos son nueve destinos, y nueve no caben en una
/// barra de celular: la barra muestra cinco y un «Más» que abre una hoja con
/// el resto (F13, D1). El riel de escritorio los muestra todos.
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

    // Tocar el destino en el que ya se está vuelve a su pantalla inicial.
    void goToBranch(int branchIndex) => navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == navigationShell.currentIndex,
    );

    void onSelect(int visibleIndex) =>
        goToBranch(destinations[visibleIndex].branchIndex);

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

    // En el celular: los destinos de la barra más un «Más» con el resto.
    final onBar = [
      for (final d in destinations)
        if (d.onPhoneBar) d,
    ];
    final overflow = [
      for (final d in destinations)
        if (!d.onPhoneBar) d,
    ];
    final moreIndex = onBar.length;
    final current = navigationShell.currentIndex;
    final barIndex = onBar.indexWhere((d) => d.branchIndex == current);
    // Estar en uno de los que quedaron detrás de «Más» marca a «Más».
    final barSelected = barIndex >= 0
        ? barIndex
        : (overflow.any((d) => d.branchIndex == current) ? moreIndex : 0);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: barSelected,
        onDestinationSelected: (index) {
          if (index == moreIndex) {
            unawaited(_showMore(context, overflow, current, goToBranch));
          } else {
            goToBranch(onBar[index].branchIndex);
          }
        },
        destinations: [
          for (final d in onBar)
            NavigationDestination(
              icon: d.icon,
              selectedIcon: d.selectedIcon,
              label: d.label,
            ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            selectedIcon: const Icon(Icons.more_horiz),
            label: l10n.navMore,
          ),
        ],
      ),
    );
  }

  /// La hoja de «Más»: los destinos que no caben en la barra.
  Future<void> _showMore(
    BuildContext context,
    List<NavDestinationSpec> overflow,
    int currentBranch,
    void Function(int branchIndex) goToBranch,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in overflow)
              ListTile(
                key: ValueKey('nav-more-${d.branchIndex}'),
                leading: d.branchIndex == currentBranch
                    ? d.selectedIcon
                    : d.icon,
                title: Text(d.label),
                selected: d.branchIndex == currentBranch,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  goToBranch(d.branchIndex);
                },
              ),
          ],
        ),
      ),
    );
  }
}
