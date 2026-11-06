import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_rows.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/headings_extractor.dart';
import 'package:sinapsis/features/processed/domain/services/headings/pdf_outline_reader.dart';
import 'package:sinapsis/features/processed/domain/services/headings/processed_headings.dart';
import 'package:sinapsis/features/processed/domain/services/headings/settle_headings.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

/// Qué hizo [ProcessedHeadingsIndexer.refresh] con un documento.
enum HeadingsRefresh {
  /// No tiene texto: no tiene capítulos que sacar (sus imágenes, si tiene, las
  /// lleva la base sola).
  noText,

  /// Ya tenía sus entradas de texto: nada cambió desde la última vez.
  upToDate,

  /// Se leyeron y se guardaron sus entradas de texto.
  indexed,

  /// Es un PDF que nadie leyó antes de la transacción (`prepare`): queda «sin
  /// indexar», y lo hace el relleno, que lo lee primero.
  deferred,

  /// El puerto falló: el documento queda «sin indexar», y se reintenta.
  failed,
}

/// El PDF de un documento procesado, para leerle los marcadores: el archivo,
/// relativo al almacén, y la clave con que se guarda lo que se leyó de él.
typedef _Pdf = ({String path, String key});

/// Escribe las entradas de texto del Índice de un documento procesado (F46,
/// paso 2): sus capítulos —lo que lee el paso 1, `readProcessedHeadings`, por
/// [HeadingsExtractor]— o, si no tiene, «Texto completo». Ver
/// `ProcessedHeadings`.
///
/// Se lo llama en la misma transacción que escribe el texto
/// (`ProcessedRepositoryImpl`), y desde el relleno para lo que quedó sin
/// indexar (`ProcessedHeadingsBackfill`). Rehace solo las de ese documento, y
/// solo si hace falta: lo que cambió el texto ya soltó sus entradas viejas en
/// la misma sentencia (`processedHeadingStaleTriggers`), así que «sin
/// indexar» —tener texto y ninguna entrada de texto— es exactamente «hay que
/// rehacerlo».
///
/// **El PDF se lee antes de la transacción** ([prepare]): es un archivo y es
/// PDFium, y mientras una transacción está abierta la base no atiende a nadie
/// más. Lo leído queda guardado por archivo —un original no se reescribe:
/// otro archivo es otra ruta—, así que corregir una página de un libro no lo
/// vuelve a abrir: los marcadores son los mismos, y solo se rehacen las
/// filas, porque los lugares se corren.
class ProcessedHeadingsIndexer {
  ProcessedHeadingsIndexer({
    required AppDatabase database,
    required HeadingsExtractor extractor,
    required PdfOutlineReader outlines,
    required FileStore files,
    required TelemetryService telemetry,
    this.cachedOutlines = 64,
    this.outlineTimeout = const Duration(seconds: 20),
  }) : _db = database,
       _extractor = extractor,
       _outlineReader = outlines,
       _files = files,
       _telemetry = telemetry;

  final AppDatabase _db;
  final HeadingsExtractor _extractor;
  final PdfOutlineReader _outlineReader;
  final FileStore _files;
  final TelemetryService _telemetry;

  /// Cuántos PDF leídos se recuerdan: los últimos usados.
  final int cachedOutlines;

  /// Cuánto se espera a PDFium. Un PDF que no responde no deja esperando el
  /// guardado de un texto: pasado este tiempo, el documento queda para el
  /// relleno, que lo vuelve a intentar.
  final Duration outlineTimeout;

  /// Lo que se leyó de cada PDF, por su clave; `null` si no se pudo leer —está
  /// cortado, cifrado o ya no está—, y entonces valen los títulos de la IA.
  final _outlines = <String, PdfOutline?>{};

  // --- Antes de la transacción ----------------------------------------------

  /// Lee, si hace falta, el PDF que va a usar [refresh] con [documentId]: el
  /// de su copia del original o, si no tiene, el de su fuente. Va SIEMPRE
  /// afuera de toda transacción.
  ///
  /// Quien está por cambiar la copia la nombra: [incomingCopy], la que está
  /// por entrar y la base todavía no tiene. Un documento que todavía no
  /// existe se busca por su fuente, [sourceItemId].
  Future<void> prepare(
    String documentId, {
    String? sourceItemId,
    ({String path, int? size})? incomingCopy,
  }) async {
    final candidates = <_Pdf?>[
      if (incomingCopy != null) _pdfAt(incomingCopy.path, incomingCopy.size),
      await _copyOf(documentId),
      await _sourceFileOf(documentId, sourceItemId: sourceItemId),
    ];
    for (final pdf in candidates.nonNulls) {
      await _read(pdf);
    }
  }

  Future<void> _read(_Pdf pdf) async {
    if (_outlines.containsKey(pdf.key)) {
      _outlines[pdf.key] = _outlines.remove(pdf.key);
      return;
    }
    final size = await _files.sizeOf(pdf.path);
    PdfOutline? outline;
    if (size != null) {
      try {
        outline = await _outlineReader
            .read(_documentAt(pdf.path, size))
            .timeout(outlineTimeout);
      } on UnreadableDocumentException {
        outline = null;
        // Cualquier otra falla —el disco, PDFium, que no responda— no se
        // recuerda: el documento queda para el relleno, que lo vuelve a
        // intentar.
        // ignore: avoid_catches_without_on_clauses
      } catch (e, stackTrace) {
        _telemetry.recordError(
          e,
          stackTrace,
          hint: 'ProcessedHeadingsIndexer: no se leyó ${pdf.path}',
        );
        return;
      }
    }
    _outlines[pdf.key] = outline;
    while (_outlines.length > cachedOutlines) {
      _outlines.remove(_outlines.keys.first);
    }
  }

  DocumentSource _documentAt(String path, int size) => DocumentSource(
    name: p.basename(path),
    size: size,
    readAll: () async =>
        await _files.read(path) ?? (throw MissingOriginalFileException(path)),
    readRange: (start, length) async =>
        await _files.readRange(path, start: start, length: length) ??
        (throw MissingOriginalFileException(path)),
  );

  // --- En la transacción ----------------------------------------------------

  /// Indexa [documentId] si está sin indexar. Corre en la transacción de
  /// quien llama —es un punto de guardado dentro de ella— o en una propia:
  /// leer las páginas, sacar los capítulos y guardarlos es una sola cosa, y
  /// nada que se escriba en el medio la deja a medias.
  ///
  /// Si el puerto falla, no escribe nada, lo anota y devuelve
  /// [HeadingsRefresh.failed]: el texto que se estaba guardando se guarda
  /// igual, y el documento queda para el relleno. Lo mismo, sin anotar nada,
  /// si es un PDF que no se leyó antes ([HeadingsRefresh.deferred]).
  Future<HeadingsRefresh> refresh(String documentId) => _db.transaction(
    () async {
      final state = await _stateOf(documentId);
      if (!state.hasText) return HeadingsRefresh.noText;
      if (state.indexed) return HeadingsRefresh.upToDate;

      final pdf = await _copyOf(documentId) ?? await _sourceFileOf(documentId);
      final kind = processedTextKindOf(
        markdown: await processedTextIsMarkdown(_db, documentId),
        originalFileName: pdf?.path,
      );
      if (kind == ProcessedTextKind.pdf && !_outlines.containsKey(pdf!.key)) {
        return HeadingsRefresh.deferred;
      }
      final pages = await _pagesOf(documentId);
      final List<ProcessedHeading> found;
      try {
        found = await _extractor.headingsOf(
          ProcessedHeadingsSource(
            pages: pages,
            kind: kind,
            pdf: kind == ProcessedTextKind.pdf ? _outlines[pdf!.key] : null,
          ),
        );
        // Cualquier falla del puerto —también un `Error`— deja el documento
        // sin indexar y nada más: el texto se guarda igual.
        // ignore: avoid_catches_without_on_clauses
      } catch (e, stackTrace) {
        _telemetry.recordError(
          e,
          stackTrace,
          hint: 'ProcessedHeadingsIndexer: documentId=$documentId',
        );
        return HeadingsRefresh.failed;
      }
      final length = pages.fold(0, (sum, page) => sum + page.length);
      await _write(documentId, settleHeadings(found, textLength: length));
      return HeadingsRefresh.indexed;
    },
  );

  /// Si [documentId] tiene texto, y si tiene sus entradas de texto. Dos
  /// búsquedas por clave: `idx_processed_parts_document` e
  /// `idx_processed_headings_document`.
  Future<({bool hasText, bool indexed})> _stateOf(String documentId) async {
    final row = await _db
        .customSelect(
          'SELECT EXISTS (SELECT 1 FROM processed_parts '
          "WHERE document_id = ?1 AND section = 'text') AS has_text, "
          'EXISTS (SELECT 1 FROM processed_headings '
          "WHERE document_id = ?1 AND origin <> 'image') AS indexed",
          variables: [Variable.withString(documentId)],
          readsFrom: {_db.processedParts, _db.processedHeadings},
        )
        .getSingle();
    return (
      hasText: row.read<bool>('has_text'),
      indexed: row.read<bool>('indexed'),
    );
  }

  /// Las páginas de «Texto» de [documentId], en orden: una detrás de la otra
  /// son su texto propio.
  Future<List<String>> _pagesOf(String documentId) {
    final pp = _db.processedParts;
    return (_db.selectOnly(pp)
          ..addColumns([pp.content])
          ..where(
            pp.documentId.equals(documentId) &
                pp.section.equalsValue(ProcessedSection.text),
          )
          ..orderBy([OrderingTerm.asc(pp.position), OrderingTerm.asc(pp.id)]))
        .map((row) => row.read(pp.content)!)
        .get();
  }

  /// La copia del original de [documentId], si tiene una y es un PDF.
  Future<_Pdf?> _copyOf(String documentId) async {
    final row =
        await (_db.select(_db.processedOriginals).join([
              innerJoin(
                _db.renditions,
                _db.renditions.id.equalsExp(_db.processedOriginals.renditionId),
              ),
            ])..where(_db.processedOriginals.documentId.equals(documentId)))
            .getSingleOrNull();
    final rendition = row?.readTable(_db.renditions);
    final path = rendition?.relativePath;
    if (path == null) return null;
    return _pdfAt(path, rendition!.sizeBytes);
  }

  /// El archivo de la fuente de [documentId] —o de [sourceItemId], si el
  /// documento todavía no existe—, si es un PDF. Solo se lee: de la
  /// Biblioteca nada se toca.
  Future<_Pdf?> _sourceFileOf(String documentId, {String? sourceItemId}) async {
    final sourceId =
        sourceItemId ??
        (await (_db.select(
              _db.processedDocuments,
            )..where((d) => d.itemId.equals(documentId))).getSingleOrNull())
            ?.sourceItemId;
    if (sourceId == null) return null;
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(sourceId))).getSingleOrNull();
    final path = source?.originalBlobPath;
    return path == null ? null : _pdfAt(path, null);
  }

  /// [path], si es un PDF —por su nombre, como `processedTextKindOf`—, con su
  /// clave: la ruta y, si se sabe, cuánto pesa.
  _Pdf? _pdfAt(String path, int? size) =>
      p.extension(path).toLowerCase() == '.pdf'
      ? (path: path, key: '$path#${size ?? ''}')
      : null;

  /// Escribe como entradas de texto de [documentId] los capítulos
  /// [headings], en su orden, o «Texto completo» si no tiene ninguno. No hay
  /// ninguna que soltar: se llega acá solo si el documento está sin indexar,
  /// en la misma transacción que lo comprobó.
  Future<void> _write(
    String documentId,
    List<ProcessedHeading> headings,
  ) async {
    final rows = headings.isNotEmpty
        ? headings
        : const [
            // Un texto en blanco: el lector no le da título, y el documento
            // igual tiene que poder abrirse desde el Índice.
            ProcessedHeading(
              order: 0,
              level: 1,
              title: '',
              origin: ProcessedHeadingOrigin.wholeText,
              start: 0,
              end: 0,
              textPage: 1,
            ),
          ];
    await _db.batch((batch) {
      for (final heading in rows) {
        batch.insert(
          _db.processedHeadings,
          ProcessedHeadingsCompanion.insert(
            documentId: documentId,
            origin: indexEntryOriginOf(heading.origin),
            level: heading.level,
            position: heading.order,
            title: heading.title,
            textStart: Value(heading.start),
            textEnd: Value(heading.end),
            textPage: Value(heading.textPage),
            pdfPage: Value(heading.pdfPage),
          ),
        );
      }
    });
  }
}

/// El origen con que se guarda un título leído con [origin]: el mismo, por su
/// nombre (`IndexEntryOrigin`).
IndexEntryOrigin indexEntryOriginOf(ProcessedHeadingOrigin origin) =>
    switch (origin) {
      ProcessedHeadingOrigin.bookmark => IndexEntryOrigin.bookmark,
      ProcessedHeadingOrigin.textHeading => IndexEntryOrigin.textHeading,
      ProcessedHeadingOrigin.aiTitle => IndexEntryOrigin.aiTitle,
      ProcessedHeadingOrigin.wholeText => IndexEntryOrigin.wholeText,
    };
