import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/library/presentation/widgets/spaces_picker_sheet.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los temas de algo que todavía no se guardó (F37): chips que se sacan con
/// su ✕, y la hoja de `showSpacesPickerSheet` para marcar otros o crear uno.
///
/// Solo elige: no le asigna nada a nadie. Lo elegido vuelve por [onChanged] y
/// quien guarda lo manda junto con el resto, en el mismo guardado —ver
/// `CaptureRequest.spaceIds`—, así un elemento nunca queda guardado a medias,
/// sin los temas que se le pidieron.
///
/// Con [requireOne] nunca queda vacío por un toque: sacar el último chip no
/// se puede, y lo dice.
///
/// Dos formas para el mismo dato: un campo como los demás del formulario de
/// captura, y chips sueltos para el editor de notas, donde un campo con borde
/// entre el título y el primer bloque pesaría más que lo escrito.
class SpacesField extends ConsumerStatefulWidget {
  /// Un campo con borde y etiqueta, como `CustomTextField`.
  const SpacesField({
    required this.spaceIds,
    required this.onChanged,
    this.requireOne = false,
    super.key,
  }) : _compact = false;

  /// Chips sueltos, para donde un campo con borde desentona.
  const SpacesField.compact({
    required this.spaceIds,
    required this.onChanged,
    this.requireOne = false,
    super.key,
  }) : _compact = true;

  /// Los temas elegidos. Uno que no existe —uno de la última vez que se borró
  /// después— no se muestra.
  final Set<String> spaceIds;
  final ValueChanged<Set<String>> onChanged;
  final bool requireOne;
  final bool _compact;

  @override
  ConsumerState<SpacesField> createState() => _SpacesFieldState();
}

class _SpacesFieldState extends ConsumerState<SpacesField> {
  /// Los últimos elegidos en la hoja. Hace falta para uno recién creado: entre
  /// que la hoja lo devuelve y `allSpacesProvider` vuelve a emitir con él
  /// adentro pasa un instante, y sin esto su chip parpadearía.
  var _lastPicked = const <Space>[];
  var _hovering = false;

  List<Space> _current(List<Space> spaces) {
    final known = {for (final space in spaces) space.id};
    return [
      for (final space in spaces)
        if (widget.spaceIds.contains(space.id)) space,
      for (final space in _lastPicked)
        if (widget.spaceIds.contains(space.id) && !known.contains(space.id))
          space,
    ];
  }

  Future<void> _choose() async {
    final chosen = await showSpacesPickerSheet(
      context,
      selected: widget.spaceIds,
      requireOne: widget.requireOne,
    );
    if (chosen == null || !mounted) return;

    setState(() => _lastPicked = chosen);
    widget.onChanged({for (final space in chosen) space.id});
  }

  void _remove(Space space, List<Space> current) {
    if (widget.requireOne && current.length == 1) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.spacesKeepOne)));
      return;
    }
    widget.onChanged({
      for (final other in current)
        if (other.id != space.id) other.id,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];
    final current = _current(spaces);
    final chips = [
      for (final space in current)
        InputChip(
          avatar: const Icon(Icons.folder_outlined, size: 18),
          label: Text(space.name),
          onPressed: _choose,
          onDeleted: () => _remove(space, current),
          deleteButtonTooltipMessage: l10n.spacesRemove(space.name),
        ),
    ];

    if (widget._compact) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ...chips,
            ActionChip(
              avatar: Icon(
                current.isEmpty ? Icons.folder_outlined : Icons.add,
                size: 18,
              ),
              label: Text(
                current.isEmpty ? l10n.spacesChoose : l10n.spacesAddMore,
              ),
              onPressed: _choose,
            ),
          ],
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
        isEmpty: current.isEmpty,
        isHovering: _hovering,
        decoration: InputDecoration(
          labelText: l10n.spacesLabel,
          prefixIcon: const Icon(Icons.folder_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          errorText: widget.requireOne && current.isEmpty
              ? l10n.spacesPickerNeedOne
              : null,
        ),
        child: current.isEmpty
            ? const SizedBox.shrink()
            : Wrap(spacing: 8, runSpacing: 4, children: chips),
      ),
    );
  }
}
