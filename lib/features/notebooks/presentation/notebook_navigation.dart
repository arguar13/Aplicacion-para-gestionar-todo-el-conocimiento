/// A dónde llevan los cuadernos (F41, paso 5): el único lugar que lo sabe.
///
/// Un cuaderno tiene solo documentos procesados, así que tocar uno abre ese
/// documento, y su vacío lleva a donde se consiguen: «Procesado» y la Bandeja.
/// Las direcciones viven acá, y no repartidas por las pantallas.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';

/// Abre el documento procesado [documentId], en su pantalla (paso 2). Se
/// apila encima del cuaderno: volver deja el cuaderno como estaba.
void openProcessedDocument(BuildContext context, String documentId) =>
    unawaited(context.push(RoutePaths.processedDocument(documentId)));

/// Va a «Procesado», a elegir qué agregar. Es `go` y no `push`: es un destino
/// de la barra, no una pantalla que se apila encima.
void openProcessedList(BuildContext context) =>
    context.go(RoutePaths.processed);

/// Va a la Bandeja, a triar. Es `go` y no `push`, por lo mismo.
void openInboxToTriage(BuildContext context) => context.go(RoutePaths.inbox);
