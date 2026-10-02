import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_picker_sheet.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El tema de algo que todavía no se guardó: elegir uno de los que hay, crear
/// uno nuevo o dejarlo sin tema, con la hoja de `showSpacePickerSheet`.
///
/// Solo elige: no le asigna nada a nadie. Lo elegido vuelve por [onChanged] y
/// quien guarda lo manda junto con el resto, en el mismo guardado —ver
/// `CaptureRequest.spaceId`—, así un elemento nunca queda guardado a medias,
/// sin el tema que se le pidió.
///
/// Dos formas para el mismo dato: un campo como los demás del formulario de
/// captura, y un chip compacto para el editor de notas, donde un campo con
/// borde entre el título y el primer bloque pesaría más que lo escrito.
class SpaceField extends ConsumerStatefulWidget {
  /// Un campo con borde y etiqueta, como `CustomTextField`.
  const SpaceField({required this.spaceId, required this.onChanged, super.key})
    : _compact = false;

  /// Un chip, para donde un campo con borde desentona.
  const SpaceField.compact({
    required this.spaceId,
    required this.onChanged,
    super.key,
  }) : _compact = true;

  /// El tema elegido, o `null` si no hay ninguno.
  final String? spaceId;
  final ValueChanged<String?> onChanged;
  final bool _compact;

  @override
  ConsumerState<SpaceField> createState() => _SpaceFieldState();
}

class _SpaceFieldState extends ConsumerState<SpaceField> {
  /// El último tema elegido en la hoja. Hace falta para uno recién creado:
  /// entre que la hoja lo devuelve y `allSpacesProvider` vuelve a emitir con
  /// él adentro pasa un instante, y sin esto el campo parpadearía vacío.
  Space? _lastPicked;
  var _hovering = false;

  Space? _current(List<Space> spaces) {
    final id = widget.spaceId;
    if (id == null) return null;
    return spaces.where((space) => space.id == id).firstOrNull ??
        (_lastPicked?.id == id ? _lastPicked : null);
  }

  Future<void> _choose() async {
    final chosen = await showSpacePickerSheet(
      context,
      selectedSpaceId: widget.spaceId,
    );
    if (chosen == null || !mounted) return;

    final (space,) = chosen;
    setState(() => _lastPicked = space);
    widget.onChanged(space?.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];
    final current = _current(spaces);

    if (widget._compact) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: current == null
            ? ActionChip(
                avatar: const Icon(Icons.folder_outlined, size: 18),
                label: Text(l10n.detailSpaceChoose),
                onPressed: _choose,
              )
            : InputChip(
                avatar: const Icon(Icons.folder_outlined, size: 18),
                label: Text(current.name),
                onPressed: _choose,
                onDeleted: () => widget.onChanged(null),
                deleteButtonTooltipMessage: l10n.captureSpaceClear,
              ),
      );
    }

    // Un `InputDecorator` y no un `TextField` de solo lectura: acá no se
    // escribe nada, se elige, y un campo de texto se anunciaría como tal a
    // un lector de pantalla y mostraría un cursor al tocarlo. Sin `border:`
    // ni colores propios —mismo motivo que en `CustomTextField`—: todo sale
    // del `inputDecorationTheme`, así se ve igual que los campos vecinos.
    return InkWell(
      onTap: _choose,
      onHover: (hovering) => setState(() => _hovering = hovering),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: current == null,
        isHovering: _hovering,
        decoration: InputDecoration(
          labelText: l10n.captureSpaceLabel,
          prefixIcon: const Icon(Icons.folder_outlined),
          suffixIcon: current == null
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.captureSpaceClear,
                  onPressed: () => widget.onChanged(null),
                ),
        ),
        child: Text(
          current?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
