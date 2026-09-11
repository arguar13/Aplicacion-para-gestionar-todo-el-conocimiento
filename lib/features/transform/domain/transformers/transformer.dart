import 'package:sinapsis/core/domain/entities/knowledge_item.dart';

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
  Future<KnowledgeItem> transform(KnowledgeItem item);
}
