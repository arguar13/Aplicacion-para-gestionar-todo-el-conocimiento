import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';

export 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';

/// Convierte un elemento a las formas en que se puede leer y buscar.
///
/// Un transformador entiende de *formatos*: cómo sacar texto de un audio,
/// cómo limpiar una página, cómo leer un PDF. No entiende de *fuentes* —de
/// eso se ocupan los adaptadores, que ya reconocieron qué era cada cosa en el
/// momento de guardarla.
///
/// La separación es lo que deja crecer esto sin volverse un nudo: agregar
/// TikTok es escribir un adaptador; cambiar el motor de transcripción es
/// cambiar un transformador; ninguno toca al otro.
///
/// A diferencia de los adaptadores, acá el trabajo sí sale a la red y sí
/// puede tardar o fallar. Por eso corre después de guardar y no antes: lo que
/// el usuario capturó ya está a salvo cuando esto empieza.
abstract interface class Transformer {
  /// Si este transformador tiene algo que hacer con [item].
  ///
  /// Mira la fuente y lo que ya se tenga: un video del que ya se bajó la
  /// transcripción no necesita volver a bajarse.
  bool canTransform(KnowledgeItem item);

  /// Devuelve el elemento enriquecido.
  ///
  /// Puede agregar formas de contenido y también corregir lo que se había
  /// deducido sin red: el título provisional sacado de la URL se reemplaza
  /// por el de verdad, y aparece el autor que antes no se sabía.
  ///
  /// Lanza si no puede completar el trabajo. Quien llama decide qué hacer con
  /// eso; lo que nunca se hace es perder lo que ya estaba guardado.
  ///
  /// [context] es la cola que lo corre: por él se pasa al carril largo, se
  /// informa el avance y se consulta si el elemento se borró. Por fuera de la
  /// cola, [TransformContext.detached].
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  });

  /// Cuánto puede tardar el tramo corto de [transform] —todo lo que hace
  /// antes de [TransformContext.enterLongLane], si es que entra— antes de
  /// darlo por colgado.
  ///
  /// Con un tope para el trabajo corto —traer una página, una publicación,
  /// reconocer una foto—: pasado ese tiempo algo se trabó, y esperarlo
  /// frenaría todo lo que viene detrás en la cola. `null` para lo que todavía
  /// no separa su parte larga de la corta: ahí cada pedido a la red lleva su
  /// propio límite. Lo que corre en el carril largo no tiene tope fijo: lo
  /// vigila que siga avanzando.
  Duration? get timeLimit;
}

/// El tope de [Transformer.timeLimit] para el trabajo corto. Holgado a
/// propósito —una conexión lenta de datos móviles no es un cuelgue—, pero
/// finito: nada corto puede frenar la cola más que esto.
const kShortTransformTimeLimit = Duration(minutes: 3);

/// Cuánto puede pasar el trabajo largo sin informar avance antes de darlo por
/// colgado. No es un tope a su duración: una transcripción de cuatro horas
/// tarda lo que tarda mientras siga avanzando. Holgado: un tramo de audio o
/// una página escaneada tardan segundos, no minutos.
const kLongTransformStallLimit = Duration(minutes: 10);
