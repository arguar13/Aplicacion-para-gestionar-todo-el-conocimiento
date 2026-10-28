import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';

/// Abre lo que se tocó en el Atlas, el Mapa, el grafo local o la Línea de
/// tiempo (F41, paso 6): desde ahí, casi siempre un documento procesado.
///
/// Es el único punto por el que esas pantallas abren un elemento. Va al
/// detalle por id, y esa ruta lleva sola a la pantalla del documento procesado
/// cuando el id es uno (`processedDocumentRedirect`, paso 2): así sirve igual
/// para una nota mapa del Atlas, que sigue abriéndose en su detalle.
Future<void> openOrganizedItem(BuildContext context, String itemId) =>
    context.push(RoutePaths.itemDetail(itemId));
