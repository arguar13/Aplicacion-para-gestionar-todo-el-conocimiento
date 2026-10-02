import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';

/// El comprobante de un «no era» (F27): con él se deshace mientras el aviso
/// sigue a la vista.
///
/// Decir que algo «no era» lo borra y lo recuerda. Deshacerlo tiene que
/// dejarlo como estaba —una tarjeta con su calendario, sus opciones y sus
/// repasos—, y eso vive acá, en memoria, y no en la base: deshacer es cosa de
/// segundos, y un comprobante perdido solo significa que ya no se puede
/// deshacer, no que algo quede a medias.
@immutable
class AiRejectionReceipt {
  const AiRejectionReceipt({
    required this.kind,
    required this.rejectionId,
    required this.removed,
  });

  /// Qué clase de cosa se rechazó: dice qué repositorio lo deshace.
  final AiRejectionKind kind;

  /// La fila de `ai_rejections` que lo recuerda, para olvidarlo al deshacer.
  final String rejectionId;

  /// Lo que se borró, tal como lo guardó el repositorio que emitió el
  /// comprobante. Opaco para todos los demás: solo ese repositorio lo lee.
  final Object removed;
}
