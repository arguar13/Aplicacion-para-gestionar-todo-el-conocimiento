import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';

/// Lo que pasó con el motor de voz mientras leía, para que quien escucha
/// pueda encadenar el próximo fragmento o mostrar un error — ver
/// `NarrationPlayer`, que es quien decide qué hacer con cada uno.
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
/// Deliberadamente sin "pausar y seguir del mismo punto": el motor nativo
/// resuelve eso distinto en cada plataforma —en Android es un truco sobre
/// el índice de la última palabra leída, en otras ni siquiera está
/// documentado—, así que confiar en que las tres plataformas lo hacen
/// igual sería una promesa que este contrato no puede sostener. En cambio,
/// quien use esto lee de a fragmentos cortos —una oración, un tramo
/// corto—, y "pausar" es simplemente no pedir el próximo fragmento
/// todavía: la única unidad de posición que este contrato garantiza es "un
/// fragmento entero, desde el principio", nunca una palabra suelta a
/// mitad. Es lo mismo que resuelve, de paso, "retroceder" y "adelantar":
/// no son un `seek` sobre audio ya generado —eso no existe para voz
/// sintetizada que nunca se decodificó a un buffer navegable—, son
/// simplemente leer un fragmento distinto.
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

  /// Libera lo que haya quedado abierto —el canal con la plataforma, la
  /// suscripción de [events]—. Después de esto, ninguno de los otros
  /// métodos vuelve a llamarse sobre esta instancia.
  Future<void> dispose();
}
