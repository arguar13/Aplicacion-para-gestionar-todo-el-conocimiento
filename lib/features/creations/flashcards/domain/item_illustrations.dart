import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Quien dibuja las ilustraciones con IA de las tarjetas y las preguntas
/// (F43, decisión H) y las guarda con su creación, como las de la infografía:
/// en `originales/<creación>/ilustraciones/`, con su ruta en el contenido
/// (`illustration_ref`).
///
/// Dibuja lo de `wanted` —clave y descripción, en orden— para `creationId`,
/// con la cuenta `accountId` elegida en «Con tu IA actual» (o la que
/// escribe). **Nunca hace fallar la creación**: lo que no sale queda dicho en
/// [StudyIllustrations.failure] y lleva el dibujo de la app. Lanza
/// `CreationCancelledException` si `cancellation` se cancela, y entonces
/// borra lo que dibujó en esta vuelta. `onDrawn` cuenta las que ya se
/// intentaron.
typedef StudyIllustrator =
    Future<StudyIllustrations> Function({
      required String creationId,
      required List<(String key, String prompt)> wanted,
      required CancellationSignal cancellation,
      String? accountId,
      void Function(int done, int total)? onDrawn,
    });

/// Lo que dio dibujar: la ruta guardada de cada clave que salió y, si alguna
/// no, el porqué y con qué cuenta.
@immutable
class StudyIllustrations {
  const StudyIllustrations({
    this.references = const {},
    this.failure,
    this.account,
  });

  final Map<String, String> references;
  final ImageFailure? failure;
  final String? account;
}

/// Lo que se le agrega a toda descripción de una ilustración de estudio: una
/// imagen limpia, sin letras —el texto lo pone siempre la app—.
const kStudyIllustrationStyle =
    'clean flat educational illustration, soft colors, simple shapes, '
    'centered subject, plain background, no text, no letters, no numbers';
