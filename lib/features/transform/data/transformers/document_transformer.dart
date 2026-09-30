import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_checkpoints.dart';
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
    ProcessingCheckpoints? checkpoints,
  }) : _parsers = parsers,
       _checkpoints = checkpoints,
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

  /// Dónde se guarda el avance de un trabajo largo —las páginas escaneadas
  /// ya reconocidas— para retomarlo si se interrumpe (F21). `null` en las
  /// pruebas que no lo necesitan: se hace todo de un tirón, como siempre.
  final ProcessingCheckpoints? _checkpoints;

  /// Sacar el texto que el documento ya trae es trabajo corto —segundos,
  /// incluso con cientos de páginas—, con el tope del carril corto: un motor
  /// trabado no frena la cola. Reconocer páginas escaneadas es largo, y el
  /// lector pasa al carril largo para eso, donde el tope fijo no corre.
  @override
  Duration? get timeLimit => kShortTransformTimeLimit;

  @override
  bool canTransform(KnowledgeItem item) {
    if (item.source.kind != SourceKind.document) return false;
    if (item.source.originalFilePath == null) return false;

    // Ya tiene contenido: no se vuelve a leer. Sin esta comprobación, cada
    // pasada de la cola volvería a parsear el mismo PDF de mil páginas.
    return item.renditions.isEmpty;
  }

  @override
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
    final path = item.source.originalFilePath!;

    // Sin traerlo a memoria: cada lector decide cuánto necesita (F21). Un
    // PDF de cientos de páginas se abre desde el disco.
    final size = await _files.sizeOf(path);
    final head = await _files.readHead(path, maxBytes: 64 * 1024);
    if (size == null || head == null) throw MissingOriginalFileException(path);

    // Se le pasa el nombre, no solo los bytes: un `.txt` y un `.md` no
    // empiezan con ninguna firma, así que sin el nombre quedarían sin
    // reconocer y sin leer. El nombre sale de la ruta del almacén, que
    // conserva el original ya saneado.
    final name = p.basename(path);
    final format = detectFileFormat(head, name: name);
    final parser = _parsers.where((p) => p.canParse(format)).firstOrNull;

    // Ningún lector para este formato: un `.zip`, un `.odt`, algo que no se
    // reconoció. Se devuelve el elemento **sin tocar**, y el caso de uso lo
    // marca listo. No se lanza a propósito: un fallo pondría el elemento en
    // rojo y ofrecería reintentar algo que nunca va a funcionar, cuando en
    // realidad no pasó nada malo — el archivo está guardado y a salvo, que
    // es lo que importaba.
    if (parser == null) return item;

    final parsed = await parser.parse(
      DocumentSource(
        name: name,
        size: size,
        localPath: await _files.localPathOf(path),
        readAll: () async {
          final bytes = await _files.read(path);
          if (bytes == null) throw MissingOriginalFileException(path);
          return bytes;
        },
        readRange: (start, length) async {
          final bytes = await _files.readRange(
            path,
            start: start,
            length: length,
          );
          if (bytes == null) throw MissingOriginalFileException(path);
          return bytes;
        },
      ),
      session: _sessionFor(item, context),
    );
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
          // Markdown solo lo que se convierte con esa forma —títulos, listas—:
          // un Word, un EPUB, un `.md`. El texto de un PDF o de un `.txt` es
          // el del original tal cual (F22).
          kind:
              const {
                FileFormat.docx,
                FileFormat.epub,
                FileFormat.markdown,
              }.contains(format)
              ? RenditionKind.markdown
              : RenditionKind.plainText,
          content: parsed.markdown,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
  }

  DocumentParseSession _sessionFor(
    KnowledgeItem item,
    TransformContext context,
  ) {
    final checkpoints = _checkpoints;
    if (checkpoints == null) return DocumentParseSession(context: context);

    return DocumentParseSession(
      context: context,
      loadRecognizedPages: () =>
          checkpoints.load(item.id, ProcessingCheckpointKind.ocrPage),
      saveRecognizedPage: (page, text) => checkpoints.save(
        item.id,
        ProcessingCheckpointKind.ocrPage,
        position: page,
        content: text,
      ),
    );
  }
}
