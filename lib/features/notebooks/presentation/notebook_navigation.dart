/// A dónde llevan los cuadernos (F41, paso 5): el único lugar que lo sabe.
///
/// Un cuaderno tiene solo documentos procesados, así que tocar uno abre ese
/// documento, y su vacío lleva a donde se consiguen: «Procesado» y la Bandeja.
/// Las direcciones viven acá, y no repartidas por las pantallas, para que la
/// de «Procesado» se cambie en un solo renglón.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';

/// Abre el documento procesado [documentId].
///
/// Mientras «Procesado» no tenga su pantalla (paso 2), lo abre el detalle de
/// elemento, como a cualquier elemento de la bóveda.
void openProcessedDocument(BuildContext context, String documentId) =>
    unawaited(context.push(RoutePaths.itemDetail(documentId)));

/// La dirección de la lista de «Procesado», o `null` mientras no tenga
/// pantalla (paso 2): sin ella, el vacío de un cuaderno ofrece solo la
/// Bandeja.
const String? processedListPath = null;

/// Va a la Bandeja, a triar. Es `go` y no `push`: la Bandeja es un destino de
/// la barra, no una pantalla que se apila encima.
void openInboxToTriage(BuildContext context) => context.go(RoutePaths.inbox);
