import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';

/// Lo que pasó con el motor de voz mientras leía, para que quien escucha
/// pueda encadenar el próximo fragmento o mostrar un error — ver
/// `ReadAloudController`, que es quien decide qué hacer con cada uno.
enum NarrationEvent {
  /// Terminó de leer el fragmento pedido, entero y sin que nadie lo
  /// interrumpiera.
  completed,

  /// El motor de voz falló a mitad de lectura —un error nativo, un motor
  /// no instalado—. Distinto de que alguien pare la lectura a propósito:
  /// eso no pasa por acá, lo decide quien llama a `stop`.
  error,
}

/// El motor de texto a voz del sistema.
///
/// Existe como contrato de dominio y no como `FlutterTts` a secas por el
/// mismo motivo de siempre en este proyecto —`FileChooser`, `FileOpener`—:
/// hablarle a un motor de voz real necesita una plataforma de verdad
/// detrás, así que todo lo que lo use se prueba con un doble.
///
/// Deliberadamente sin un "pausar y seguir" nativo: el motor lo resuelve
/// distinto en cada plataforma —en Android es un truco sobre el índice de
/// la última palabra, en otras ni siquiera está documentado—, y sería una
/// promesa que este contrato no puede sostener. Lo que sí da es
/// [progress]: **qué palabra está diciendo ahora** (F25). Con eso, quien lo
/// usa arma la pausa de verdad sin pedirle nada más al motor: "pausar" es
/// [stop] recordando el comienzo de la última palabra avisada, y "seguir"
/// es [speak] del resto del texto desde ahí —ver `ReadAloudController`—.
/// "Retroceder" y "adelantar" tampoco son un `seek` sobre audio ya
/// generado —eso no existe para voz sintetizada que nunca se decodificó a
/// un buffer navegable—: son leer desde otra palabra.
///
/// Por lo mismo, quien use esto le pasa a [speak] tramos cortos —una línea,
/// una oración—, nunca el texto entero de una vez: retomar o saltar es
/// volver a pedir un tramo, y uno corto empieza a sonar enseguida.
abstract interface class TextToSpeechService {
  /// Las voces que este dispositivo tiene instaladas. Puede ser una lista
  /// larga —Android suele traer varias decenas— o, en un motor sin nada
  /// instalado, vacía: ahí no hay nada que elegir y se sigue con la voz que
  /// el sistema use por defecto.
  Future<List<NarrationVoice>> getVoices();

  /// Qué voz usar de ahora en más. `null` vuelve a la que el sistema tenga
  /// configurada por defecto.
  Future<void> setVoice(NarrationVoice? voice);

  /// La velocidad de lectura, de 0.5 (la mitad de la velocidad normal del
  /// motor) a 2.0 (el doble). 1.0 es la velocidad normal.
  Future<void> setSpeed(double speed);

  /// Lee [text] en voz alta. No espera a que termine —eso se sabe por
  /// [events]—, así que quien llama puede seguir reaccionando a otras
  /// cosas mientras tanto.
  Future<void> speak(String text);

  /// Corta la lectura en seco, ahí donde esté.
  Future<void> stop();

  /// Un evento por cada lectura que termina o falla. No hay un evento de
  /// "empezó" a propósito: nadie que use este contrato lo necesita, porque
  /// ya sabe que empezó apenas llamó a [speak].
  Stream<NarrationEvent> get events;

  /// Dónde empieza la palabra que el motor está diciendo ahora, en
  /// caracteres (unidades UTF-16, las mismas de un `String` de Dart) dentro
  /// del texto que se le pasó al último [speak]: un valor por palabra
  /// (F25).
  ///
  /// Solo lo que corresponde al último [speak]: un aviso tardío de una
  /// lectura anterior —que llega después de pedir la nueva— no sale por
  /// acá. Puede no emitir nada: en `flutter_tts` 4.2.5 Windows no avisa
  /// palabra por palabra, y Android anterior a 8.0 avisa una sola vez, en
  /// 0, al empezar; quien lo use tiene que seguir funcionando sin esto, con
  /// la posición en el comienzo del tramo.
  Stream<int> get progress;

  /// Libera lo que haya quedado abierto —el canal con la plataforma, la
  /// suscripción de [events] y [progress]—. Después de esto, ninguno de los
  /// otros métodos vuelve a llamarse sobre esta instancia.
  Future<void> dispose();
}
