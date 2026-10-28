import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';

/// Adónde abre de verdad el elemento [itemId] cuando alguien pide su detalle
/// (`RoutePaths.itemDetail`): a la pantalla de su documento procesado si lo es
/// (F41) —vivo o en la papelera—, o `null` para seguir al detalle de siempre.
///
/// Un documento procesado es, para la base, una nota de un tipo propio
/// (`NoteKind.processed`) sin texto propio: sus secciones viven en
/// `processed_parts`. El detalle de una nota lo mostraría vacío. Por eso se
/// decide acá, en la ruta por la que pasa todo lo que abre «un elemento» por
/// su id —la búsqueda, las citas del chat, el Mapa, la Línea de tiempo, un
/// enlace—, y no en cada pantalla que lo abre.
///
/// Si no se puede saber —la base falló—, se sigue al detalle: abrir algo, aun
/// con la pantalla de una nota, es mejor que no abrir nada.
Future<String?> processedDocumentRedirect(
  ProcessedRepository repository,
  String itemId,
) async {
  final status = await repository.statusOf(itemId);
  return status.match(
    (_) => null,
    (status) => status == ProcessedDocumentStatus.absent
        ? null
        : RoutePaths.processedDocument(itemId),
  );
}
