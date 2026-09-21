import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un destino de la navegación principal: cómo se ve en la barra (celular) o
/// el riel (escritorio), y a qué rama del `StatefulShellRoute` corresponde.
///
/// [branchIndex] es la posición real de la rama en `app_router.dart` —fija,
/// igual en todas las plataformas—, no la posición dentro de esta lista: en
/// la web el chat no se muestra (ver [buildNavDestinations]), así que la
/// lista visible puede tener menos elementos que ramas hay, y el Atlas se
/// sumó al final del árbol de rutas pero se muestra tercero. Confundir las
/// dos posiciones dejaría a `NavigationBar`/`NavigationRail` marcando un
/// destino distinto del que en verdad está activo.
class NavDestinationSpec {
  const NavDestinationSpec({
    required this.branchIndex,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.onPhoneBar = false,
  });

  final int branchIndex;
  final Widget icon;
  final Widget selectedIcon;
  final String label;

  /// Si va en la barra de abajo del celular. Con ocho destinos no caben: los
  /// que no van ahí quedan detrás de «Más». El riel de escritorio los
  /// muestra todos.
  final bool onPhoneBar;
}

/// La rama del Atlas en `app_router.dart`: la última, para no correr el
/// índice de las que ya existían.
const kAtlasBranchIndex = 7;

/// Arma la lista de destinos principales, en el orden en que se ven:
/// biblioteca, bandeja de entrada, atlas, explorador, mapa, chat, repaso,
/// ajustes. Cada uno sabe su rama ([NavDestinationSpec.branchIndex]).
///
/// En el celular la barra muestra cinco —biblioteca, bandeja, atlas, mapa y
/// repaso— y un «Más» con el resto ([NavDestinationSpec.onPhoneBar]).
///
/// Es una función y no una constante porque necesita `l10n` (idioma activo)
/// y las cuentas de pendientes para las insignias de Bandeja y Repaso — cosas
/// que solo se conocen en el build. La misma lista alimenta a la barra y al
/// riel, para que no puedan desincronizarse entre sí.
List<NavDestinationSpec> buildNavDestinations({
  required AppLocalizations l10n,
  required int dueFlashcardCount,
  required int pendingInboxCount,
  required bool includeChat,
}) {
  return [
    NavDestinationSpec(
      branchIndex: 0,
      icon: const Icon(Icons.folder_outlined),
      selectedIcon: const Icon(Icons.folder),
      label: l10n.navLibrary,
      onPhoneBar: true,
    ),
    // Justo después de biblioteca: es el punto entre "todo lo guardado" y
    // "todo lo organizado" — ver la decisión sobre F3 en docs/arquitectura.md.
    //
    // `move_to_inbox`, no `inbox_outlined`: ese ícono ya lo usan los estados
    // vacíos de Biblioteca y Explorador, y coincidir lo dejaría ambiguo en
    // pantalla ancha —el riel y un estado vacío se ven a la vez—, además de
    // hacer que un test que busque el ícono de este destino encuentre dos.
    NavDestinationSpec(
      branchIndex: 1,
      icon: Badge(
        isLabelVisible: pendingInboxCount > 0,
        label: Text('$pendingInboxCount'),
        child: const Icon(Icons.move_to_inbox_outlined),
      ),
      selectedIcon: Badge(
        isLabelVisible: pendingInboxCount > 0,
        label: Text('$pendingInboxCount'),
        child: const Icon(Icons.move_to_inbox),
      ),
      label: l10n.navInbox,
      onPhoneBar: true,
    ),
    // El índice dinámico de lo que se sabe y de lo que falta (F13): después de
    // lo que entra y antes de lo que se explora. `account_tree` porque es un
    // árbol de temas; ningún otro destino usa ese ícono.
    NavDestinationSpec(
      branchIndex: kAtlasBranchIndex,
      icon: const Icon(Icons.account_tree_outlined),
      selectedIcon: const Icon(Icons.account_tree),
      label: l10n.navAtlas,
      onPhoneBar: true,
    ),
    // Entre bandeja y mapa, tal como pidió el usuario: es el punto medio
    // natural entre "todo lo guardado" y "todo lo vinculado" — la vitrina de
    // resultados ya organizados por carpeta.
    NavDestinationSpec(
      branchIndex: 2,
      icon: const Icon(Icons.snippet_folder_outlined),
      selectedIcon: const Icon(Icons.snippet_folder),
      label: l10n.navExplorer,
    ),
    NavDestinationSpec(
      branchIndex: 3,
      icon: const Icon(Icons.hub_outlined),
      selectedIcon: const Icon(Icons.hub),
      label: l10n.navMap,
      onPhoneBar: true,
    ),
    // Sin web a propósito: el chat necesita flutter_gemma corriendo en el
    // dispositivo, y esta función solo se validó en Android y Windows —
    // decisión 6 y 20 en docs/arquitectura.md—. La rama sigue existiendo en
    // el árbol de rutas (por eso branchIndex sigue siendo 4 más abajo, no
    // se corre), solo no aparece en la navegación.
    if (includeChat)
      NavDestinationSpec(
        branchIndex: 4,
        icon: const Icon(Icons.forum_outlined),
        selectedIcon: const Icon(Icons.forum),
        label: l10n.navChat,
      ),
    NavDestinationSpec(
      branchIndex: 5,
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
      onPhoneBar: true,
    ),
    NavDestinationSpec(
      branchIndex: 6,
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings),
      label: l10n.navSettings,
    ),
  ];
}
