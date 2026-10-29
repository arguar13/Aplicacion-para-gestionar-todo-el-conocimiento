import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/navigation/nav_destinations.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/study_day_watcher.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Bajo este ancho, `NavigationBar` abajo; en o por encima, `NavigationRail`
/// al costado. El mismo corte que usa Material 3 entre la clase de ventana
/// "compacta" (celular) y "mediana o más" (tablet, escritorio) — no un
/// número inventado para esta app.
const kNavRailBreakpoint = 600.0;

/// El alto de `NavigationBar` cuando el tema no dice otro: el de Material 3.
const _kNavigationBarHeight = 80.0;

/// El shell de navegación principal: biblioteca, bandeja, atlas, procesado,
/// cuadernos, línea de tiempo, mapa, repaso, chat y ajustes, cada uno con su
/// propio `Navigator` —vía `StatefulShellRoute.indexedStack` en
/// `app_router.dart`— para que cambiar de pestaña y volver conserve el scroll
/// y los filtros de cada una.
///
/// Reemplaza al AppBar de nueve íconos que tenía antes la biblioteca (ver la
/// decisión 22 en docs/arquitectura.md): cada función pasa a tener su propio
/// lugar, en vez de competir por espacio en una sola fila que en un celular
/// real desbordaba.
///
/// Diez destinos no caben en una barra de celular: la barra muestra los
/// cinco pasos del trabajo, en el orden en que se usan —Biblioteca,
/// Organizar, Estudiar, Chat y Ajustes (F43; antes «Repasar» era un paso y
/// el chat iba antes)—, y un paso con varios destinos abre su lista (F34,
/// decisión 76; antes eran cinco y un «Más», F13). El riel de escritorio los
/// muestra todos, en el mismo orden.
class AdaptiveScaffold extends ConsumerWidget {
  const AdaptiveScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dueCount = ref.watch(studyDueTodayCountProvider).valueOrNull ?? 0;
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
              // Diez destinos con su nombre (F41) no entran en una ventana
              // baja, ni con la letra al doble: el riel se desplaza en vez de
              // desbordar.
              scrollable: true,
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
            Expanded(child: StudyDayWatcher(child: navigationShell)),
          ],
        ),
      );
    }

    // En el celular: un botón por paso, en orden de uso (F34). Un paso con
    // varios destinos abre su lista; con uno solo, lo abre directo.
    final groups = buildNavStepGroups(l10n: l10n, destinations: destinations);
    final current = navigationShell.currentIndex;
    final groupIndex = groups.indexWhere((g) => g.contains(current));

    return Scaffold(
      body: StudyDayWatcher(child: navigationShell),
      // Con el teclado abierto, la barra se va (F42): queda debajo de él, no
      // se puede tocar, y el lector de pantalla no tiene por qué pasar por
      // ella; la pantalla —el chat, sobre todo— usa toda la altura. Se va
      // recién cuando el teclado ya la tapa entera, y vuelve apenas asoma:
      // así lo de arriba no salta mientras el teclado sube o baja.
      bottomNavigationBar: _keyboardCoversBar(context)
          ? null
          : NavigationBar(
              selectedIndex: groupIndex < 0 ? 0 : groupIndex,
              onDestinationSelected: (index) {
                final group = groups[index];
                if (group.hasList) {
                  unawaited(_showStep(context, group, current, goToBranch));
                } else {
                  goToBranch(group.destinations.single.branchIndex);
                }
              },
              destinations: [
                for (final g in groups)
                  NavigationDestination(
                    key: ValueKey('nav-step-${g.step.name}'),
                    icon: g.icon,
                    selectedIcon: g.selectedIcon,
                    label: g.label,
                  ),
              ],
            ),
    );
  }

  /// Si el teclado tapa la barra de abajo entera: su alto de Material 3 más el
  /// borde del sistema que todavía quede a la vista.
  static bool _keyboardCoversBar(BuildContext context) {
    final bar =
        (NavigationBarTheme.of(context).height ?? _kNavigationBarHeight) +
        MediaQuery.paddingOf(context).bottom;
    return MediaQuery.viewInsetsOf(context).bottom >= bar;
  }

  /// La lista de un paso: sus destinos de arriba abajo en orden de uso, cada
  /// uno con para qué sirve, y el que está abierto marcado.
  Future<void> _showStep(
    BuildContext context,
    NavStepGroup group,
    int currentBranch,
    void Function(int branchIndex) goToBranch,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Con letra grande o en un teléfono chico, la lista entera.
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(group.label, style: theme.textTheme.titleLarge),
                ),
                for (final d in group.destinations)
                  ListTile(
                    key: ValueKey('nav-step-item-${d.branchIndex}'),
                    leading: d.branchIndex == currentBranch
                        ? d.selectedIcon
                        : d.icon,
                    title: Text(d.label),
                    subtitle: Text(d.hint),
                    trailing: const Icon(Icons.chevron_right),
                    selected: d.branchIndex == currentBranch,
                    selectedTileColor: theme.colorScheme.secondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      goToBranch(d.branchIndex);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
