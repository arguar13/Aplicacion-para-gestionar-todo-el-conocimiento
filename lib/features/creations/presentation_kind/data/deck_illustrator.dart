import 'dart:async';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/data/services/illustration_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Lo que dejó una vuelta de [DeckIllustrator.illustrate].
@immutable
class DeckIllustrationRun {
  const DeckIllustrationRun({
    required this.content,
    required this.drawn,
    required this.saved,
    required this.replaced,
  });

  /// El contenido con las ilustraciones que salieron y las fallas de las
  /// que no.
  final PresentationContent content;

  /// Cuántas salieron.
  final int drawn;

  /// Los archivos nuevos que se guardaron.
  final List<String> saved;

  /// Los archivos de antes que quedaron reemplazados: se borran cuando el
  /// contenido nuevo ya está guardado.
  final List<String> replaced;
}

/// Quien dibuja las ilustraciones de una presentación (F43, decisión H): una
/// por diapositiva que la pide, con la cuenta elegida en «Con tu IA actual»
/// y la pista de estilo de la plantilla. Lo usan el generador —al terminar de
/// escribir el mazo—, «Completar ilustraciones» y «Volver a dibujar» del
/// visor.
///
/// **Una ilustración que no sale nunca tumba la presentación**: queda su
/// lugar dibujado por la app (`CreationArt`) y su porqué en el contenido
/// (`PresentationContent.misses`), para que el visor lo diga. Si la falla es
/// de la cuenta —sin facturación, sin cuota, sin clave—, no se insiste con
/// las que faltan: quedan todas con ese porqué, y lo ya hecho se guarda.
///
/// Cancelar ([illustrate] con su señal) corta lo que se esté dibujando, borra
/// lo que se guardó en esta vuelta y lanza [CreationCancelledException].
///
/// Lo hecho se guarda con `CreationIllustrationStore`, como en los demás
/// tipos: una PNG grande queda como JPEG.
class DeckIllustrator {
  DeckIllustrator({
    required IllustrationService service,
    required CreationIllustrationStore files,
    Future<void> Function(Duration)? wait,
  }) : _service = service,
       _files = files,
       _wait = wait ?? Future<void>.delayed;

  final IllustrationService _service;
  final CreationIllustrationStore _files;
  final Future<void> Function(Duration) _wait;

  /// Cuánto se espera, como mucho, si el proveedor pide calma (el tope por
  /// minuto) antes de reintentar una vez.
  static const maxRateLimitWait = Duration(seconds: 15);

  /// Dibuja las diapositivas [slides] (posiciones, en orden) de [content],
  /// de [creationId], con [styleHint] y la cuenta [accountId] (o la de
  /// siempre). [onProgress] dice cuántas van de cuántas.
  Future<DeckIllustrationRun> illustrate({
    required String creationId,
    required PresentationContent content,
    required List<int> slides,
    required String styleHint,
    String? accountId,
    CancellationSignal? cancellation,
    void Function(int done, int total)? onProgress,
  }) async {
    final account = await accountFor(accountId);
    final label = account?.label ?? (await _service.defaultAccount())?.label;
    var current = content.copyWith(illustrationAccount: label);
    final saved = <String>[];
    final replaced = <String>[];
    var drawn = 0;
    ImageFailure? stopped;

    Never cancelled() {
      for (final path in saved) {
        unawaited(_files.delete(creationId, path));
      }
      throw const CreationCancelledException();
    }

    for (final (done, index) in slides.indexed) {
      if (cancellation?.isCancelled ?? false) cancelled();
      onProgress?.call(done, slides.length);
      final slide = current.deck.slides[index];
      final prompt = slide.illustrationPrompt?.trim() ?? '';
      if (prompt.isEmpty) continue;
      if (stopped != null) {
        current = _missed(current, index, stopped);
        continue;
      }
      try {
        final result = await _draw(
          prompt: prompt,
          styleHint: styleHint,
          aspect: aspectFor(slide),
          account: account,
          cancellation: cancellation,
        );
        if (cancellation?.isCancelled ?? false) cancelled();
        final path = await _files.save(
          creationId: creationId,
          slotId: 'diapositiva-${index + 1}',
          bytes: result.image.bytes,
          mimeType: result.image.mimeType,
        );
        saved.add(path);
        if (slide.illustrationRef case final old?) replaced.add(old);
        current = current.withIllustration(index, path);
        drawn++;
      } on ImageGenerationException catch (error) {
        if (error.failure == ImageFailure.cancelled ||
            (cancellation?.isCancelled ?? false)) {
          cancelled();
        }
        current = _missed(current, index, error.failure);
        if (stopsTheRest(error.failure)) stopped = error.failure;
        // Lo que no es de la imagen —el disco, un archivo que no se pudo
        // escribir— tampoco tumba la presentación: esa queda dibujada.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        if (cancellation?.isCancelled ?? false) cancelled();
        current = _missed(current, index, ImageFailure.unknown);
      }
    }
    onProgress?.call(slides.length, slides.length);
    return DeckIllustrationRun(
      content: current,
      drawn: drawn,
      saved: saved,
      replaced: replaced,
    );
  }

  /// La cuenta [accountId] entre las que pueden dibujar; `null` (la de
  /// siempre, `IllustrationService.defaultAccount`) si no se eligió o ya no
  /// está.
  Future<IllustrationAccount?> accountFor(String? accountId) async {
    if (accountId == null) return null;
    for (final account in await _service.accounts()) {
      if (account.id == accountId) return account;
    }
    return null;
  }

  /// Un pedido, con un reintento si el proveedor pide esperar.
  Future<IllustrationResult> _draw({
    required String prompt,
    required String styleHint,
    required IllustrationAspect aspect,
    required IllustrationAccount? account,
    required CancellationSignal? cancellation,
  }) async {
    for (var attempt = 1; ; attempt++) {
      final cancel = CancelToken();
      unawaited(
        cancellation?.whenCancelled.then((_) {
          if (!cancel.isCancelled) cancel.cancel();
        }),
      );
      try {
        return await _service.generate(
          prompt: prompt,
          styleHint: styleHint,
          aspect: aspect,
          account: account,
          cancel: cancel,
        );
      } on ImageGenerationException catch (error) {
        if (error.failure != ImageFailure.rateLimited || attempt > 1) rethrow;
        final pause = error.retryAfter ?? const Duration(seconds: 6);
        await Future.any([
          _wait(pause > maxRateLimitWait ? maxRateLimitWait : pause),
          if (cancellation != null) cancellation.whenCancelled,
        ]);
        if (cancellation?.isCancelled ?? false) {
          throw const ImageGenerationException(ImageFailure.cancelled);
        }
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          throw const ImageGenerationException(ImageFailure.cancelled);
        }
        rethrow;
      }
    }
  }

  PresentationContent _missed(
    PresentationContent content,
    int slide,
    ImageFailure failure,
  ) => content.copyWith(
    misses: [
      for (final miss in content.misses)
        if (miss.slide != slide) miss,
      IllustrationMiss(slide: slide, failure: failure),
    ]..sort((a, b) => a.slide.compareTo(b.slide)),
  );

  /// Si después de [failure] no tiene sentido seguir pidiendo con la misma
  /// cuenta: lo que es de la cuenta, la cuota del día o que no haya ninguna.
  static bool stopsTheRest(ImageFailure failure) =>
      failure.isAboutAccount ||
      failure == ImageFailure.quotaExhausted ||
      failure == ImageFailure.noAccount ||
      failure == ImageFailure.modelNotFound;

  /// La forma de la ilustración de [slide]: la del lugar donde va. La
  /// portada es ancha; el comienzo de una parte, un medallón; lo demás, un
  /// panel de 4:3. Lo que sobra se recorta al dibujarla.
  static IllustrationAspect aspectFor(Slide slide) => switch (slide.layout) {
    SlideLayout.cover || SlideLayout.closing => IllustrationAspect.wide,
    SlideLayout.section => IllustrationAspect.square,
    _ => IllustrationAspect.classic,
  };
}
