import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/data/creation_files.dart';

/// Dónde viven las ilustraciones con IA de «Lo creado» (F43, decisión H): las
/// de todos los tipos —la infografía, la presentación, el mazo, el
/// cuestionario—. En el almacén de los originales, como cualquier archivo de
/// la bóveda, en `originales/<creación>/ilustraciones/`.
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
///
/// **Solo borra lo de la propia creación** ([isCreationFile], la misma regla
/// que la unión de bóvedas): una ruta del contenido puede venir de otra
/// bóveda, y nunca se borra el archivo de otra creación ni el original de un
/// documento por lo que diga un JSON.
class CreationIllustrationStore {
  CreationIllustrationStore(this._files);

  final FileStore _files;

  /// La subcarpeta, dentro de la de la creación.
  static const folder = kCreationIllustrationsFolder;

  /// Desde cuántos bytes una que no es JPEG se guarda como JPEG: una
  /// ilustración de 1024 px en PNG pesa más de un mega, y en JPEG de buena
  /// calidad, la décima parte, sin diferencia a la vista.
  static const recompressAbove = 600 * 1024;

  /// La calidad de los JPEG que se guardan.
  static const jpegQuality = 88;

  /// Guarda [bytes] como la ilustración del lugar [slotId] de [creationId] y
  /// devuelve su ruta. Nunca pisa otra: rehacer una deja la nueva al lado
  /// («block-3-2.png») hasta que la vieja se borra.
  ///
  /// Antes, la ajusta ([fitCreationIllustration]): achicada a [maxSide] si se
  /// pide y, si no es JPEG y pesa, como JPEG —sin transparencia—.
  Future<String> save({
    required String creationId,
    required String slotId,
    required Uint8List bytes,
    required String mimeType,
    int? maxSide,
  }) async {
    final fitted = await fitCreationIllustration(
      bytes,
      mimeType,
      maxSide: maxSide,
    );
    return _files.saveStream(
      bytes: Stream.value(fitted.bytes),
      suggestedName: '$slotId.${_extensionOf(fitted.mimeType)}',
      id: creationId,
      folder: folder,
      unique: true,
    );
  }

  /// Los bytes de [reference], o `null` si ya no está.
  Future<Uint8List?> read(String reference) => _files.read(reference);

  /// Borra [reference] si es de [creationId] ([isCreationFile]), y nada si
  /// no; no falla si ya no estaba.
  Future<void> delete(String creationId, String reference) async {
    if (!isCreationFile(creationId, reference)) return;
    await _files.delete(reference);
  }

  /// Borra las de [references] que son de [creationId], sin fallar: lo
  /// dibujado en una vuelta que se canceló, lo que se reemplazó.
  Future<void> deleteQuietly(
    String creationId,
    Iterable<String> references,
  ) async {
    for (final reference in references) {
      try {
        await delete(creationId, reference);
        // Un archivo que no se pudo borrar no deshace lo dibujado ni tapa una
        // cancelación.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
  }

  static String _extensionOf(String mimeType) => switch (mimeType) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'png',
  };
}

/// Una ilustración lista para guardarse.
typedef FittedIllustration = ({Uint8List bytes, String mimeType});

/// [bytes] como se guardan ([fitCreationIllustrationSync]), en otro hilo si
/// hay que leer la imagen: decodificar una PNG de un mega trabaría la
/// pantalla.
Future<FittedIllustration> fitCreationIllustration(
  Uint8List bytes,
  String mimeType, {
  int? maxSide,
}) {
  if (maxSide == null && !_wantsJpeg(bytes, mimeType)) {
    return Future.value((bytes: bytes, mimeType: mimeType));
  }
  return Isolate.run(
    () => fitCreationIllustrationSync(bytes, mimeType, maxSide: maxSide),
  );
}

/// [bytes] achicada a [maxSide] de lado mayor, si se pide y es más grande, y
/// como JPEG si no lo era y se achicó o pesa más de
/// `CreationIllustrationStore.recompressAbove` —solo si queda más chica—.
///
/// Una con partes transparentes nunca pasa a JPEG, que no las tiene y las
/// pondría negras: achicada, queda PNG. Una que no se puede leer —un formato
/// raro— queda tal cual.
FittedIllustration fitCreationIllustrationSync(
  Uint8List bytes,
  String mimeType, {
  int? maxSide,
}) {
  final asIs = (bytes: bytes, mimeType: mimeType);
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
    // Los bytes los manda un proveedor de afuera: un formato que el lector no
    // entiende puede tirar cualquier cosa en vez de devolver null.
  } on Object {
    decoded = null;
  }
  if (decoded == null) return asIs;

  final longest = math.max(decoded.width, decoded.height);
  final shrink = maxSide != null && longest > maxSide;
  final image = shrink
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxSide : null,
          height: decoded.height > decoded.width ? maxSide : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;
  if (!shrink && !_wantsJpeg(bytes, mimeType)) return asIs;

  if (_hasTransparency(image)) {
    return shrink ? (bytes: img.encodePng(image), mimeType: 'image/png') : asIs;
  }
  final jpeg = img.encodeJpg(
    image,
    quality: CreationIllustrationStore.jpegQuality,
  );
  if (!shrink && jpeg.length >= bytes.length) return asIs;
  return (bytes: jpeg, mimeType: 'image/jpeg');
}

bool _wantsJpeg(Uint8List bytes, String mimeType) =>
    mimeType != 'image/jpeg' &&
    mimeType != 'image/jpg' &&
    bytes.length > CreationIllustrationStore.recompressAbove;

bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}
