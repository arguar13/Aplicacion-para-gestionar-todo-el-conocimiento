import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sinapsis/core/util/external_url_launcher.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El menú que aparece al seleccionar texto en la app: siempre las mismas
/// opciones y en el mismo orden —Copiar, Compartir, Seleccionar todo, Leer
/// en voz alta, Resaltar, Extraer como nota, Crear tarjeta y Buscar en la
/// Web— (pedido del usuario). Las que no tienen sentido en un texto —no
/// hay nada seleccionado, o ese texto no se resalta— no aparecen; las demás
/// no cambian de lugar.
///
/// Por qué no el menú que arma Flutter: en Android le suma una opción por
/// cada app instalada que acepta texto —"Preguntar a ChatGPT", "Preguntar a
/// Gemini", traductores…—, el menú se volvía una lista larga detrás de los
/// tres puntos y lo propio de la app quedaba perdido entre lo ajeno. De lo
/// de Flutter se toman solo Copiar, Compartir y Seleccionar todo, con su
/// comportamiento de siempre. "Buscar en la Web" Flutter lo ofrece solo en
/// iOS; acá lo hace la app, igual en todas.
///
/// Cada opción propia cierra el menú antes de actuar, como las de Flutter.
List<ContextMenuButtonItem> selectionMenuItems(
  BuildContext context,
  EditableTextState editable, {
  VoidCallback? onReadAloud,
  VoidCallback? onHighlight,
  VoidCallback? onExtract,
  VoidCallback? onCreateFlashcard,
}) {
  final l10n = AppLocalizations.of(context)!;
  final value = editable.textEditingValue;
  final selected = value.selection.isValid
      ? value.selection.textInside(value.text).trim()
      : '';
  final hasSelection = selected.isNotEmpty;

  ContextMenuButtonItem? fromFlutter(ContextMenuButtonType type) {
    for (final item in editable.contextMenuButtonItems) {
      if (item.type == type) return item;
    }
    return null;
  }

  ContextMenuButtonItem? own(String label, VoidCallback? action) {
    if (!hasSelection || action == null) return null;
    return ContextMenuButtonItem(
      label: label,
      onPressed: () {
        ContextMenuController.removeAny();
        action();
      },
    );
  }

  return [
    fromFlutter(ContextMenuButtonType.copy),
    fromFlutter(ContextMenuButtonType.share),
    fromFlutter(ContextMenuButtonType.selectAll),
    own(l10n.readAloudTooltip, onReadAloud),
    own(l10n.detailHighlightSelection, onHighlight),
    own(l10n.detailExtractSelection, onExtract),
    own(l10n.flashcardsFromSelection, onCreateFlashcard),
    if (hasSelection)
      ContextMenuButtonItem(
        // Con el tipo, el texto lo pone Flutter, traducido: "Buscar en la
        // Web".
        type: ContextMenuButtonType.searchWeb,
        onPressed: () {
          ContextMenuController.removeAny();
          unawaited(searchWeb(selected));
        },
      ),
  ].nonNulls.toList();
}

/// [selectionMenuItems] ya armado como menú, junto a la selección: lo que
/// usa un texto seleccionable que no agrega nada propio salvo, quizás,
/// leer en voz alta.
Widget buildSelectionMenu(
  BuildContext context,
  EditableTextState editable, {
  VoidCallback? onReadAloud,
}) => AdaptiveTextSelectionToolbar.buttonItems(
  anchors: editable.contextMenuAnchors,
  buttonItems: selectionMenuItems(context, editable, onReadAloud: onReadAloud),
);

/// Busca [text] en la web, en el navegador del teléfono.
Future<bool> searchWeb(String text) => launchExternalUrl(
  Uri.https('www.google.com', '/search', {'q': text}).toString(),
);
