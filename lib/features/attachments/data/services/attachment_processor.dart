import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/network/bounded_download.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/domain/media_kind.dart';
import 'package:sinapsis/features/attachments/domain/repositories/attachment_repository.dart';
import 'package:sinapsis/features/attachments/domain/services/archive_expander.dart';
import 'package:sinapsis/features/attachments/domain/services/attachment_work.dart';
import 'package:sinapsis/features/attachments/domain/services/linked_file_fetcher.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// La subcarpeta de la del elemento donde va su «Contenido».
const kAttachmentsFolder = 'contenido';

/// Baja el «Contenido» de un elemento (F30, decisiones D y E).
///
/// Recorre la lista de trabajo del elemento —lo que anotó su página— y baja
/// lo pendiente **de a uno**, en el orden de la decisión E: primero los
/// documentos, después los audios, las fotos y por último los videos; dentro
/// de cada grupo, en el orden de la página. Cada archivo:
///
/// - se baja acotado a lo que queda del tope por elemento —el tope se aplica
///   mientras baja, no después—, de a uno por servidor y solo de internet
///   (ver `LinkedFileFetcher`);
/// - si no entra, queda **afuera** y se sigue con el siguiente, que puede
///   ser más chico: así entra todo lo que entra. Lo que la persona pidió con
///   «Bajar el resto» no tiene tope; el espacio libre, sí;
/// - si llega una página en vez de un archivo —un enlace que terminaba en
///   `.pdf` pero no lo era—, o el servidor dice que no, queda **fallido**,
///   sin guardar nada;
/// - lo bajado queda en `originales/<fuente>/contenido/`, con su nombre y sin
///   pisar a otro, y entra al «Contenido» con lo que se sabe de él.
///
/// Cada paso queda escrito apenas se da: si la app se cierra a mitad de
/// camino, lo bajado no se vuelve a bajar.
class AttachmentProcessor implements AttachmentWork {
  AttachmentProcessor({
    required AttachmentRepository attachments,
    required LinkedFileFetcher? fetcher,
    required int Function() maxBytesPerItem,
    required AppLogger logger,
    ArchiveExpander? archives,
    FileStore? files,
    List<DocumentParser> parsers = const [],
    AudioTranscriber? transcriber,
    ImageTextExtractor? imageText,
  }) : _parsers = parsers,
       _transcriber = transcriber,
       _imageText = imageText,
       _attachments = attachments,
       _fetcher = fetcher,
       _archives = archives,
       _files = files,
       _maxBytesPerItem = maxBytesPerItem,
       _logger = logger;

  final AttachmentRepository _attachments;
  final LinkedFileFetcher? _fetcher;

  /// Quien abre los `.zip`; sin él, se guardan cerrados.
  final ArchiveExpander? _archives;

  /// El almacén: para borrar un `.zip` ya descomprimido y para leer cada
  /// archivo al sacarle el texto.
  final FileStore? _files;

  /// Los lectores de documentos, el que transcribe y el que lee las fotos:
  /// los mismos de cada elemento, para el texto de cada archivo.
  final List<DocumentParser> _parsers;
  final AudioTranscriber? _transcriber;
  final ImageTextExtractor? _imageText;
  final int Function() _maxBytesPerItem;
  final AppLogger _logger;

  /// Lo más que se baja de un archivo pedido con «Bajar el resto», que no
  /// tiene tope por elemento: lo frena el espacio libre, y esto, que es más
  /// de lo que cualquier archivo de una página pesa.
  static const maxForcedBytes = 64 * 1024 * 1024 * 1024;

  @override
  Duration? get timeLimit => null;

  @override
  bool canTransform(KnowledgeItem item) => true;

  @override
  Future<bool> hasWork(String itemId) async {
    // Sin quien baje (la web), lo pendiente no es trabajo que se pueda hacer.
    if (_fetcher == null) return false;
    return _attachments.hasWork(itemId);
  }

  @override
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
    final fetcher = _fetcher;
    if (fetcher == null) return item;
    await context.enterLongLane();

    final pending = [
      for (final download in await _attachments.downloadsOf(item.id))
        if (download.status == AttachmentDownloadStatus.pending) download,
    ]..sort(_byPriority);
    // El avance va en milésimos de archivo: cada archivo es un tramo de la
    // barra, y la bajada en curso lo va llenando.
    final total = pending.length * _steps;
    var done = 0;
    context.reportProgress(done, total);

    var used = await _attachments.totalBytes(item.id);
    for (final download in pending) {
      context.throwIfCancelled();
      final base = done;
      used += await _download(
        item,
        download,
        fetcher,
        context,
        used: used,
        onProgress: _progressReporter(context, base: base, total: total),
      );
      done += _steps;
      context.reportProgress(done, total);
    }

    await _extractTexts(item, context);
    return item;
  }

  // --- El texto de cada archivo -------------------------------------------

  /// Le saca el texto a cada archivo del «Contenido» que todavía no lo
  /// tiene (decisión D): lo que dice un libro o un documento, la
  /// transcripción de un audio o un video, lo que se lee en una foto. En el
  /// orden de la decisión E, y de a uno: es trabajo largo, en el carril
  /// largo.
  ///
  /// Lo que no tiene texto —una foto sin letras, un formato que nadie
  /// lee— queda con un texto vacío: «se intentó». Lo que no se pudo hacer
  /// todavía —el modelo de transcripción no está bajado— queda sin texto, y
  /// se retoma la próxima vez que se procese el elemento.
  Future<void> _extractTexts(
    KnowledgeItem item,
    TransformContext context,
  ) async {
    final files = _files;
    if (files == null) return;
    final pending =
        [
          for (final attachment in await _attachments.attachmentsOf(item.id))
            if (attachment.canHaveText && !attachment.textAttempted) attachment,
        ]..sort((a, b) {
          final byGroup = a.group.index.compareTo(b.group.index);
          return byGroup != 0 ? byGroup : a.position.compareTo(b.position);
        });
    for (final (index, attachment) in pending.indexed) {
      context
        ..throwIfCancelled()
        ..reportProgress(index, pending.length);
      try {
        final text = await _textOf(attachment, item, files, context);
        if (text == null) continue;
        await _attachments.saveText(attachment.id, text.$1, kind: text.$2);
      } on ProcessingCancelledException {
        rethrow;
      } on WhisperModelNotReadyException {
        // Sin el modelo no se transcribe: queda para cuando esté.
        _logger.info('Sin modelo para transcribir ${attachment.fileName}.');
      } on Exception catch (e) {
        if (context.isCancelled) throw const ProcessingCancelledException();
        // Un archivo que no se deja leer —dañado, cifrado, un formato raro—
        // no frena a los demás: queda intentado y sin texto.
        _logger.warning('No se le sacó el texto a ${attachment.fileName}: $e');
        await _attachments.saveText(attachment.id, '');
      }
    }
    context.reportProgress(pending.length, pending.length);
  }

  /// El texto de [attachment] y su clase, o `null` si todavía no se puede.
  Future<(String, RenditionKind)?> _textOf(
    Attachment attachment,
    KnowledgeItem item,
    FileStore files,
    TransformContext context,
  ) async {
    final path = attachment.relativePath;
    switch (attachment.kind) {
      case RenditionKind.image:
        final reader = _imageText;
        if (reader == null) return null;
        // Un SVG es un dibujo vectorial: no hay foto que leer.
        if (path.toLowerCase().endsWith('.svg')) {
          return ('', RenditionKind.plainText);
        }
        final local = kIsWeb ? path : await files.resolve(path);
        return (await reader.extractText(local), RenditionKind.plainText);
      case RenditionKind.audio || RenditionKind.video:
        final transcriber = _transcriber;
        if (transcriber == null) return null;
        await context.enterLongLane();
        final local = kIsWeb ? path : await files.resolve(path);
        final transcript = await transcriber.transcribe(
          local,
          language: item.source.language ?? defaultTranscriptionLanguage,
          session: TranscriptionSession(context: context),
        );
        return (transcript.text, RenditionKind.plainText);
      case RenditionKind.pdf || RenditionKind.document:
        return _readDocument(path, files, context);
      case _:
        return null;
    }
  }

  /// Lo que dice un documento, con el lector que le corresponda; vacío si
  /// ninguno lo sabe leer (un `.doc` viejo, un `.odt`).
  Future<(String, RenditionKind)> _readDocument(
    String path,
    FileStore files,
    TransformContext context,
  ) async {
    final size = await files.sizeOf(path);
    final head = await files.readHead(path, maxBytes: 64 * 1024);
    if (size == null || head == null) throw MissingOriginalFileException(path);
    final name = path.split('/').last;
    final format = detectFileFormat(head, name: name);
    final parser = _parsers.where((p) => p.canParse(format)).firstOrNull;
    if (parser == null) return ('', RenditionKind.plainText);

    final parsed = await parser.parse(
      DocumentSource(
        name: name,
        size: size,
        localPath: await files.localPathOf(path),
        readAll: () async {
          final bytes = await files.read(path);
          if (bytes == null) throw MissingOriginalFileException(path);
          return bytes;
        },
        readRange: (start, length) async {
          final bytes = await files.readRange(
            path,
            start: start,
            length: length,
          );
          if (bytes == null) throw MissingOriginalFileException(path);
          return bytes;
        },
      ),
      session: DocumentParseSession(context: context),
    );
    // Markdown solo lo que se convierte con esa forma, como en el
    // transformador de documentos (F22).
    final markdown = const {
      FileFormat.docx,
      FileFormat.epub,
      FileFormat.markdown,
    }.contains(format);
    return (
      parsed.markdown,
      markdown ? RenditionKind.markdown : RenditionKind.plainText,
    );
  }

  /// Primero los documentos, después los audios, las fotos y los videos; en
  /// cada grupo, el orden de la página.
  static int _byPriority(AttachmentDownload a, AttachmentDownload b) {
    final byGroup = a.group.index.compareTo(b.group.index);
    return byGroup != 0 ? byGroup : a.position.compareTo(b.position);
  }

  /// Baja [download] y devuelve cuánto ocupó (0 si no se guardó).
  Future<int> _download(
    KnowledgeItem item,
    AttachmentDownload download,
    LinkedFileFetcher fetcher,
    TransformContext context, {
    required int used,
    required void Function(int received, int? total) onProgress,
  }) async {
    final cap = _maxBytesPerItem();
    final remaining = download.forced ? maxForcedBytes : cap - used;
    final expected = download.expectedBytes;
    if (remaining <= 0 || (expected != null && expected > remaining)) {
      await _attachments.markDownload(
        download.id,
        status: AttachmentDownloadStatus.leftOut,
      );
      return 0;
    }

    try {
      final fetched = await fetcher.fetch(
        download.url,
        storeId: item.source.id,
        folder: kAttachmentsFolder,
        maxBytes: remaining,
        preferredName: _fileNameFor(download),
        // Una página no es un archivo: un enlace a `.pdf` que lleva a una
        // página de descarga se descarta sin bajarla.
        accept: (type) =>
            type != 'text/html' && type != 'application/xhtml+xml',
        whenCancelled: context.whenCancelled,
        onProgress: onProgress,
      );
      if (isZipArchive(
        contentType: fetched.contentType,
        fileName: fetched.fileName,
      )) {
        final expanded = await _expand(
          item,
          download,
          fetched,
          room: remaining,
        );
        if (expanded != null) return expanded;
      }
      final kind =
          mediaKindOf(
            contentType: fetched.contentType,
            fileName: fetched.fileName,
          ) ??
          download.kind;
      final attachment = await _attachments.addAttachment(
        itemId: item.id,
        kind: kind,
        relativePath: fetched.relativePath,
        position: download.position,
        title: download.title,
        originUrl: download.url.toString(),
        mimeType: fetched.contentType,
        sizeBytes: fetched.bytes,
      );
      await _attachments.markDownload(
        download.id,
        status: AttachmentDownloadStatus.done,
        expectedBytes: fetched.bytes,
        renditionId: attachment.id,
      );
      return fetched.bytes;
    } on DownloadTooLargeException catch (e) {
      await _attachments.markDownload(
        download.id,
        status: AttachmentDownloadStatus.leftOut,
        expectedBytes: e.declared,
      );
    } on NotEnoughSpaceException {
      await _attachments.markDownload(
        download.id,
        status: AttachmentDownloadStatus.noSpace,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel || context.isCancelled) {
        throw const ProcessingCancelledException();
      }
      _logger.warning('No se pudo bajar ${download.url}: $e');
      await _attachments.markDownload(
        download.id,
        status: AttachmentDownloadStatus.failed,
      );
    } on Exception catch (e) {
      // Cualquier otro motivo de este archivo —una dirección de la red
      // local, un tipo que no se quiere, un corte que no se arregló— es de
      // este archivo: queda fallido, y se sigue con los demás.
      _logger.warning('No se bajó ${download.url}: $e');
      await _attachments.markDownload(
        download.id,
        status: AttachmentDownloadStatus.failed,
      );
    }
    return 0;
  }

  /// Descomprime un `.zip` recién bajado en el «Contenido» —cada archivo
  /// con la ruta que traía adentro como título, en el lugar del `.zip` en
  /// la página— y lo borra: lo que importa es lo de adentro, en su formato.
  /// Devuelve cuánto ocupa lo sacado, o `null` si no se abrió —sin quien lo
  /// abra, o porque era hostil o desmedido—: entonces queda el `.zip` tal
  /// cual, como un archivo más.
  ///
  /// Lo descomprimido no pasa de [room], lo que quedaba del tope cuando se
  /// lo empezó a bajar: el `.zip` se borra, y su lugar lo ocupa lo de
  /// adentro.
  Future<int?> _expand(
    KnowledgeItem item,
    AttachmentDownload download,
    FetchedFile zip, {
    required int room,
  }) async {
    final archives = _archives;
    if (archives == null) return null;
    final List<ExpandedFile> expanded;
    try {
      expanded = await archives.expand(
        zip.relativePath,
        storeId: item.source.id,
        folder: kAttachmentsFolder,
        maxBytes: room,
      );
    } on UnsafeArchiveException catch (e) {
      _logger.warning('${download.url}: $e');
      return null;
    }

    var bytes = 0;
    for (final file in expanded) {
      final name = file.entryName.split('/').last;
      await _attachments.addAttachment(
        itemId: item.id,
        kind: mediaKindOf(fileName: name) ?? RenditionKind.file,
        relativePath: file.relativePath,
        position: download.position,
        title: file.entryName,
        originUrl: download.url.toString(),
        sizeBytes: file.bytes,
      );
      bytes += file.bytes;
    }
    await _files?.delete(zip.relativePath);
    await _attachments.markDownload(
      download.id,
      status: AttachmentDownloadStatus.done,
      expectedBytes: zip.bytes,
    );
    return bytes;
  }

  /// El nombre con que se guarda: el texto del enlace para un documento,
  /// un audio o un video —"Informe anual 2026", que es lo que se reconoce—,
  /// si es corto; el del servidor para una foto, cuyo título suele ser una
  /// oración entera.
  static String? _fileNameFor(AttachmentDownload download) {
    final title = download.title?.trim();
    if (title == null || title.isEmpty || title.length > 80) return null;
    return download.kind == RenditionKind.image ? null : title;
  }

  static const _steps = 1000;

  /// Avisa el avance de la bajada en curso de a un mega: lo que mantiene
  /// despierto al vigilante del carril largo con un archivo de cientos de
  /// megas, sin avisarle por cada pedacito. Si el servidor no dijo cuánto
  /// pesa, la barra no se mueve pero el aviso llega igual.
  static void Function(int received, int? total) _progressReporter(
    TransformContext context, {
    required int base,
    required int total,
  }) {
    var nextReport = 0;
    return (received, size) {
      if (received < nextReport) return;
      nextReport = received + 1024 * 1024;
      final part = size == null || size <= 0
          ? 0
          : (received * _steps ~/ size).clamp(0, _steps - 1);
      context.reportProgress(base + part, total);
    };
  }
}
