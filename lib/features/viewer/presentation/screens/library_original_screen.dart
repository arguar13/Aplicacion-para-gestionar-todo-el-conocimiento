import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_heading.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/open_document_viewer.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El original de un elemento de la Biblioteca a pantalla completa, con su
/// propia dirección (F46, paso 5c): lo que abre «Abrir en el original» desde
/// un capítulo del Índice cuando Procesado no guardó su propia copia —al
/// «Pasar todo» se pasa solo el texto—, pero el documento conoce su fuente.
///
/// Es **la misma pantalla** que abre «Ver la página» o «Leer como libro»
/// desde el detalle del elemento (`openDocumentViewer`, que la arma con
/// `libraryOriginalScreenOf`): el mismo visor, las mismas fichas que marcan
/// sobre la fuente y nada en rojo —de la Biblioteca nada se borra—. Acá se
/// abre además en un lugar: un PDF, en la página [page]; una página web, en
/// el título [heading], que se resalta un momento.
///
/// Si el elemento ya no está o su original no se lee en un visor, lo dice.
class LibraryOriginalScreen extends ConsumerWidget {
  const LibraryOriginalScreen({
    required this.itemId,
    this.page,
    this.heading,
    super.key,
  });

  final String itemId;

  /// La página del PDF en que se abre, desde 1.
  final int? page;

  /// El título de la página web en que se abre.
  final ArchivedHeading? heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final item = ref.watch(libraryItemProvider(itemId));
    final found = item.valueOrNull;
    final resolved = found == null
        ? null
        : ref.watch(resolvedFileViewerProvider(found));

    if (item.isLoading && found == null ||
        resolved != null && resolved.isLoading && !resolved.hasValue) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final value = resolved?.valueOrNull;
    final screen = found == null || value == null
        ? null
        : libraryOriginalScreenOf(found, value, page: page, heading: heading);
    return screen ??
        Scaffold(
          key: const Key('library-original-missing'),
          appBar: AppBar(),
          body: EmptyStateView(
            icon: Icons.file_copy_outlined,
            title: l10n.failureMissingOriginalFile,
          ),
        );
  }
}
