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
/// Sin `isScrollControlled`, el panel queda topeado a la mitad de la pantalla
/// aunque haya de sobra más abajo: con muchos filtros, ese tope fijo obligaría
/// a desplazarse antes de lo necesario.
Future<void> showListFiltersSheet(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: builder,
  );
}

/// El marco del panel de filtros: el título, «Limpiar filtros» mientras haya
/// alguno, y las secciones.
///
/// Desplazable y no un `Column` a secas: cuántas líneas ocupan los chips
/// depende de cuántos haya y de qué tan angosta sea la pantalla, y un panel
/// que no puede crecer más allá de lo que el sistema le da —un teléfono en
/// horizontal, una ventana partida, la letra al doble— tiene que poder
/// desplazarse en vez de desbordar.
class ListFiltersSheet extends StatelessWidget {
  const ListFiltersSheet({
    required this.children,
    required this.onClear,
    super.key,
  });

  /// Las secciones, cada una con su [FilterSectionLabel].
  final List<Widget> children;

  /// Saca todos los filtros; `null` si no hay ninguno puesto.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.libraryFiltersTooltip,
                    style: theme.textTheme.titleMedium,
                  ),
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
