import 'package:sinapsis/features/transform/domain/entities/stored_video_text.dart';

/// Los textos ya guardados de los videos de YouTube (F45, paso 4): lo que se
/// mira para ofrecer «Volver a extraer» en los que no están en su idioma.
///
/// Trae solo el comienzo de cada texto ([kStoredVideoTextHead] caracteres):
/// alcanza para reconocer su escritura y su idioma, y un video de cuatro
/// horas no viaja entero a la interfaz.
abstract interface class VideoTextRepository {
  /// Los videos que esperan en la Bandeja y ya tienen texto, en el orden de
  /// la Bandeja.
  Stream<List<StoredVideoText>> watchPending();

  /// Los documentos de Procesado que salieron de un video que sigue en la
  /// Biblioteca —vivo—, con el comienzo de su sección «Texto» y el del texto
  /// de su fuente.
  Stream<List<StoredVideoText>> watchProcessed();
}

/// Cuántos caracteres del comienzo de cada texto se traen.
const kStoredVideoTextHead = 4000;
