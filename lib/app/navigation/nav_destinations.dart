import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un destino de la navegación principal: cómo se ve en la barra (celular) o
/// el riel (escritorio), y a qué rama del `StatefulShellRoute` corresponde.
///
/// [branchIndex] es la posición real de la rama en `app_router.dart` —fija,
/// igual en todas las plataformas—, no la posición dentro de esta lista: en
/// la web el chat no se muestra (ver [buildNavDestinations]), así que la
/// lista visible puede tener menos elementos que ramas hay. Confundir las
/// dos posiciones dejaría a `NavigationBar`/`NavigationRail` marcando un
/// destino distinto del que en verdad está activo.
class NavDestinationSpec {
  const NavDestinationSpec({
    required this.branchIndex,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final int branchIndex;
  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

/// Arma la lista de destinos principales, en el mismo orden que las ramas de
/// `app_router.dart`: biblioteca, explorador, grafo, chat, repaso, ajustes.
///
/// Es una función y no una constante porque necesita `l10n` (idioma activo)
/// y la cuenta de tarjetas vencidas para la insignia de Repaso — dos cosas
/// que solo se conocen en el build. La misma lista alimenta a la barra y al
/// riel, para que no puedan desincronizarse entre sí.
List<NavDestinationSpec> buildNavDestinations({
  required AppLocalizations l10n,
  required int dueFlashcardCount,
  required bool includeChat,
}) {
  return [
    NavDestinationSpec(
      branchIndex: 0,
      icon: const Icon(Icons.folder_outlined),
      selectedIcon: const Icon(Icons.folder),
      label: l10n.navLibrary,
    ),
    // Entre biblioteca y grafo, tal como pidió el usuario: es el punto medio
    // natural entre "todo lo guardado" y "todo lo vinculado" — la vitrina de
    // resultados ya organizados por carpeta.
    NavDestinationSpec(
      branchIndex: 1,
      icon: const Icon(Icons.snippet_folder_outlined),
      selectedIcon: const Icon(Icons.snippet_folder),
      label: l10n.navExplorer,
    ),
    NavDestinationSpec(
      branchIndex: 2,
      icon: const Icon(Icons.hub_outlined),
      selectedIcon: const Icon(Icons.hub),
      label: l10n.navGraph,
    ),
    // Sin web a propósito: el chat necesita flutter_gemma corriendo en el
    // dispositivo, y esta función solo se validó en Android y Windows —
    // decisión 6 y 20 en docs/arquitectura.md—. La rama sigue existiendo en
    // el árbol de rutas (por eso branchIndex sigue siendo 3 más abajo, no
    // se corre), solo no aparece en la navegación.
    if (includeChat)
      NavDestinationSpec(
        branchIndex: 3,
        icon: const Icon(Icons.forum_outlined),
        selectedIcon: const Icon(Icons.forum),
        label: l10n.navChat,
      ),
    NavDestinationSpec(
      branchIndex: 4,
      icon: Badge(
        isLabelVisible: dueFlashcardCount > 0,
        label: Text('$dueFlashcardCount'),
        child: const Icon(Icons.style_outlined),
      ),
      selectedIcon: Badge(
        isLabelVisible: dueFlashcardCount > 0,
        label: Text('$dueFlashcardCount'),
        child: const Icon(Icons.style),
      ),
      label: l10n.navReview,
    ),
    NavDestinationSpec(
      branchIndex: 5,
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings),
      label: l10n.navSettings,
    ),
  ];
}
