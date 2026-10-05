import 'package:dio/dio.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/network/bounded_download.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/domain/media_kind.dart';
import 'package:sinapsis/features/attachments/domain/repositories/attachment_repository.dart';
import 'package:sinapsis/features/attachments/domain/services/attachment_work.dart';
import 'package:sinapsis/features/attachments/domain/services/linked_file_fetcher.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
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
  }) : _attachments = attachments,
       _fetcher = fetcher,
       _maxBytesPerItem = maxBytesPerItem,
       _logger = logger;

  final AttachmentRepository _attachments;
  final LinkedFileFetcher? _fetcher;
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
    return item;
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
