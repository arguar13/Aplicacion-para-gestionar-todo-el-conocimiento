import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';

/// Sabe reconocer una clase de fuente y convertirla en algo guardable.
///
/// Un adaptador entiende de *de dónde viene* el contenido: cómo reconocer un
/// enlace de YouTube, dónde está el nombre del canal, qué parte de una URL
/// sirve como título. No entiende de *formatos* —convertir audio en texto,
/// una página en artículo— porque de eso se ocupan los transformadores.
///
/// La separación es lo que deja crecer esto sin que se vuelva un nudo:
/// agregar TikTok es escribir un adaptador, cambiar el motor de
/// transcripción es cambiar un transformador, y ninguno toca al otro.
abstract interface class SourceAdapter {
  /// Qué clase de fuente produce este adaptador.
  ///
  /// Lo expone aparte de [adapt] para que la pantalla de captura pueda
  /// anticipar en qué se va a convertir lo que el usuario está pegando,
  /// mientras lo pega. Averiguarlo llamando a [adapt] sería armar un elemento
  /// entero —con sus identificadores y su marca de tiempo— en cada tecla, y
  /// tirarlo.
  SourceKind get producesKind;

  /// Si este adaptador sabe manejar lo que entró.
  bool canHandle(CaptureRequest request);

  /// Arma el elemento con lo que se pueda averiguar sin salir a la red.
  ///
  /// Traer el contenido real —los subtítulos de un video, el texto de una
  /// página— es trabajo posterior y puede tardar o fallar. Acá se guarda lo
  /// que ya se sabe y se deja marcado como pendiente, para que capturar sea
  /// siempre instantáneo y nada dependa de tener conexión en ese momento.
  Future<KnowledgeItem> adapt(CaptureRequest request);
}
