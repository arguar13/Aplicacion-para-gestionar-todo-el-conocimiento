import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';

/// Lo que llega desde el sistema operativo sin que el usuario haya abierto
/// Sinapsis a propósito: el botón de compartir de otra app.
///
/// Dos formas de recibirlo y no una, porque el sistema operativo las
/// entrega distinto. Si la app estaba cerrada, lo compartido es lo que la
/// arrancó, y hay que preguntarlo una vez ([initial]). Si ya estaba
/// abierta, llega después, de a poco, por [stream]. Ignorar cualquiera de
/// los dos casos pierde capturas: solo mirar el stream se perdería
/// justamente el más común, que alguien comparte algo con la app cerrada.
///
/// Cada lote es una lista y no un elemento suelto porque el sistema permite
/// compartir varias cosas de una vez —varias fotos elegidas juntas—, y acá
/// no hay ninguna que sea "la principal": todas piden su propio elemento.
abstract interface class SharedContentListener {
  /// Lo que trajo el arranque, si la app se abrió por esto. Vacío si no.
  Future<List<CaptureRequest>> initial();

  /// Lo que va llegando mientras la app sigue abierta.
  Stream<List<CaptureRequest>> get stream;
}
