import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_store.dart';

/// Dónde viven las ilustraciones con IA de «Lo creado» (F43, decisión H): las
/// de una infografía, un mazo o un cuestionario. En el almacén de los
/// originales, como cualquier archivo de la bóveda, en
/// `originales/<creación>/ilustraciones/`.
///
/// Fuera de la base, por lo mismo que los originales (ver `FileStore`): una
/// creación con diez imágenes de un mega dentro de su fila haría lenta la
/// lista de «Lo creado», que lee las filas enteras. Afuera, el contenido
/// guarda solo la ruta (`illustration_ref`), y así:
///
/// - **sobreviven a cerrar la app**: el almacén es el directorio de
///   documentos, no la caché;
/// - **viajan en la copia de la bóveda**, que lleva la carpeta de los
///   originales entera;
/// - **y en la unión de bóvedas**, que copia los archivos que alguna fila
///   nombra (`studyCreationFilesSql`);
/// - **se van al borrarla para siempre** (`FileStore.deleteAllOf`).
class CreationIllustrationStore {
  const CreationIllustrationStore(this._files);

  final FileStore _files;

  /// La subcarpeta, dentro de la de la creación.
  static const folder = 'ilustraciones';

  /// Guarda [bytes] como la ilustración del lugar [slotId] de [creationId] y
  /// devuelve su ruta. Nunca pisa otra: rehacer una deja la nueva al lado
  /// («block-3-2.png») hasta que la vieja se borra.
  Future<String> save({
    required String creationId,
    required String slotId,
    required Uint8List bytes,
    required String mimeType,
  }) => _files.saveStream(
    bytes: Stream.value(bytes),
    suggestedName: '$slotId.${_extensionOf(mimeType)}',
    id: creationId,
    folder: folder,
    unique: true,
  );

  /// Los bytes de [reference], o `null` si ya no está.
  Future<Uint8List?> read(String reference) => _files.read(reference);

  /// Borra [reference]; no falla si ya no estaba.
  Future<void> delete(String reference) => _files.delete(reference);

  /// Borra [references] sin fallar.
  Future<void> deleteQuietly(Iterable<String> references) async {
    for (final reference in references) {
      try {
        await delete(reference);
        // Un archivo que no se pudo borrar no deshace lo dibujado ni tapa una
        // cancelación.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
  }

  static String _extensionOf(String mimeType) => switch (mimeType) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/webp' => 'webp',
    _ => 'png',
  };
}
