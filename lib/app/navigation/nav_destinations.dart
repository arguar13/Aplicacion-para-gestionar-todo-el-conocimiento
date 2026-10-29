import 'package:flutter/material.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los pasos del trabajo, de izquierda a derecha en la barra del celular
/// (F34): primero se guarda, después se ordena lo que entró, después se
/// estudia lo procesado y por último se pregunta; Ajustes siempre a la
/// derecha. «Estudiar» tomó el lugar de «Repasar», que pasó a ser el último
/// de su lista, y el chat quedó a su derecha (F43). El orden del enum es el
/// de la barra.
enum NavStep { save, organize, study, ask, settings }

/// Un destino de la navegación principal: cómo se ve en la barra (celular) o
/// el riel (escritorio), y a qué rama del `StatefulShellRoute` corresponde.
///
/// [branchIndex] es la posición real de la rama en `app_router.dart` —fija,
/// igual en todas las plataformas—, no la posición dentro de esta lista: en
/// la web el chat no se muestra (ver [buildNavDestinations]), así que la
/// lista visible puede tener menos elementos que ramas hay, y el Atlas,
/// Procesado, los cuadernos y la línea de tiempo se sumaron al final del
/// árbol de rutas pero se muestran en el medio de «Organizar» y de
/// «Estudiar». Confundir las dos posiciones dejaría a
/// `NavigationBar`/`NavigationRail` marcando un destino distinto del que en
/// verdad está activo.
class NavDestinationSpec {
  const NavDestinationSpec({
    required this.branchIndex,
    required this.step,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.hint,
    this.badgeCount = 0,
  });

  final int branchIndex;

  /// El paso de la barra del celular en el que va (F34).
  final NavStep step;

  final Widget icon;
  final Widget selectedIcon;
  final String label;

  /// Para qué sirve, en una línea: lo que dice la lista de un paso debajo
  /// del nombre.
  final String hint;

  /// Lo pendiente que cuenta su insignia (ya dibujada en [icon]); el paso
  /// que lo agrupa la suma, para que se vea sin abrir la lista.
  final int badgeCount;
}

/// Un botón de la barra del celular: un paso con sus destinos, en orden de
/// uso (F34). Con uno solo se ve como ese destino y lo abre; con varios
/// tiene su propio nombre e ícono y abre la lista del paso.
class NavStepGroup {
  const NavStepGroup({
    required this.step,
    required this.destinations,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final NavStep step;
  final List<NavDestinationSpec> destinations;
  final Widget icon;
  final Widget selectedIcon;
  final String label;

  bool get hasList => destinations.length > 1;

  bool contains(int branchIndex) =>
      destinations.any((d) => d.branchIndex == branchIndex);
}

/// Las ramas del `StatefulShellRoute` de `app_router.dart`, **en su orden**:
/// el índice de cada una es su posición en el árbol de rutas. Una prueba
/// compara las dos listas (`app_router_branches_test.dart`).
///
/// Con nombre y no con números sueltos: el Atlas, los cuadernos, la línea de
/// tiempo (F40) y Procesado (F41) se sumaron al final para no correr las de
/// arriba, y el Explorador salió de la barra
/// (F36) —ahora se abre desde el Atlas y el Mapa—, así que sacar o sumar una
/// rama corre las demás, y un número escrito a mano en otro lado quedaría
/// apuntando a otra pantalla. Por lo mismo, mudar un destino de paso (F43:
/// «Estudiar») no toca este orden: el lugar en la barra lo dice
/// [buildNavDestinations], no la rama.
enum ShellBranch {
  library,
  inbox,
  graph,
  chat,
  review,
  settings,
  atlas,
  notebooks,
  timeline,
  processed,
}

/// Arma la lista de destinos principales, en el orden de uso en que se ven
/// (F34, F43): biblioteca; bandeja de entrada y atlas; procesado, cuadernos,
/// línea de tiempo, mapa y repaso; chat; ajustes. Cada uno sabe su rama
/// ([NavDestinationSpec.branchIndex]) y su paso ([NavDestinationSpec.step]).
///
/// El riel de escritorio los muestra todos, en este orden; la barra del
/// celular, agrupados por paso ([buildNavStepGroups]), cada uno en su lugar
/// dentro del suyo.
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
      branchIndex: ShellBranch.library.index,
      step: NavStep.save,
      icon: const Icon(Icons.folder_outlined),
      selectedIcon: const Icon(Icons.folder),
      label: l10n.navLibrary,
      hint: l10n.navLibraryHint,
    ),
    // Justo después de biblioteca: es el punto entre "todo lo guardado" y
    // "todo lo organizado" — ver la decisión sobre F3 en docs/arquitectura.md.
    //
    // `move_to_inbox`, no `inbox_outlined`: ese ícono ya lo usan los estados
    // vacíos de la Biblioteca y del material de un tema, y coincidir lo
    // dejaría ambiguo en pantalla ancha —el riel y un estado vacío se ven a
    // la vez—, además de hacer que un test que busque el ícono de este
    // destino encuentre dos.
    NavDestinationSpec(
      branchIndex: ShellBranch.inbox.index,
      step: NavStep.organize,
      icon: _badged(pendingInboxCount, Icons.move_to_inbox_outlined),
      selectedIcon: _badged(pendingInboxCount, Icons.move_to_inbox),
      label: l10n.navInbox,
      hint: l10n.navInboxHint,
      badgeCount: pendingInboxCount,
    ),
    // El índice dinámico de lo que se sabe y de lo que falta (F13): se queda
    // en «Organizar», debajo de la Bandeja, cuando lo demás pasó a
    // «Estudiar» —el pedido no lo nombraba entre los que se mudan; F43,
    // decisión A—. `account_tree` porque es un árbol de temas; ningún otro
    // destino usa ese ícono.
    NavDestinationSpec(
      branchIndex: ShellBranch.atlas.index,
      step: NavStep.organize,
      icon: const Icon(Icons.account_tree_outlined),
      selectedIcon: const Icon(Icons.account_tree),
      label: l10n.navAtlas,
      hint: l10n.navAtlasHint,
    ),
    // La información que se sacó de cada fuente (F41): la primera de
    // «Estudiar» (F43), porque todo lo que se estudia sale de acá. `summarize`
    // —una hoja con renglones—, que no usa ningún otro destino ni pantalla:
    // `article` ya es el de una página web.
    NavDestinationSpec(
      branchIndex: ShellBranch.processed.index,
      step: NavStep.study,
      icon: const Icon(Icons.summarize_outlined),
      selectedIcon: const Icon(Icons.summarize),
      label: l10n.navProcessed,
      hint: l10n.navProcessedHint,
    ),
    // Debajo de Procesado (F43): un cuaderno junta un grupo de documentos
    // procesados para estudiarlos —y preguntarle al chat— solo sobre ellos.
    NavDestinationSpec(
      branchIndex: ShellBranch.notebooks.index,
      step: NavStep.study,
      icon: const Icon(Icons.auto_stories_outlined),
      selectedIcon: const Icon(Icons.auto_stories),
      label: l10n.navNotebooks,
      hint: l10n.navNotebooksHint,
    ),
    // Los hechos con fecha sobre un eje (F9, F40), en «Estudiar» (F43): el
    // Atlas la sigue abriendo filtrada por una rama. `timeline` en los dos
    // estados: no tiene variante rellena, y el riel marca el elegido con su
    // cápsula.
    NavDestinationSpec(
      branchIndex: ShellBranch.timeline.index,
      step: NavStep.study,
      icon: const Icon(Icons.timeline),
      selectedIcon: const Icon(Icons.timeline),
      label: l10n.navTimeline,
      hint: l10n.navTimelineHint,
    ),
    // Sin el Explorador (F36): repetía la Biblioteca con otros filtros. Lo
    // que tenía de propio —el material de un tema y sus subtemas— se abre
    // desde el Atlas y el Mapa, con su flecha para volver.
    NavDestinationSpec(
      branchIndex: ShellBranch.graph.index,
      step: NavStep.study,
      icon: const Icon(Icons.hub_outlined),
      selectedIcon: const Icon(Icons.hub),
      label: l10n.navMap,
      hint: l10n.navMapHint,
    ),
    // Al final de «Estudiar» (F43): las tarjetas de hoy y, desde ahí, lo que
    // se crea sobre lo procesado. Su insignia la suma el paso, para que lo
    // que toca hoy se vea sin abrir la lista.
    NavDestinationSpec(
      branchIndex: ShellBranch.review.index,
      step: NavStep.study,
      icon: _badged(dueFlashcardCount, Icons.style_outlined),
      selectedIcon: _badged(dueFlashcardCount, Icons.style),
      label: l10n.navReview,
      hint: l10n.navReviewHint,
      badgeCount: dueFlashcardCount,
    ),
    // A la derecha de «Estudiar» (F43), solo y directo, sin lista.
    //
    // Sin web a propósito: el chat necesita flutter_gemma corriendo en el
    // dispositivo, y esta función solo se validó en Android y Windows —
    // decisión 6 y 20 en docs/arquitectura.md—. La rama sigue existiendo en
    // el árbol de rutas, solo no aparece en la navegación.
    if (includeChat)
      NavDestinationSpec(
        branchIndex: ShellBranch.chat.index,
        step: NavStep.ask,
        icon: const Icon(Icons.forum_outlined),
        selectedIcon: const Icon(Icons.forum),
        label: l10n.navChat,
        hint: l10n.navChatHint,
      ),
    NavDestinationSpec(
      branchIndex: ShellBranch.settings.index,
      step: NavStep.settings,
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings),
      label: l10n.navSettings,
      hint: l10n.navSettingsHint,
    ),
  ];
}

/// Agrupa [destinations] en los botones de la barra del celular, uno por
/// paso con algo adentro, en el orden de [NavStep] (F34). Cada destino
/// conserva su orden dentro del paso, y un paso con lista suma las
/// insignias de los suyos: la Bandeja en «Organizar», las tarjetas para hoy
/// en «Estudiar» (F43).
List<NavStepGroup> buildNavStepGroups({
  required AppLocalizations l10n,
  required List<NavDestinationSpec> destinations,
}) {
  return [
    for (final step in NavStep.values)
      if (destinations.where((d) => d.step == step).toList() case final inStep
          when inStep.isNotEmpty)
        _groupOf(l10n, step, inStep),
  ];
}

NavStepGroup _groupOf(
  AppLocalizations l10n,
  NavStep step,
  List<NavDestinationSpec> inStep,
) {
  if (inStep.length == 1) {
    final only = inStep.single;
    return NavStepGroup(
      step: step,
      destinations: inStep,
      icon: only.icon,
      selectedIcon: only.selectedIcon,
      label: only.label,
    );
  }
  final badge = inStep.fold(0, (sum, d) => sum + d.badgeCount);
  // Íconos que ningún destino ni pantalla usa, para que el paso no se
  // confunda con uno de sus destinos.
  final (label, icon, selectedIcon) = switch (step) {
    NavStep.organize => (
      l10n.navStepOrganize,
      Icons.workspaces_outlined,
      Icons.workspaces,
    ),
    // La pluma sobre el papel (F43): estudiar es también crear sobre lo
    // procesado. `school` no, que ya es el de «estudiar un documento».
    NavStep.study => (
      l10n.f43NavStepStudy,
      Icons.history_edu_outlined,
      Icons.history_edu,
    ),
    // Pasos de un destino solo: un segundo pide decidir antes cómo se ve el
    // paso, no heredar en silencio el aspecto del primero.
    NavStep.save || NavStep.ask || NavStep.settings => throw StateError(
      'El paso $step tiene ${inStep.length} destinos y no tiene aspecto '
      'propio',
    ),
  };
  return NavStepGroup(
    step: step,
    destinations: inStep,
    icon: _badged(badge, icon),
    selectedIcon: _badged(badge, selectedIcon),
    label: label,
  );
}

Widget _badged(int count, IconData icon) =>
    Badge(isLabelVisible: count > 0, label: Text('$count'), child: Icon(icon));
