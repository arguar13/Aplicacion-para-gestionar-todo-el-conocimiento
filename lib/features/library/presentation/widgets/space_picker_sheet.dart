import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja de "elegir tema": sin clasificar, o uno de [spaces].
///
/// Compartida entre mover un elemento solo —el menú de tres puntos de cada
/// fila— y mover varios a la vez —el modo de selección múltiple—: las dos
/// pantallas necesitan exactamente la misma lista, y escribirla dos veces
/// solo serviría para que un día se desincronicen.
///
/// Devuelve el `id` elegido, `null` para "sin clasificar", o `void` —sin
/// que el `Future` se resuelva con ningún valor útil— si se cerró sin
/// elegir nada. Un `String?` a secas no alcanza para eso: "cerró sin
/// elegir" y "eligió sin clasificar" vuelven las dos como `null` de
/// `Navigator.pop`, así que hace falta distinguir "no se llegó a elegir
/// nada" de "se eligió que nada es la respuesta" con la propia presencia
/// del resultado, no con su valor.
Future<(String? spaceId,)?> showSpacePickerSheet(
  BuildContext context, {
  required List<Space> spaces,
  String? selectedSpaceId,
}) {
  final l10n = AppLocalizations.of(context)!;

  return showModalBottomSheet<(String?,)>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(l10n.detailSpaceChoose), dense: true),
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: Text(l10n.detailSpaceNone),
            selected: selectedSpaceId == null,
            onTap: () => Navigator.of(context).pop((null,)),
          ),
          for (final space in spaces)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(space.name),
              selected: selectedSpaceId == space.id,
              onTap: () => Navigator.of(context).pop((space.id,)),
            ),
        ],
      ),
    ),
  );
}
