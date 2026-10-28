import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/attachments/domain/media_kind.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';

/// Las imágenes que ofrece una fuente para Procesado (F41, decisión L), leídas
/// sin tocarla y sin abrir ninguna. Es la única forma de listarlas, para la
/// grilla de la hoja y para el caso de uso que las copia.
///
/// Cómo guarda hoy sus imágenes cada fuente, y de dónde salen acá:
///
/// - **Una imagen o una captura** (`SourceKind.image`) es su archivo
///   (`source.original_blob_path`): un enlace directo a una foto también
///   termina así (F30).
/// - **Una publicación** guarda su primera foto como su archivo, si no trae
///   video, y las demás del carrusel en su «Contenido» (F30).
/// - **Una página web guardada** baja las fotos de su artículo, en su versión
///   más grande, a su «Contenido» (F30, `findPageAttachments`). La página
///   archivada lleva además una copia de cada una incrustada como datos, junto
///   con los íconos y la decoración de la página entera: esas no se listan.
///   Son las mismas fotos —repetidas, y a veces más chicas— y sacarlas
///   obligaría a leer y decodificar un archivo de hasta 25 MB para mostrar
///   una grilla.
///
/// Lo que se lista: el archivo de la fuente, si es una imagen, y después las
/// fotos de su «Contenido» y cualquier otra forma de imagen con archivo, en el
/// orden de la página. Fuera quedan los SVG: no hay con qué dibujarlos en la
/// grilla ni en la galería, y elegir es mirar.
///
/// Barato y paginado: la lista sale de la base de a tramos, sin traer nada que
/// no sea su fila, y el peso se mide en el disco solo cuando la base no lo
/// sabe —el archivo de la fuente, que no lo guarda—.
class SourceImagesReader {
  const SourceImagesReader(this._db, this._files);

  final AppDatabase _db;
  final FileStore _files;

  /// Las imágenes de [sourceItemId], en orden: el tramo desde [offset] y, con
  /// [limit], solo esas. Vacío si no es una fuente o no tiene ninguna.
  Future<List<SourceImage>> list(
    String sourceItemId, {
    int offset = 0,
    int? limit,
  }) async {
    assert(offset >= 0, 'Un tramo empieza en 0 o más.');
    final own = await _ownImage(sourceItemId);
    final images = <SourceImage>[];
    var contentOffset = offset;
    var contentLimit = limit;
    if (own != null) {
      if (offset == 0) {
        if (limit == 0) return const [];
        images.add(own);
        if (contentLimit != null) contentLimit--;
      } else {
        contentOffset--;
      }
    }
    if (contentLimit == 0) return images;
    final rows = await _db
        .customSelect(
          'SELECT relative_path, size_bytes, title, mime_type '
          'FROM renditions r WHERE $_contentImageSql '
          'ORDER BY COALESCE(r.position, -1), r.created_at, r.id '
          'LIMIT ?3 OFFSET ?4',
          variables: [
            Variable.withString(sourceItemId),
            Variable.withString(own?.path ?? ''),
            Variable.withInt(contentLimit ?? -1),
            Variable.withInt(contentOffset),
          ],
          readsFrom: {_db.renditions},
        )
        .get();
    for (final row in rows) {
      final path = row.read<String>('relative_path');
      final size =
          row.readNullable<int>('size_bytes') ?? await _files.sizeOf(path);
      images.add(
        SourceImage(
          path: path,
          origin: SourceImageOrigin.content,
          sizeBytes: size ?? 0,
          title: _clean(row.readNullable<String>('title')),
          mimeType: row.readNullable<String>('mime_type'),
        ),
      );
    }
    return images;
  }

  /// Cuántas imágenes ofrece [sourceItemId] y cuánto pesan todas juntas.
  Future<SourceImagesSummary> summary(String sourceItemId) async {
    final own = await _ownImage(sourceItemId);
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n, COALESCE(SUM(size_bytes), 0) AS bytes '
          'FROM renditions r WHERE $_contentImageSql',
          variables: [
            Variable.withString(sourceItemId),
            Variable.withString(own?.path ?? ''),
          ],
          readsFrom: {_db.renditions},
        )
        .getSingle();
    var bytes = row.read<int>('bytes');
    // Lo que la base no sabe cuánto pesa —una forma de antes de F30— se mide
    // en el disco: son pocas, si hay alguna.
    final unsized = await _db
        .customSelect(
          'SELECT relative_path FROM renditions r '
          'WHERE $_contentImageSql '
          'AND r.size_bytes IS NULL',
          variables: [
            Variable.withString(sourceItemId),
            Variable.withString(own?.path ?? ''),
          ],
          readsFrom: {_db.renditions},
        )
        .get();
    for (final unsizedRow in unsized) {
      final path = unsizedRow.read<String>('relative_path');
      bytes += await _files.sizeOf(path) ?? 0;
    }
    return SourceImagesSummary(
      count: row.read<int>('n') + (own == null ? 0 : 1),
      sizeBytes: bytes + (own?.sizeBytes ?? 0),
    );
  }

  /// El archivo de la fuente, si es una imagen que se puede mostrar.
  Future<SourceImage?> _ownImage(String sourceItemId) async {
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(sourceItemId))).getSingleOrNull();
    final path = source?.originalBlobPath;
    if (source == null || path == null || _isSvg(path)) return null;
    final isImage =
        source.sourceType == SourceKind.image ||
        mediaKindOf(fileName: p.basename(path)) == RenditionKind.image;
    if (!isImage) return null;
    final size = await _files.sizeOf(path);
    // Sin el archivo en el teléfono —alguien vació el almacenamiento—, no hay
    // qué copiar ni qué mostrar.
    if (size == null) return null;
    return SourceImage(
      path: path,
      origin: SourceImageOrigin.original,
      sizeBytes: size,
    );
  }

  /// Las formas de imagen con archivo de la fuente —el primer parámetro de la
  /// consulta—, sin el archivo de la fuente misma —el segundo— ni los SVG.
  static const _contentImageSql =
      "r.item_id = ?1 AND r.kind = 'image' "
      'AND r.relative_path IS NOT NULL AND r.relative_path <> ?2 '
      "AND lower(r.relative_path) NOT LIKE '%.svg' "
      "AND lower(COALESCE(r.mime_type, '')) NOT LIKE 'image/svg%'";

  static bool _isSvg(String path) => p.extension(path).toLowerCase() == '.svg';

  static String? _clean(String? title) {
    final trimmed = title?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
