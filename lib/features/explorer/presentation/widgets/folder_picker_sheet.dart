import 'package:flutter/material.dart';
import 'package:sinapsis/features/explorer/domain/entities/folder.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja de "elegir carpeta": el árbol entero, indentado por nivel, para
/// agregar un elemento a una de ellas.
///
/// Sin una opción de "nivel raíz" — a diferencia de `showSpacePickerSheet`,
/// acá no hay una carpeta real a la que volver: un elemento sin ninguna fila
/// en `ItemFolders` ya aparece solo en la raíz del Explorador, así que "sacar
/// de todo" se hace desde el menú del elemento (`explorerRemoveFromFolder`),
/// no eligiendo acá.
///
/// Devuelve el `id` de la carpeta elegida, o `null` si se cerró sin elegir.
Future<String?> showFolderPickerSheet(
  BuildContext context, {
  required List<Folder> folders,
}) {
  final l10n = AppLocalizations.of(context)!;
  final flat = _flattenTree(folders);

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n.explorerPickFolderTitle), dense: true),
            if (flat.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text(
                  l10n.explorerEmptyRootMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: flat.length,
                  itemBuilder: (context, index) {
                    final (folder, depth) = flat[index];
                    return ListTile(
                      contentPadding: EdgeInsets.only(
                        left: 16 + depth * 20,
                        right: 16,
                      ),
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(folder.name),
                      onTap: () => Navigator.of(context).pop(folder.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// El árbol de [folders] en orden de recorrido en profundidad —cada carpeta
/// seguida inmediatamente de sus subcarpetas—, con el nivel de cada una para
/// poder indentarla.
List<(Folder, int)> _flattenTree(List<Folder> folders) {
  final byParent = <String?, List<Folder>>{};
  for (final folder in folders) {
    (byParent[folder.parentId] ??= []).add(folder);
  }
  for (final children in byParent.values) {
    children.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  final result = <(Folder, int)>[];
  void visit(String? parentId, int depth) {
    for (final folder in byParent[parentId] ?? const <Folder>[]) {
      result.add((folder, depth));
      visit(folder.id, depth + 1);
    }
  }

  visit(null, 0);
  return result;
}
