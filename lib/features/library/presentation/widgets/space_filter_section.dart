import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_naming.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La sección «Tema» de un panel de filtros, debajo de su encabezado.
///
/// Compartida entre la Biblioteca y el Explorador: las dos filtran por tema
/// de la misma manera, y dos copias de esta sección —con su tope de alto, su
/// barra y su desvanecido— solo servirían para que un día se vean distintas.
/// Cada pantalla le dice cuál es su tema elegido y qué hacer cuando cambia;
/// el resto vive acá.
///
/// Siempre está, aunque no haya ningún tema: esconderla en ese caso es lo que
/// hacía que, en una biblioteca recién estrenada, nadie supiera que se puede
/// filtrar por tema. Sin temas, muestra para qué sirven y cómo crear uno —ver
/// `_NoSpacesYet`—.
///
/// Mira `allSpacesProvider` por su cuenta, en vez de recibir la lista al
/// abrirse el panel: renombrar, borrar o crear un tema se hace desde esta
/// misma sección, y tiene que verse enseguida.
class SpaceFilterSection extends ConsumerWidget {
  const SpaceFilterSection({
    required this.selectedSpaceId,
    required this.onChanged,
    super.key,
  });

  /// La clave del área de los chips, la que se desplaza: por ella la
  /// encuentran las pruebas sin confundir un chip de acá con el del tema
  /// elegido debajo de la búsqueda, que se llama igual.
  static const chipsKey = ValueKey('space-filter-chips');

  /// El tema por el que se está filtrando, o `null` si ninguno.
  final String? selectedSpaceId;

  /// Qué tema pasa a ser el elegido: el `id` de uno, o `null` para soltar el
  /// que hubiera. La sección ya resuelve que tocar el elegido lo suelta.
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(allSpacesProvider).valueOrNull;

    // Mientras llega la lista, nada: mostrar «todavía no tenés temas» a
    // quien sí tiene sería decirle algo falso por un instante.
    if (spaces == null) return const SizedBox.shrink();
    if (spaces.isEmpty) return const _NoSpacesYet();

    return _SpaceFilterChips(
      spaces: spaces,
      selectedSpaceId: selectedSpaceId,
      onSelected: (spaceId) =>
          onChanged(spaceId == selectedSpaceId ? null : spaceId),
      onManage: (space) => _manageSpace(
        context,
        ref,
        space,
        // Si era el tema que se estaba mirando, hay que salir de esa vista
        // antes de borrarlo: si no, la lista quedaría filtrando por un tema
        // que ya no existe, vacía sin decir por qué.
        onDeleting: () {
          if (selectedSpaceId == space.id) onChanged(null);
        },
      ),
    );
  }
}

/// El tema en el que está parada una pantalla, fuera del panel de filtros.
///
/// Un número en la insignia de los filtros no alcanza para saber CUÁL tema
/// recorta la lista, y mirar una lista recortada sin saber por qué
/// desorienta. Tocarlo abre el panel —donde se cambia—; la cruz sale del
/// tema. El mismo en la Biblioteca, debajo de la búsqueda, y en el
/// Explorador, debajo del título.
class CurrentSpaceChip extends StatelessWidget {
  const CurrentSpaceChip({
    required this.space,
    required this.onPressed,
    required this.onLeave,
    super.key,
  });

  /// El alto que ocupa con su margen, que la barra de arriba necesita saber
  /// antes de construirlo (`PreferredSize`).
  static const extent = 40.0;

  final Space space;
  final VoidCallback onPressed;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: InputChip(
          avatar: const Icon(Icons.folder_outlined, size: 18),
          label: Text(space.name, overflow: TextOverflow.ellipsis),
          selected: true,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: onPressed,
          onDeleted: onLeave,
          deleteButtonTooltipMessage: l10n.libraryLeaveSpaceTooltip,
        ),
      ),
    );
  }
}

/// La sección sin ningún tema creado: qué es un tema y cómo crear el primero.
///
/// Crear un tema vive, en general, donde se elige uno —al guardar algo o al
/// moverlo, ver `showSpacePickerSheet`—, porque casi siempre se crea para
/// poner algo adentro. Esta es la excepción: sin ningún tema, la sección no
/// tendría nada que tocar, y un callejón sin salida no enseña que filtrar por
/// tema existe.
///
/// El tema recién creado NO queda elegido como filtro: está vacío, y elegirlo
/// dejaría la lista de atrás vacía de golpe, como si se hubiera borrado todo.
/// Aparece como chip en esta misma sección, listo para tocarlo cuando tenga
/// algo adentro.
class _NoSpacesYet extends ConsumerStatefulWidget {
  const _NoSpacesYet();

  @override
  ConsumerState<_NoSpacesYet> createState() => _NoSpacesYetState();
}

class _NoSpacesYetState extends ConsumerState<_NoSpacesYet> {
  var _creating = false;

  /// Por qué no se pudo crear el último tema pedido, si no se pudo. Acá y no
  /// en un aviso al pie: el panel tapa justo la parte de la pantalla donde
  /// aparecería.
  String? _createError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final error = _createError;

    // El mismo borde fino y las mismas esquinas que las tarjetas de la app
    // —ver `cardTheme` en `app_theme.dart`—, sin fondo propio: es un hueco
    // por llenar, no una tarjeta más.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.folder_outlined, size: 20, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.spacesFilterEmptyMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _creating ? null : _create,
                    icon: _creating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.create_new_folder_outlined),
                    label: Text(l10n.spacesNewAction),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pide el nombre, avisa si ya es una etiqueta y crea el tema. Con el
  /// diálogo y el aviso de siempre —los mismos que al crear uno desde el
  /// selector de temas—: un tema nace igual venga de donde venga.
  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;

    final name = await showDialog<String>(
      context: context,
      builder: (context) => SpaceNameDialog(
        title: l10n.spacesNewTitle,
        hint: l10n.spacesNameHint,
        confirmLabel: l10n.commonCreate,
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    if (!await confirmSpaceNameNotATag(
          context,
          ref,
          name,
          action: l10n.spacesNameIsTagCreate,
        ) ||
        !mounted) {
      return;
    }

    setState(() {
      _creating = true;
      _createError = null;
    });
    final result = await ref.read(organizeRepositoryProvider).createSpace(name);
    // Si salió bien, lo normal es que esto ya no esté: con un tema en la
    // lista, la sección pasó a mostrar los chips.
    if (!mounted) return;

    setState(() {
      _creating = false;
      _createError = result.fold(
        (failure) => failure.localizedMessage(l10n),
        (_) => null,
      );
    });
  }
}

/// Los temas de la sección, de a uno: tocar uno lo elige y tocar el elegido
/// lo suelta —es una carpeta en la que se entra y se sale, ver
/// `LibraryQueryNotifier.selectSpace`—.
///
/// `Wrap` y no un desplazamiento horizontal, como el resto del panel: las
/// opciones quedan a la vista de una, en las líneas que hagan falta. Pero los
/// temas pueden ser muchos, así que el área tiene un alto máximo y se
/// desplaza adentro, en vez de volverse una pared que empuje Tipo y lo demás
/// fuera de la vista. Que hay más se ve sin tener que descubrirlo: la última
/// fila queda cortada a la mitad, la barra de desplazamiento está siempre a
/// la vista y el borde de abajo se desvanece mientras quede algo por ver.
///
/// Renombrar o borrar un tema: mantener apretado su chip, o el ícono que
/// lleva el elegido —mantener apretado no se adivina, y el ícono en todos
/// los chips duplicaría el ancho de cada uno—.
class _SpaceFilterChips extends StatefulWidget {
  const _SpaceFilterChips({
    required this.spaces,
    required this.selectedSpaceId,
    required this.onSelected,
    required this.onManage,
  });

  final List<Space> spaces;
  final String? selectedSpaceId;
  final ValueChanged<String> onSelected;
  final ValueChanged<Space> onManage;

  @override
  State<_SpaceFilterChips> createState() => _SpaceFilterChipsState();
}

class _SpaceFilterChipsState extends State<_SpaceFilterChips> {
  static const _spacing = 8.0;

  /// Cuántas filas se ven antes de desplazar. La media de más no es un
  /// descuido: un chip cortado por el borde es la pista más directa de que
  /// la lista sigue.
  static const _visibleRows = 3.5;

  /// El alto del desvanecido del borde de abajo.
  static const _fadeExtent = 24.0;

  final _controller = ScrollController();
  var _overflows = false;
  var _atEnd = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => _sync(_controller.position));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Si hay más de lo que se ve y si ya se llegó al final: deciden si se
  /// muestra la barra y si se desvanece el borde.
  void _sync(ScrollMetrics metrics) {
    final overflows = metrics.maxScrollExtent > 0;
    // Menos de un píxel por ver ya es el final: la posición es un
    // `double`, y el último tramo puede no cerrar exacto.
    final atEnd = metrics.extentAfter < 1;
    if (overflows == _overflows && atEnd == _atEnd) return;
    setState(() {
      _overflows = overflows;
      _atEnd = atEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Un chip ocupa 48 de alto con el margen táctil de un teléfono y 32 sin
    // él, en escritorio: el tope se calcula en filas, no en píxeles fijos,
    // para que muestre las mismas filas en los dos.
    final chipExtent =
        theme.materialTapTargetSize == MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 32.0;
    final fades = _overflows && !_atEnd;

    return ConstrainedBox(
      key: SpaceFilterSection.chipsKey,
      constraints: BoxConstraints(
        maxHeight: (chipExtent + _spacing) * _visibleRows,
      ),
      // Las medidas del contenido llegan recién después de distribuirlo: es
      // lo que dice, sin desplazar nada, si los temas desbordan el tope.
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _sync(notification.metrics);
          return false;
        },
        // Siempre puesto, aunque no desvanezca nada: sacarlo y volver a
        // ponerlo cambiaría la forma del árbol, y la lista volvería a
        // arrancar desde arriba a mitad de desplazarla.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Colors.black,
              if (fades) Colors.transparent else Colors.black,
            ],
            stops: [
              0,
              if (bounds.height > _fadeExtent)
                1 - _fadeExtent / bounds.height
              else
                0,
              1,
            ],
          ).createShader(bounds),
          child: RawScrollbar(
            controller: _controller,
            thumbVisibility: _overflows,
            thickness: 4,
            radius: const Radius.circular(2),
            thumbColor: theme.colorScheme.primary.withValues(alpha: 0.55),
            child: SingleChildScrollView(
              controller: _controller,
              // Aire del lado de la barra, para que no se monte sobre los
              // chips. Fijo, haya o no barra: si apareciera solo al
              // desbordar, los chips se reacomodarían en ese momento.
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Wrap(
                spacing: _spacing,
                runSpacing: _spacing,
                children: [
                  for (final space in widget.spaces)
                    _buildChip(space, l10n: l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(Space space, {required AppLocalizations l10n}) {
    final selected = widget.selectedSpaceId == space.id;

    return GestureDetector(
      onLongPress: () => widget.onManage(space),
      child: FilterChip(
        avatar: const Icon(Icons.folder_outlined, size: 18),
        label: Text(space.name),
        selected: selected,
        onSelected: (_) => widget.onSelected(space.id),
        onDeleted: selected ? () => widget.onManage(space) : null,
        deleteIcon: const Icon(Icons.more_horiz, size: 18),
        deleteButtonTooltipMessage: l10n.librarySpaceManageTooltip,
      ),
    );
  }
}

/// Renombrar o borrar [space], desde su chip en la sección. [onDeleting]
/// corre justo antes de borrarlo, con el borrado ya confirmado.
Future<void> _manageSpace(
  BuildContext context,
  WidgetRef ref,
  Space space, {
  required VoidCallback onDeleting,
}) async {
  final l10n = AppLocalizations.of(context)!;

  final action = await showDialog<_SpaceAction>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(space.name),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(_SpaceAction.rename),
          child: Text(l10n.spacesRenameAction),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(_SpaceAction.delete),
          child: Text(l10n.spacesDeleteAction),
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _SpaceAction.rename:
      await _renameSpace(context, ref, space);
    case _SpaceAction.delete:
      await _deleteSpace(context, ref, space, onDeleting: onDeleting);
  }
}

Future<void> _renameSpace(
  BuildContext context,
  WidgetRef ref,
  Space space,
) async {
  final l10n = AppLocalizations.of(context)!;

  final name = await showDialog<String>(
    context: context,
    builder: (context) => SpaceNameDialog(
      title: l10n.spacesRenameAction,
      hint: l10n.spacesNameHint,
      confirmLabel: l10n.detailSave,
      initialValue: space.name,
    ),
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  // Quedarse con el mismo nombre no es un nombre nuevo que avisar.
  if (normalizeVocabularyLabel(name) != normalizeVocabularyLabel(space.name) &&
      !await confirmSpaceNameNotATag(
        context,
        ref,
        name,
        action: l10n.spacesNameIsTagRename,
      )) {
    return;
  }
  if (!context.mounted) return;

  final result = await ref
      .read(organizeRepositoryProvider)
      .renameSpace(id: space.id, name: name);
  if (!context.mounted) return;

  result.match(
    (failure) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
    (_) {},
  );
}

Future<void> _deleteSpace(
  BuildContext context,
  WidgetRef ref,
  Space space, {
  required VoidCallback onDeleting,
}) async {
  final l10n = AppLocalizations.of(context)!;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(l10n.spacesDeleteConfirm(space.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.spacesDeleteAction),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  onDeleting();
  await ref.read(organizeRepositoryProvider).deleteSpace(space.id);
}

enum _SpaceAction { rename, delete }
