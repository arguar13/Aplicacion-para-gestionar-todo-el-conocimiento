import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
/// - **lo que el contenido ya no nombra se barre** ([sweep]) cuando se guarda
///   uno nuevo (`StudyCreationRepository.complete` y `amend`): volver a
///   generar o a dibujar libera lo de antes;
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

  /// Lo que se está guardando y lo guardado que el contenido todavía no
  /// nombra, por creación: lo que el barrido no puede tocar. Va con el
  /// almacén de archivos y no con este objeto: dos que escriben en el mismo
  /// disco —el del ilustrador y el del repositorio— lo comparten siempre.
  static final _pendingOf = Expando<Map<String, _Pending>>(
    'CreationIllustrationStore',
  );

  Map<String, _Pending> get _pending => _pendingOf[_files] ??= {};

  _Pending _pendingFor(String creationId) =>
      _pending.putIfAbsent(creationId, _Pending.new);

  /// Guarda [bytes] como la ilustración del lugar [slotId] de [creationId] y
  /// devuelve su ruta. Nunca pisa otra: rehacer una deja la nueva al lado
  /// («block-3-2.png») hasta que el barrido se lleva la vieja.
  ///
  /// Antes, la ajusta ([fitCreationIllustration]): achicada a [maxSide] si se
  /// pide y, si no es JPEG y pesa, como JPEG —sin transparencia—.
  ///
  /// Desde que empieza hasta que el contenido guardado la nombra, el barrido
  /// no la toca: lo que se dibuja para una creación se guarda antes de que su
  /// ruta llegue al contenido.
  Future<String> save({
    required String creationId,
    required String slotId,
    required Uint8List bytes,
    required String mimeType,
    int? maxSide,
  }) async {
    final pending = _pendingFor(creationId);
    pending.saving++;
    try {
      final fitted = await fitCreationIllustration(
        bytes,
        mimeType,
        maxSide: maxSide,
      );
      final path = await _files.saveStream(
        bytes: Stream.value(fitted.bytes),
        suggestedName: '$slotId.${_extensionOf(fitted.mimeType)}',
        id: creationId,
        folder: folder,
        unique: true,
      );
      pending.unnamed.add(path);
      return path;
    } finally {
      pending.saved();
    }
  }

  /// Los bytes de [reference], o `null` si ya no está.
  Future<Uint8List?> read(String reference) => _files.read(reference);

  /// Borra [reference] si es de [creationId] ([isCreationFile]), y nada si
  /// no; no falla si ya no estaba.
  Future<void> delete(String creationId, String reference) async {
    if (!isCreationFile(creationId, reference)) return;
    await _files.delete(reference);
    _pending[creationId]?.unnamed.remove(reference);
  }

  /// Borra las de [references] que son de [creationId], sin fallar: lo
  /// dibujado en una vuelta que se canceló.
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

  /// Borra las ilustraciones de [creationId] que el contenido guardado ya no
  /// nombra: lo que da [named] —las rutas de sus `illustration_ref`, leídas
  /// de la base en el momento de barrer—, o nada si da `null` (la creación ya
  /// no está). Lo llama el repositorio **después** de guardar un contenido.
  ///
  /// Nunca toca lo que se está guardando ni lo guardado que el contenido
  /// todavía no nombró: si un ilustrador está dibujando para esta creación,
  /// lo suyo queda. Si hay uno guardando en el momento de decidir, se espera
  /// a que termine y se vuelve a mirar. Los barridos de una misma creación
  /// van de a uno.
  Future<void> sweep(
    String creationId, {
    required Future<Set<String>?> Function() named,
  }) {
    final pending = _pendingFor(creationId);
    final run = pending.sweeps.then((_) => _sweep(creationId, pending, named));
    pending.sweeps = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _sweep(
    String creationId,
    _Pending pending,
    Future<Set<String>?> Function() named,
  ) async {
    while (true) {
      await pending.idle;
      final listed = await _files.filesOf(creationId, folder: folder);
      final kept = await named();
      if (kept == null) return;
      // Un guardado que empezó mientras se listaba puede tener su archivo en
      // [listed] sin estar todavía anotado: se mira de nuevo cuando termine.
      if (pending.saving > 0) continue;
      pending.unnamed.removeAll(kept);
      final unused = [
        for (final path in listed)
          if (!kept.contains(path) && !pending.unnamed.contains(path)) path,
      ];
      await deleteQuietly(creationId, unused);
      return;
    }
  }

  static String _extensionOf(String mimeType) => switch (mimeType) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'png',
  };
}

/// Lo de una creación que el barrido respeta.
class _Pending {
  /// Cuántos guardados están en curso.
  int saving = 0;

  /// Lo guardado que el contenido todavía no nombró.
  final unnamed = <String>{};

  /// El último barrido: el próximo va después.
  Future<void> sweeps = Future.value();

  Completer<void>? _idle;

  /// Cuando no hay ningún guardado en curso.
  Future<void> get idle =>
      saving == 0 ? Future.value() : (_idle ??= Completer<void>()).future;

  void saved() {
    saving--;
    if (saving == 0) {
      _idle?.complete();
      _idle = null;
    }
  }
}

/// Una ilustración lista para guardarse.
typedef FittedIllustration = ({Uint8List bytes, String mimeType});

/// [bytes] como se guardan ([fitCreationIllustrationSync]), en otro hilo si
/// hay que leer la imagen: decodificar una PNG de un mega trabaría la
/// pantalla. Con `compute`, que en la web —sin hilos— lo hace ahí mismo.
Future<FittedIllustration> fitCreationIllustration(
  Uint8List bytes,
  String mimeType, {
  int? maxSide,
}) {
  if (maxSide == null && !_wantsJpeg(bytes, mimeType)) {
    return Future.value((bytes: bytes, mimeType: mimeType));
  }
  return compute(_fit, (bytes: bytes, mimeType: mimeType, maxSide: maxSide));
}

FittedIllustration _fit(
  ({Uint8List bytes, String mimeType, int? maxSide}) job,
) => fitCreationIllustrationSync(job.bytes, job.mimeType, maxSide: job.maxSide);

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
