import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';

/// El «Contenido» de los elementos (F30): los archivos bajados de una página
/// y su texto, y la lista de trabajo de lo que falta bajar.
///
/// Aparte del repositorio de la biblioteca a propósito: el elemento que
/// carga la biblioteca no trae su «Contenido» —una página puede traer cien
/// fotos y tres libros, y cada lista y cada búsqueda los arrastraría—. Se
/// pide acá, cuando hace falta, y el texto de cada archivo, recién cuando se
/// lo va a leer.
abstract interface class AttachmentRepository {
  // --- La lista de trabajo -------------------------------------------------

  /// Anota lo que ofrece la página de [itemId], como [status]. Lo que ya
  /// estaba anotado —la misma dirección— queda como estaba: volver a leer la
  /// página no hace volver a bajar lo bajado.
  Future<void> plan(
    String itemId,
    List<AttachmentCandidate> candidates, {
    AttachmentDownloadStatus status = AttachmentDownloadStatus.pending,
  });

  /// La lista de trabajo de [itemId], en el orden de la página.
  Future<List<AttachmentDownload>> downloadsOf(String itemId);

  Stream<List<AttachmentDownload>> watchDownloads(String itemId);

  /// Anota en qué quedó un renglón.
  Future<void> markDownload(
    String downloadId, {
    required AttachmentDownloadStatus status,
    int? expectedBytes,
    String? renditionId,
  });

  /// «Bajar el resto»: lo que quedó afuera por el tope vuelve a estar
  /// pendiente y sin tope; lo que quedó afuera por falta de lugar o no se
  /// pudo bajar, pendiente otra vez (el lugar y el servidor se vuelven a
  /// probar). Devuelve cuántos.
  Future<int> requestRest(String itemId);

  // --- Los archivos ---------------------------------------------------------

  /// Suma un archivo al «Contenido» de [itemId] y devuelve cómo quedó.
  Future<Attachment> addAttachment({
    required String itemId,
    required RenditionKind kind,
    required String relativePath,
    required int position,
    String? title,
    String? originUrl,
    String? mimeType,
    int? sizeBytes,
  });

  /// El «Contenido» de [itemId], en el orden de la página. Sin el texto de
  /// cada archivo: solo cuánto tiene.
  Future<List<Attachment>> attachmentsOf(String itemId);

  Stream<List<Attachment>> watchAttachments(String itemId);

  /// Cuánto pesa todo el «Contenido» de [itemId]: lo que ya cuenta para el
  /// tope.
  Future<int> totalBytes(String itemId);

  /// El texto de un archivo, o `null` si todavía no se le sacó.
  Future<String?> textOf(String attachmentId);

  /// Guarda el texto de un archivo, en lugar del que tuviera. Vacío dice "se
  /// intentó y no tiene".
  Future<void> saveText(
    String attachmentId,
    String text, {
    RenditionKind kind = RenditionKind.plainText,
  });

  /// Saca un archivo del «Contenido», con su texto. Devuelve la ruta del
  /// archivo para borrarlo del disco, o `null` si no estaba.
  Future<String?> removeAttachment(String attachmentId);

  // --- Para la cola ---------------------------------------------------------

  /// Si a [itemId] le queda algo por hacer: algo pendiente de bajar, o un
  /// archivo al que todavía no se le intentó sacar el texto.
  Future<bool> hasWork(String itemId);
}
