import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre lo que nombra un `[[Título]]` de una nota de bloques: busca un
/// elemento por título exacto —sin distinguir mayúsculas— y navega a su
/// detalle. Lo usan el detalle de la nota y su lectura (F46, paso 5j).
///
/// Un `[[Título]]` que ya no coincide con nada —porque el elemento se borró,
/// o porque le cambiaron el nombre después de escrito el enlace— avisa en vez
/// de fallar en silencio: el vínculo de verdad (`Relations`, el que alimenta
/// el Grafo) ya quedó creado al escribirlo, así que solo el texto quedó
/// desactualizado.
///
/// `list()`, no `libraryItemsProvider`: ese es un `StreamProvider` pensado
/// para que un widget lo mire con `ref.watch` desde su propio `build`, no
/// para leerlo una sola vez desde un manejador de toque como este — hacerlo
/// así deja una suscripción activa que `autoDispose` nunca llega a soltar, y
/// la próxima operación contra la base que dependa de esa misma conexión se
/// queda esperando para siempre.
Future<void> openNoteLink(
  BuildContext context,
  WidgetRef ref,
  String title,
) async {
  final l10n = AppLocalizations.of(context)!;
  final normalized = title.trim().toLowerCase();
  // Sin el texto: solo se busca un título, y traer los libros enteros de
  // toda la biblioteca para eso era memoria de más.
  final allItems =
      (await ref
              .read(libraryRepositoryProvider)
              .list(const LibraryQuery(), withText: false))
          .getRight()
          .toNullable() ??
      const <KnowledgeItem>[];
  final target = allItems
      .where((i) => i.title.trim().toLowerCase() == normalized)
      .firstOrNull;
  if (!context.mounted) return;

  if (target == null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showAppSnackBar(
        AppSnackBar(content: Text(l10n.detailLinkNotFound(title))),
      );
    return;
  }

  unawaited(context.push(RoutePaths.itemDetail(target.id)));
}
