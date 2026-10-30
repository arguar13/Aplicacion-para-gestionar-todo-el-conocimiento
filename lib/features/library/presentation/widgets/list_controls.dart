/// Las piezas de una lista como la Biblioteca: la búsqueda con el botón de
/// filtros al lado, el panel de filtros, el pie de «Cargar más» y la barra del
/// modo de selección.
///
/// Nacieron en `LibraryScreen` y se mudaron acá cuando «Procesado» (F41), que
/// se ve como la Biblioteca, las necesitó: una lista que se busca, se filtra y
/// se elige de a varios tiene que verse y portarse igual en las dos pantallas,
/// y dos copias se separan solas con el tiempo. Cada pantalla pone lo suyo —qué
/// filtra, qué hace con lo elegido—; estas piezas, cómo se ve.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La búsqueda, con el botón de filtros al lado y no en una fila propia, y el
/// número de filtros activos en su insignia.
class ListSearchRow extends StatelessWidget {
  const ListSearchRow({
    required this.hintText,
    required this.onChanged,
    required this.activeFilterCount,
    required this.onOpenFilters,
    super.key,
  });

  /// El alto que ocupa, que una barra de arriba necesita saber antes de
  /// construirla (`PreferredSize`).
  static const height = 64.0;

  final String hintText;
  final ValueChanged<String> onChanged;

  /// Cuántos filtros hay puestos: con alguno, el botón se ve marcado.
  final int activeFilterCount;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Badge(
            label: Text('$activeFilterCount'),
            isLabelVisible: activeFilterCount > 0,
            child: IconButton(
              icon: const Icon(Icons.tune),
              tooltip: l10n.libraryFiltersTooltip,
              isSelected: activeFilterCount > 0,
              onPressed: onOpenFilters,
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre el panel de filtros que arma [builder], desde abajo.
///
/// Devuelve `true` si se cerró con el pie —«Ver N resultados», ver
/// [ListFiltersSheet]—: la pantalla muestra entonces su lista desde arriba.
/// Cerrado de otra forma —arrastrándolo, con «atrás», tocando afuera— da
/// `false`, y lo elegido vale igual: los filtros se aplican al tocarlos
/// (F47, decisión K), no al confirmar.
///
/// Sin `isScrollControlled`, el panel queda topeado a la mitad de la pantalla
/// aunque haya de sobra más abajo: con muchos filtros, ese tope fijo obligaría
/// a desplazarse antes de lo necesario. Con `useSafeArea`, alto del todo —un
/// teléfono en horizontal— no se mete debajo de la barra de estado.
Future<bool> showListFiltersSheet(
  BuildContext context, {
  required WidgetBuilder builder,
}) async {
  final showResults = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: builder,
  );
  return showResults ?? false;
}

/// El marco del panel de filtros: el título, «Limpiar filtros» mientras haya
/// alguno, las secciones y, fijo abajo, el pie que lo cierra con cuántos
/// resultados quedan (F47, mejora 21).
///
/// Las secciones se desplazan y no un `Column` a secas: cuántas líneas
/// ocupan los chips depende de cuántos haya y de qué tan angosta sea la
/// pantalla, y un panel que no puede crecer más allá de lo que el sistema le
/// da —un teléfono en horizontal, una ventana partida, la letra al doble—
/// tiene que poder desplazarse en vez de desbordar. El pie, no: se queda a la
/// vista mientras se recorren los filtros, que es cuando se lo busca.
class ListFiltersSheet extends StatelessWidget {
  const ListFiltersSheet({
    required this.children,
    required this.onClear,
    required this.results,
    required this.narrowed,
    super.key,
  });

  /// El botón del pie, para las pruebas.
  static const showResultsKey = Key('list-filters-show-results');

  /// Las secciones, cada una con su [FilterSectionLabel].
  final List<Widget> children;

  /// Saca todos los filtros; `null` si no hay ninguno puesto.
  final VoidCallback? onClear;

  /// Cuántos quedan con lo elegido —contados en la base, sin traerlos—: lo
  /// que dice el pie. Mientras se cuenta, sin cifra.
  final AsyncValue<int> results;

  /// Si algo acota la lista —un filtro o lo buscado—: sin nada, el pie dice
  /// «Ver todo (N)» y no «Ver N resultados».
  final bool narrowed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // `Wrap` y no una fila: con la letra al doble en un
                  // teléfono angosto, «Limpiar filtros» no entra al lado del
                  // título y baja a su propia línea en vez de desbordar.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.libraryFiltersTooltip,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (onClear case final onClear?)
                        TextButton(
                          onPressed: onClear,
                          child: Text(l10n.libraryClearFilters),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...children,
                ],
              ),
            ),
          ),
          _ShowResultsBar(results: results, narrowed: narrowed),
        ],
      ),
    );
  }
}

/// El pie del panel de filtros: un botón relleno a lo ancho con cuántos
/// resultados quedan, que cierra el panel y deja la lista a la vista.
///
/// - Con alguno, «Ver 12 resultados»; sin nada que acote, «Ver todo (340)».
/// - Mientras se cuenta —cada filtro que se toca es otra cuenta—, «Ver
///   resultados», sin cifra: nunca la de antes, que ya no es cierta.
/// - Con cero, «Ningún resultado», apagado: no hay nada que ir a ver, y
///   arriba sigue «Limpiar filtros».
///
/// Es una región viva: el lector de pantalla anuncia la frase nueva cada vez
/// que la cifra cambia, sin que haya que ir a buscarla.
class _ShowResultsBar extends StatefulWidget {
  const _ShowResultsBar({required this.results, required this.narrowed});

  final AsyncValue<int> results;
  final bool narrowed;

  @override
  State<_ShowResultsBar> createState() => _ShowResultsBarState();
}

class _ShowResultsBarState extends State<_ShowResultsBar> {
  /// La última frase con la cifra ya contada. Mientras se cuenta de nuevo,
  /// el botón le guarda el lugar —con la letra al doble puede ocupar dos
  /// líneas y «Ver resultados» una— para no saltar de tamaño en cada toque.
  /// Se mide, no se muestra ni se lee.
  String? _lastCounted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Solo un valor recién contado: una cuenta que se repite recuerda la de
    // antes —`isLoading`, con su valor—, y esa ya no es la cifra de ahora.
    final results = widget.results;
    final count = results.hasValue && !results.isLoading && !results.hasError
        ? results.requireValue
        : null;
    final label = switch (count) {
      null => l10n.f47P0FiltersCounting,
      0 => l10n.f47P0FiltersNoResults,
      final count when !widget.narrowed => l10n.f47P0FiltersShowAll(count),
      final count => l10n.f47P0FiltersShowResults(count),
    };
    final reserved = count == null ? _lastCounted : null;
    if (count != null) _lastCounted = label;
    final onPressed = count == 0 ? null : () => Navigator.of(context).pop(true);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        // Un solo nodo para el lector de pantalla —el botón, su frase y la
        // región viva juntos—, dicho acá y no mezclado del botón: la región
        // viva tiene que ser el nodo cuya frase cambia, o no se anuncia.
        child: Semantics(
          container: true,
          liveRegion: true,
          button: true,
          enabled: onPressed != null,
          label: label,
          onTap: onPressed,
          excludeSemantics: true,
          child: FilledButton(
            key: ListFiltersSheet.showResultsKey,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: onPressed,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (reserved != null)
                  Visibility(
                    visible: false,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Text(reserved, textAlign: TextAlign.center),
                  ),
                Text(label, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El nombre de una sección del panel de filtros.
class FilterSectionLabel extends StatelessWidget {
  const FilterSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// El pie de «Cargar más»: trae la próxima tanda sin tener que desplazarse
/// para descubrir que hay una.
///
/// Un botón explícito y no una carga automática al llegar al final del
/// scroll a propósito: las vistas de la Biblioteca —lista, tabla, tablero—
/// comparten este mismo pie, y solo una de ellas tiene un único scroll
/// vertical del que "llegar al final" tendría un sentido obvio.
class LoadMoreBar extends StatelessWidget {
  const LoadMoreBar({
    required this.isLoading,
    required this.onPressed,
    super.key,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: onPressed,
                  child: Text(l10n.libraryLoadMore),
                ),
        ),
      ),
    );
  }
}

/// La barra de arriba mientras se eligen elementos: cuántos hay, la cruz para
/// salir y las acciones que tienen sentido en ese modo.
class SelectionModeAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const SelectionModeAppBar({
    required this.selectedCount,
    required this.onCancel,
    required this.actions,
    super.key,
  });

  final int selectedCount;
  final VoidCallback onCancel;

  /// Lo que se puede hacer con lo elegido. Cada pantalla las apaga en cero:
  /// pedirle algo a una lista vacía solo volvería con un fallo de validación.
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.libraryExitSelectionTooltip,
        onPressed: onCancel,
      ),
      title: Text(l10n.librarySelectedCount(selectedCount)),
      actions: actions,
    );
  }
}
