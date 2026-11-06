import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';

/// Lo que la pantalla del Índice (F46) lee y escribe: el árbol de lo
/// procesado de a lo que se ve, la búsqueda y cómo va el relleno.
///
/// Cada lectura es un stream que cambia en vivo: lo que llega a Procesado, se
/// borra, se renombra, cambia de tema o se vuelve a indexar se ve solo. Ninguna
/// trae el Índice entero: los temas con sus cuentas en una lectura, los
/// documentos de un tema en otra, y las entradas de un documento solo al
/// desplegarlo. Lo que está en la papelera no aparece.
abstract interface class IndexRepository {
  /// Los temas que tienen documentos del Índice, con cuántos, de la A a la Z
  /// —sin mayúsculas ni acentos—, y «Sin tema» al final si hay alguno sin
  /// tema.
  Stream<List<IndexTopic>> watchTopics();

  /// Los documentos de un tema —[spaceId] `null` es «Sin tema»—, de la A a la
  /// Z. Uno con varios temas está bajo cada uno (decisión D).
  Stream<List<IndexDocument>> watchDocumentsOf(String? spaceId);

  /// Todos los documentos del Índice, en el orden de [order].
  Stream<List<IndexDocument>> watchDocuments(IndexDocumentOrder order);

  /// Las entradas de [documentId] en su orden: sus capítulos —o «Texto
  /// completo»— y después sus imágenes.
  Stream<List<IndexEntry>> watchEntries(String documentId);

  /// Los capítulos y las imágenes de los documentos vivos cuyo título tiene
  /// todas las palabras de [query] —el comienzo de cada una alcanza, sin
  /// mayúsculas ni acentos—, en el orden de los documentos y del texto, cada
  /// uno con sus padres. Como mucho [limit].
  Stream<List<IndexSearchHit>> watchSearch(String query, {int limit = 200});

  /// Las entradas de cada uno de [documentIds], de una vez y sin quedarse
  /// mirando: lo que lleva «Descargar el índice» (F46, paso 4), que necesita
  /// todos los documentos que se ven y no uno por uno. En el mismo orden que
  /// [watchEntries]; un documento sin entradas no está.
  Future<Either<Failure, Map<String, List<IndexEntry>>>> readEntries(
    List<String> documentIds,
  );

  /// Cómo va el relleno.
  Stream<IndexProgress> watchProgress();

  /// Le pone [title] a una imagen de un documento procesado (decisión E):
  /// cambia su entrada del Índice. Un título en blanco no se guarda.
  Future<Either<Failure, Unit>> renameImage(String imageId, String title);
}
