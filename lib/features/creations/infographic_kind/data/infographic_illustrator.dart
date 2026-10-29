import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:sinapsis/features/ai_models/data/services/illustration_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_styles.dart';
import 'package:sinapsis/features/creations/infographic_kind/data/infographic_illustration_store.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_illustration_plan.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Dibuja las ilustraciones con IA de una infografía (F43, decisión H): al
/// generarla, y después desde el visor —rehacer una, o completar las que
/// faltan—.
///
/// - **Con la cuenta del aviso**: la que se eligió en «Con tu IA actual» o,
///   si no se eligió otra, la misma que escribe, como lo estima el aviso
///   (`CreationCostEstimator`). Nunca una que la persona no vio: si la IA
///   actual no dibuja (Claude, Gemma) y no se eligió otra, no se pide nada.
/// - **Nunca hace fallar la lámina**: lo que no sale queda con su lugar
///   dibujado por la app y anotado con su porqué
///   (`InfographicContent.failures`), para que el visor lo diga y ofrezca
///   completarlo. Si la cuenta no puede (sin facturación, sin cuota…), las
///   que siguen no se piden: fallarían igual.
/// - **De a una**, avisando cuántas van, y **cancelable** entre una y otra y
///   a mitad de una: lo que se dibujó en esta vuelta se borra.
/// - **Lo hecho se guarda** con `InfographicIllustrationStore`; la ilustración
///   que se rehizo borra la de antes.
class InfographicIllustrator {
  InfographicIllustrator({
    required IllustrationService Function() service,
    required InfographicIllustrationStore Function() store,
    required Future<String?> Function() textAccountId,
  }) : _service = service,
       _store = store,
       _textAccountId = textAccountId;

  final IllustrationService Function() _service;
  final InfographicIllustrationStore Function() _store;
  final Future<String?> Function() _textAccountId;

  /// Dibuja [slots] de [content] —con [design], para el estilo— y devuelve
  /// el contenido con lo que salió y lo que no. [accountId] es la cuenta
  /// elegida en el aviso, o `null` para la que escribe. Lanza
  /// [CreationCancelledException] si se cancela.
  Future<InfographicContent> illustrate({
    required String creationId,
    required InfographicContent content,
    required InfographicDesign design,
    required List<InfographicSlot> slots,
    String? accountId,
    CancellationSignal? cancellation,
    void Function(int done, int total)? onProgress,
  }) async {
    if (slots.isEmpty) return content;
    _throwIfCancelled(cancellation);
    final service = _service();
    final account = await _accountOf(service, accountId);
    if (account == null) {
      return _failAll(content, slots, ImageFailure.noAccount, null);
    }
    final capability = await service.capabilityOf(account);
    if (capability.cannot) {
      // Ya se sabe que no puede: pedirlo sería gastar tiempo en un no.
      return _failAll(
        content,
        slots,
        capability.reason ?? ImageFailure.unknown,
        account.label,
      );
    }

    final store = _store();
    final hint = illustrationStyleHint(
      InfographicAuto.arrange(content.sheet, design).style,
    );
    final token = CancelToken();
    final cancelled = cancellation?.whenCancelled.then((_) {
      if (!token.isCancelled) token.cancel();
    });
    unawaited(cancelled);

    var sheet = content.sheet;
    final failures = {...content.failures};
    final created = <String>[];
    final replaced = <String>[];
    ImageFailure? stopAll;
    try {
      for (final (i, slot) in slots.indexed) {
        _throwIfCancelled(cancellation);
        if (stopAll != null) {
          failures[slot.id] = stopAll;
          onProgress?.call(i + 1, slots.length);
          continue;
        }
        try {
          final result = await _orCancelled(
            service.generate(
              prompt: slot.prompt,
              styleHint: hint,
              aspect: slot.aspect,
              account: account,
              cancel: token,
            ),
            cancellation,
          );
          _throwIfCancelled(cancellation);
          final reference = await store.save(
            creationId: creationId,
            slotId: slot.id,
            bytes: result.image.bytes,
            mimeType: result.image.mimeType,
          );
          created.add(reference);
          final before = InfographicIllustrationPlan.referenceOf(
            sheet,
            slot.id,
          );
          if (before != null) replaced.add(before);
          sheet = InfographicIllustrationPlan.withReference(
            sheet,
            slot.id,
            reference,
          );
          failures.remove(slot.id);
        } on CreationCancelledException {
          rethrow;
        } on ImageGenerationException catch (error) {
          _throwIfCancelled(cancellation);
          if (error.failure == ImageFailure.cancelled) {
            throw const CreationCancelledException();
          }
          failures[slot.id] = error.failure;
          // Lo que es de la cuenta —o su cuota del día— no se arregla con la
          // siguiente: se anota para todas las que faltan.
          if (error.failure.isAboutAccount ||
              error.failure == ImageFailure.quotaExhausted) {
            stopAll = error.failure;
          }
          // Una ilustración nunca tumba la lámina: cualquier otra cosa que
          // falle —el disco, un formato raro— queda anotada y se sigue.
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {
          _throwIfCancelled(cancellation);
          failures[slot.id] = ImageFailure.unknown;
        }
        onProgress?.call(i + 1, slots.length);
      }
    } on CreationCancelledException {
      await _deleteQuietly(store, created);
      rethrow;
    }
    // Lo rehecho reemplaza a lo de antes: la vieja ya no la nombra nadie.
    await _deleteQuietly(store, replaced);
    return content.copyWith(
      sheet: sheet,
      failures: failures,
      accountLabel: account.label,
    );
  }

  Future<IllustrationAccount?> _accountOf(
    IllustrationService service,
    String? accountId,
  ) async {
    final id = accountId ?? await _textAccountId();
    if (id == null) return null;
    for (final account in await service.accounts()) {
      if (account.id == id) return account;
    }
    return null;
  }

  static InfographicContent _failAll(
    InfographicContent content,
    List<InfographicSlot> slots,
    ImageFailure failure,
    String? accountLabel,
  ) => content.copyWith(
    failures: {...content.failures, for (final slot in slots) slot.id: failure},
    accountLabel: accountLabel,
  );

  static Future<void> _deleteQuietly(
    InfographicIllustrationStore store,
    List<String> references,
  ) async {
    for (final reference in references) {
      try {
        await store.delete(reference);
        // Un archivo que no se pudo borrar no deshace lo dibujado ni tapa
        // una cancelación.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
  }

  /// [work], o [CreationCancelledException] en cuanto se cancele: un motor
  /// que no atiende el corte (el del teléfono a mitad de un paso) no deja la
  /// lámina esperando. Lo que [work] termine después se descarta.
  static Future<T> _orCancelled<T>(Future<T> work, CancellationSignal? signal) {
    if (signal == null) return work;
    final cut = signal.whenCancelled.then<T>(
      (_) => throw const CreationCancelledException(),
    );
    // Si la cancelación llega después de que [work] terminó, nadie la espera.
    unawaited(cut.then((_) {}, onError: (_) {}));
    work.ignore();
    return Future.any([work, cut]);
  }

  static void _throwIfCancelled(CancellationSignal? signal) {
    if (signal?.isCancelled ?? false) {
      throw const CreationCancelledException();
    }
  }
}

/// Cómo se le describe el estilo al modelo de imágenes (en inglés, que es lo
/// que mejor entienden): el de los estilos con ilustraciones con IA
/// (`InfographicStyleSpec.illustrationHint`) o, en los dibujados por la app,
/// uno que vaya con su trazo.
String illustrationStyleHint(InfographicStyleId style) =>
    InfographicStyles.of(style).illustrationHint ??
    switch (style) {
      InfographicStyleId.editorial =>
        'elegant editorial illustration, fine ink lines with muted washes',
      InfographicStyleId.geometric =>
        'flat geometric vector illustration, bold simple shapes',
      InfographicStyleId.swiss =>
        'minimal Swiss-style flat illustration, few shapes, strong contrast',
      InfographicStyleId.chalkboard =>
        'chalk drawing on a dark chalkboard, hand-drawn lines',
      InfographicStyleId.neon => 'glowing neon line art on a dark background',
      InfographicStyleId.parchment =>
        'antique engraving illustration on parchment, sepia ink',
      InfographicStyleId.corporate =>
        'clean corporate flat illustration, calm blue tones',
      InfographicStyleId.pastel =>
        'soft pastel flat illustration, gentle gradients',
      InfographicStyleId.kids =>
        "playful children's book illustration, bright colors, thick outlines",
      InfographicStyleId.data =>
        'minimal flat icon-like illustration, simple shapes',
      _ => 'friendly flat vector illustration, rounded shapes, soft colors',
    };
