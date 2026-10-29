import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:sinapsis/core/storage/file_store.dart';

/// Dónde viven las ilustraciones de una creación (F43, decisión H): en el
/// almacén de archivos de la app (`FileStore`), en
/// `originales/<id de la creación>/ilustraciones/`, y no en la base.
///
/// Fuera de la base por lo mismo que los originales (ver `FileStore`): una
/// presentación con siete ilustraciones pesa varios megas, y «Lo creado» se
/// relee entero cada vez que algo cambia. En el contenido de la creación va
/// solo la ruta (`Slide.illustrationRef`).
///
/// Así sobreviven a cerrar la app, viajan en la copia de la bóveda —que lleva
/// la carpeta `originales/` entera— y la unión de bóvedas copia las que
/// faltan (`OriginalFilesMerge`, con `studyCreationFilesSql`, que las
/// encuentra por su `illustration_ref`). Cuando la creación se borra para
/// siempre, se van con su carpeta (`StudyCreationRepository.purge`, con
/// `FileStore.deleteAllOf`).
class CreationIllustrationFiles {
  const CreationIllustrationFiles(this._store);

  final FileStore _store;

  /// La subcarpeta de la creación donde van.
  static const folder = 'ilustraciones';

  /// Desde cuántos bytes una PNG o una WebP se guarda como JPEG: una
  /// ilustración de 1024 px en PNG pesa más de un mega, y en JPEG de buena
  /// calidad, la décima parte, sin diferencia a la vista en una diapositiva.
  static const recompressAbove = 600 * 1024;

  /// La calidad del JPEG de [recompressAbove].
  static const jpegQuality = 88;

  /// Guarda la ilustración de la diapositiva [slide] (desde 0) de
  /// [creationId] y devuelve su ruta: la que va en `illustrationRef`. Nunca
  /// pisa otra —«diapositiva-3-2.jpg» si ya hay una—.
  Future<String> save({
    required String creationId,
    required int slide,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    var data = bytes;
    var type = mimeType;
    if (type != 'image/jpeg' && data.length > recompressAbove) {
      final jpeg = await compute(_toJpeg, data);
      if (jpeg != null && jpeg.length < data.length) {
        data = jpeg;
        type = 'image/jpeg';
      }
    }
    return _store.saveStream(
      bytes: Stream.value(data),
      suggestedName: 'diapositiva-${slide + 1}.${_extensionOf(type)}',
      id: creationId,
      folder: folder,
      unique: true,
    );
  }

  /// Los bytes de [path], o `null` si ya no está (se vació el almacenamiento
  /// de la app): la diapositiva dibuja la de reserva.
  Future<Uint8List?> read(String path) => _store.read(path);

  /// Borra [path] si es de [creationId] —de su carpeta de ilustraciones—, y
  /// nada si no. Una ruta del contenido puede venir de otra bóveda: nunca se
  /// borra un archivo que no es de esta creación por lo que diga un JSON.
  Future<void> delete(String creationId, String path) async {
    if (!isOwnedBy(creationId, path)) return;
    await _store.delete(path);
  }

  /// Si [path] es una ilustración guardada por [creationId].
  static bool isOwnedBy(String creationId, String path) {
    final prefix = 'originales/$creationId/$folder/';
    if (!path.startsWith(prefix) || path.contains('..')) return false;
    final name = path.substring(prefix.length);
    return name.isNotEmpty && !name.contains('/');
  }

  static String _extensionOf(String mimeType) => switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'png',
  };
}

/// [bytes] como JPEG, o `null` si no se pudo leer la imagen o tiene partes
/// transparentes —el JPEG no las tiene, y saldrían negras—. Corre en otro
/// hilo (`compute`): decodificar una PNG de un mega trabaría la pantalla.
Uint8List? _toJpeg(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null || image.numChannels == 4) return null;
  return img.encodeJpg(image, quality: CreationIllustrationFiles.jpegQuality);
}
