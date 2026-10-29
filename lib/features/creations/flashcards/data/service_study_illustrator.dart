import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;
import 'package:image/image.dart' as img;
import 'package:sinapsis/features/ai_models/data/services/illustration_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_drawing.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/flashcards/domain/item_illustrations.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// El [StudyIllustrator] de verdad ([illustrate]), sobre el servicio de
/// ilustraciones (F43, decisión H), con las mismas reglas que la infografía
/// (`InfographicIllustrator`):
///
/// - **la cuenta del aviso** (`creationIllustrationAccount`): la elegida en
///   «Con tu IA actual» o la que escribe; si ninguna dibuja, no se pide nada;
/// - una cuenta que ya se sabe que no puede no se prueba de nuevo;
/// - lo que es de la cuenta (sin facturación, sin cuota) corta las que
///   siguen; cualquier otra falla queda anotada y se sigue;
/// - **cancelable** entre una y otra y a mitad de una, y lo dibujado en esta
///   vuelta se borra;
/// - **lo hecho se guarda** con `CreationIllustrationStore`, achicado a
///   [kStudyIllustrationSide]: una tarjeta no necesita más.
class ServiceStudyIllustrator {
  ServiceStudyIllustrator({
    required IllustrationService Function() service,
    required CreationIllustrationStore Function() store,
    required Future<String?> Function() textAccountId,
    Future<ShrunkIllustration> Function(Uint8List bytes, String mimeType)?
    shrink,
  }) : _service = service,
       _store = store,
       _textAccountId = textAccountId,
       _shrink = shrink ?? shrinkStudyIllustration;

  final IllustrationService Function() _service;
  final CreationIllustrationStore Function() _store;
  final Future<String?> Function() _textAccountId;
  final Future<ShrunkIllustration> Function(Uint8List bytes, String mimeType)
  _shrink;

  Future<StudyIllustrations> illustrate({
    required String creationId,
    required List<(String key, String prompt)> wanted,
    required CancellationSignal cancellation,
    String? accountId,
    void Function(int done, int total)? onDrawn,
  }) async {
    if (wanted.isEmpty) return const StudyIllustrations();
    throwIfCreationCancelled(cancellation);
    final service = _service();
    final account = await creationIllustrationAccount(
      service,
      accountId: accountId,
      textAccountId: _textAccountId,
    );
    if (account == null) {
      return const StudyIllustrations(failure: ImageFailure.noAccount);
    }
    final capability = await service.capabilityOf(account);
    if (capability.cannot) {
      return StudyIllustrations(
        failure: capability.reason ?? ImageFailure.unknown,
        account: account.label,
      );
    }

    final store = _store();
    final token = CancelToken();
    unawaited(
      cancellation.whenCancelled.then((_) {
        if (!token.isCancelled) token.cancel();
      }),
    );
    final references = <String, String>{};
    ImageFailure? failure;
    try {
      for (final (index, (key, prompt)) in wanted.indexed) {
        throwIfCreationCancelled(cancellation);
        onDrawn?.call(index, wanted.length);
        try {
          final result = await creationOrCancelled(
            service.generate(
              prompt: prompt,
              styleHint: kStudyIllustrationStyle,
              aspect: IllustrationAspect.classic,
              size: IllustrationSize.small,
              account: account,
              cancel: token,
            ),
            cancellation,
          );
          throwIfCreationCancelled(cancellation);
          final shrunk = await _shrink(
            result.image.bytes,
            result.image.mimeType,
          );
          references[key] = await store.save(
            creationId: creationId,
            slotId: key,
            bytes: shrunk.bytes,
            mimeType: shrunk.mimeType,
          );
        } on CreationCancelledException {
          rethrow;
        } on ImageGenerationException catch (error) {
          throwIfCreationCancelled(cancellation);
          if (error.failure == ImageFailure.cancelled) {
            throw const CreationCancelledException();
          }
          failure = error.failure;
          // Lo que es de la cuenta —o su cuota del día— no se arregla con la
          // siguiente: no se piden más.
          if (error.failure.isAboutAccount ||
              error.failure == ImageFailure.quotaExhausted) {
            break;
          }
          // Una ilustración nunca tumba la creación: el disco, un formato
          // raro, quedan anotados y se sigue.
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {
          throwIfCreationCancelled(cancellation);
          failure = ImageFailure.unknown;
        }
      }
    } on CreationCancelledException {
      await store.deleteQuietly(references.values);
      rethrow;
    }
    onDrawn?.call(wanted.length, wanted.length);
    return StudyIllustrations(
      references: references,
      failure: failure,
      account: account.label,
    );
  }
}

/// Una ilustración lista para guardarse.
class ShrunkIllustration {
  const ShrunkIllustration({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

/// El lado más largo de una ilustración guardada: alcanza para una tarjeta
/// en una tableta, y diez de ellas pesan menos que una foto.
const kStudyIllustrationSide = 640;

/// [bytes] achicada a [kStudyIllustrationSide] como JPEG, en otro hilo. Si no
/// se puede leer —un formato raro—, queda tal cual.
Future<ShrunkIllustration> shrinkStudyIllustration(
  Uint8List bytes,
  String mimeType,
) => Isolate.run(() => shrinkStudyIllustrationSync(bytes, mimeType));

ShrunkIllustration shrinkStudyIllustrationSync(
  Uint8List bytes,
  String mimeType,
) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
    // Los bytes los manda un proveedor de afuera: un formato que el lector no
    // entiende puede tirar cualquier cosa en vez de devolver null.
  } on Object {
    decoded = null;
  }
  if (decoded == null) {
    return ShrunkIllustration(bytes: bytes, mimeType: mimeType);
  }
  final longest = math.max(decoded.width, decoded.height);
  final resized = longest <= kStudyIllustrationSide
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height
              ? kStudyIllustrationSide
              : null,
          height: decoded.height > decoded.width
              ? kStudyIllustrationSide
              : null,
          interpolation: img.Interpolation.average,
        );
  return ShrunkIllustration(
    bytes: img.encodeJpg(resized, quality: 80),
    mimeType: 'image/jpeg',
  );
}
