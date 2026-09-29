import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Saca el texto de los documentos guardados como archivo.
///
/// Es **uno solo para todos los formatos** y no uno por formato, porque lo
/// único que cambia entre un PDF, un EPUB y un DOCX es cómo se interpretan
/// los bytes. Traer el archivo del almacén, decidir si hay algo que hacer,
/// armar la forma de contenido y corregir el título es idéntico para los
/// tres; escribirlo tres veces sería tres veces la misma oportunidad de
/// equivocarse. Lo que cambia vive en los [DocumentParser].
class DocumentTransformer implements Transformer {
  const DocumentTransformer({
    required List<DocumentParser> parsers,
    required FileStore files,
    required IdGenerator ids,
    required Clock clock,
    Future<bool> Function(String itemId)? hasConfirmedReference,
  }) : _parsers = parsers,
       _files = files,
       _ids = ids,
       _clock = clock,
       _hasConfirmedReference = hasConfirmedReference;

  final List<DocumentParser> _parsers;
  final FileStore _files;
  final IdGenerator _ids;
  final Clock _clock;

  /// Si el elemento ya tiene datos de referencia confirmados (F15): cuando
  /// los hay, el título y el autor que trae el documento ya no se escriben
  /// solos, aunque el análisis los encuentre — alguien ya completó la
  /// tarjeta «Referencia» a mano, y esa carga tiene la última palabra, no un
  /// análisis que puede llegar después de ella. `null` en las pruebas que no
  /// lo necesitan y en cualquier llamador que no pueda mirar la base: se
  /// comporta como siempre, sin este resguardo.
  final Future<bool> Function(String itemId)? _hasConfirmedReference;

  /// Trabajo largo: un libro de cientos de páginas —y, si está escaneado,
  /// reconocer cada una— no tiene un tope fijo razonable.
  @override
  Duration? get timeLimit => null;

  @override
  bool canTransform(KnowledgeItem item) {
    if (item.source.kind != SourceKind.document) return false;
    if (item.source.originalFilePath == null) return false;

    // Ya tiene contenido: no se vuelve a leer. Sin esta comprobación, cada
    // pasada de la cola volvería a parsear el mismo PDF de mil páginas.
    return item.renditions.isEmpty;
  }

  @override
  Future<KnowledgeItem> transform(KnowledgeItem item) async {
    final path = item.source.originalFilePath!;

    final bytes = await _files.read(path);
    if (bytes == null) throw MissingOriginalFileException(path);

    // Se le pasa el nombre, no solo los bytes: un `.txt` y un `.md` no
    // empiezan con ninguna firma, así que sin el nombre quedarían sin
    // reconocer y sin leer. El nombre sale de la ruta del almacén, que
    // conserva el original ya saneado.
    final format = detectFileFormat(bytes, name: p.basename(path));
    final parser = _parsers.where((p) => p.canParse(format)).firstOrNull;

    // Ningún lector para este formato: un `.zip`, un `.odt`, algo que no se
    // reconoció. Se devuelve el elemento **sin tocar**, y el caso de uso lo
    // marca listo. No se lanza a propósito: un fallo pondría el elemento en
    // rojo y ofrecería reintentar algo que nunca va a funcionar, cuando en
    // realidad no pasó nada malo — el archivo está guardado y a salvo, que
    // es lo que importaba.
    if (parser == null) return item;

    final parsed = await parser.parse(bytes);
    if (parsed.isEmpty) return item;

    final now = _clock();
    final confirmed = await _hasConfirmedReference?.call(item.id) ?? false;

    return item.copyWith(
      // Lo que diga el documento gana sobre el nombre del archivo: un PDF
      // llamado `descarga (3).pdf` puede tener un título de verdad adentro.
      // Salvo que alguien ya haya confirmado la referencia a mano: eso no se
      // pisa (F15).
      title: confirmed ? item.title : (parsed.title ?? item.title),
      source: item.source.copyWith(
        authorName: confirmed
            ? item.source.authorName
            : (parsed.author ?? item.source.authorName),
      ),
      renditions: [
        Rendition.text(
          id: _ids.next(),
          itemId: item.id,
          kind: RenditionKind.markdown,
          content: parsed.markdown,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
  }
}
