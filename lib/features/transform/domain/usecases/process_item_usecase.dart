import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/attachments/domain/services/attachment_work.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_suggestion_generator.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/reference/domain/services/metadata_suggestion_generator.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_state_repository.dart';
import 'package:sinapsis/features/transform/domain/repositories/text_anchor_relocator.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/merge_transform_result.dart';
import 'package:sinapsis/features/transform/domain/usecases/processing_failure_classifier.dart';
import 'package:sinapsis/features/transform/domain/usecases/reextraction.dart';

/// Trae el contenido de un elemento que quedó pendiente.
///
/// El orden de los pasos importa, y todos existen por una razón:
///
/// 1. Se marca **en curso** —y se cuenta el intento— antes de empezar. Eso es
///    lo que hace que la interfaz pueda mostrar que algo está trabajando — la
///    lista escucha los cambios de la base, así que ve el cambio de estado
///    sola. El intento contado es lo que le permite a la cola dejar de
///    retomar algo que hace caer la app cada vez.
/// 2. Se transforma. Acá es donde se sale a la red, se tarda y se puede
///    fallar.
/// 3. Se guarda el resultado como **listo**.
///
/// Si el paso 2 falla, el elemento queda **fallido**, con el motivo guardado,
/// pero conserva todo lo que ya tenía: su enlace, su título provisional, la
/// nota del usuario. Nunca se borra nada por un error de red. Rechazar algo
/// porque una etapa opcional no funcionó sería peor que aceptarlo incompleto,
/// y además se puede reintentar cuando haya conexión.
///
/// Los pasos 1 y el fallo son operaciones puntuales de
/// [ProcessingStateRepository], no un guardado del elemento entero: guardar la
/// foto que se tenía en la mano pisaba lo que el usuario hubiera cambiado
/// mientras tanto. Por lo mismo el paso 3 aplica el resultado sobre la
/// versión actual ([mergeTransformResult]), y no lo guarda si el elemento se
/// borró mientras se procesaba.
class ProcessItemUseCase implements UseCase<KnowledgeItem, String> {
  const ProcessItemUseCase({
    required TransformerRegistry registry,
    required LibraryRepository repository,
    required ProcessingStateRepository processingStates,
    required AppLogger logger,
    required TelemetryService telemetry,
    required Clock clock,
    required DuplicateSuggestionGenerator duplicateSuggestionGenerator,
    required MetadataSuggestionGenerator metadataSuggestionGenerator,
    TextAnchorRelocator? anchorRelocator,
    AttachmentWork? attachmentWork,
    Duration longStallLimit = kLongTransformStallLimit,
  }) : _longStallLimit = longStallLimit,
       _attachmentWork = attachmentWork,
       _anchorRelocator = anchorRelocator,
       _registry = registry,
       _repository = repository,
       _processingStates = processingStates,
       _logger = logger,
       _telemetry = telemetry,
       _clock = clock,
       _duplicateSuggestionGenerator = duplicateSuggestionGenerator,
       _metadataSuggestionGenerator = metadataSuggestionGenerator;

  /// Cuánto puede pasar el trabajo largo sin informar avance. Se inyecta
  /// para poder probarlo sin esperar diez minutos.
  final Duration _longStallLimit;

  /// Lleva los subrayados y las citas al texto nuevo cuando se vuelve a
  /// extraer (F22). Sin él, volver a extraer igual conserva los subrayados
  /// —la forma no cambia de identificador—, pero sin moverlos.
  final TextAnchorRelocator? _anchorRelocator;

  /// El «Contenido» bajado de una página (F30): corre después del
  /// transformador del elemento, en la misma vuelta, si quedó algo por bajar
  /// o algún archivo sin texto; y solo, cuando no hay otro trabajo —«Bajar
  /// el resto»—. `null` donde no se baja nada.
  final AttachmentWork? _attachmentWork;
  final TransformerRegistry _registry;
  final LibraryRepository _repository;
  final ProcessingStateRepository _processingStates;
  final AppLogger _logger;
  final TelemetryService _telemetry;
  final Clock _clock;
  final DuplicateSuggestionGenerator _duplicateSuggestionGenerator;
  final MetadataSuggestionGenerator _metadataSuggestionGenerator;

  @override
  Future<Either<Failure, KnowledgeItem>> call(String itemId) => process(itemId);

  /// Procesa [itemId] dentro de [context], la cola que lo corre. Si el
  /// contexto pide abandonar —el elemento se borró mientras tanto—, se lo
  /// suelta en el acto: no se espera a que termine lo que quedó corriendo, y
  /// su resultado no se guarda.
  Future<Either<Failure, KnowledgeItem>> process(
    String itemId, {
    TransformContext context = TransformContext.detached,
  }) async {
    final found = await _repository.findById(itemId);

    final failure = found.getLeft().toNullable();
    if (failure != null) return left(failure);

    final item = found.getRight().toNullable();
    if (item == null) {
      // Se borró entre que entró en la cola y le tocó el turno. No es un
      // defecto: alguien lo eliminó mientras esperaba.
      return left(
        const Failure.unexpected(
          message: 'El elemento ya no existe; nada que procesar.',
        ),
      );
    }

    // Lo mismo si está en la papelera: no se procesa, y queda en espera por
    // si alguien lo restaura.
    if (await _processingStates.isRemoved(itemId)) {
      return left(
        const Failure.unexpected(
          message: 'El elemento está en la papelera; nada que procesar.',
        ),
      );
    }

    return _process(item, context);
  }

  /// Si el usuario pidió volver a extraer el texto de [itemId] (F22). Si
  /// no se puede saber —la base falló—, se procesa como siempre.
  Future<bool> _reextractionRequested(String itemId) async {
    try {
      final marks = await _processingStates.load(
        itemId,
        ProcessingCheckpointKind.reextract,
      );
      return marks.isNotEmpty;
      // Cualquier falla de la base: se procesa como siempre.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _logger.error(
        'No se pudo leer si $itemId se vuelve a extraer.',
        e,
        stackTrace,
      );
      return false;
    }
  }

  /// Después de volver a extraer (F22): lo que apuntaba al texto de
  /// [before] —subrayados, tarjetas, extractos— se lleva a su lugar en el de
  /// [after]. Los subrayados que no se encuentran quedan en las notas del
  /// elemento, citados con su nota: nada de lo que el usuario marcó se
  /// pierde. Dentro de la transacción del guardado.
  Future<Either<Failure, KnowledgeItem>> _relocateAnchors(
    Either<Failure, KnowledgeItem> saved, {
    required KnowledgeItem before,
    required KnowledgeItem after,
  }) async {
    final relocator = _anchorRelocator;
    final old = primaryTextOf(before);
    final now = old == null
        ? null
        : after.renditions
              .whereType<TextRendition>()
              .where((r) => r.id == old.id)
              .firstOrNull;
    if (relocator == null ||
        old == null ||
        now == null ||
        now.content == old.content) {
      return saved;
    }

    final lost = await relocator.relocate(
      itemId: after.id,
      renditionId: old.id,
      from: old.content,
      to: now.content,
    );
    if (lost.isEmpty) return saved;
    return _repository.save(
      after.copyWith(notes: notesWithLostHighlights(after.notes, lost)),
    );
  }

  Future<Either<Failure, KnowledgeItem>> _process(
    KnowledgeItem item,
    TransformContext context, {
    bool onlyAttachments = false,
  }) async {
    // Volver a extraer (F22): el transformador se elige como si el
    // elemento no tuviera texto —todos piden eso para correr—, pero recibe
    // el elemento entero, y el texto nuevo toma el lugar del viejo. También
    // en lo que es «solo el libro» (F30): la cola no le saca el texto sola,
    // pero la persona sí puede pedirlo; con el texto nuevo guardado, la marca
    // se va sola (`KnowledgeEntryWriter.upsert`).
    final reextract = !onlyAttachments && await _reextractionRequested(item.id);
    var transformer = onlyAttachments
        ? null
        : _registry.resolve(
            reextract
                ? item.copyWith(
                    renditions: const [],
                    source: item.source.copyWith(onlyFile: false),
                  )
                : item,
          );
    // Sin otro trabajo, el del «Contenido», si queda (F30).
    final attachmentWork = _attachmentWork;
    if (transformer == null &&
        attachmentWork != null &&
        await _hasAttachmentWork(item.id)) {
      transformer = attachmentWork;
    }

    if (transformer == null) {
      // Nada que hacer: ya está completo. Se marca listo para que no siga
      // apareciendo como pendiente ni vuelva a entrar en la cola.
      final result = await _repository.save(
        item.copyWith(
          processingState: ProcessingState.ready,
          updatedAt: _clock(),
        ),
      );
      if (result.isRight()) await _processingStates.succeed(item.id);
      _generateSuggestions(result);
      return result;
    }

    try {
      // Se publica el "en curso" antes de empezar, para que la interfaz lo
      // muestre mientras dura. Adentro del `try`: si la base falla acá, el
      // fallo tiene que quedar registrado como cualquier otro, no escapar.
      await _processingStates.begin(item.id);

      // Vigilado: con tope fijo mientras está en el carril corto —pasado ese
      // tiempo algo se trabó, y esperarlo frenaría la cola entera—, y en el
      // largo, cortado solo si deja de avanzar. Ni el vigilante ni la
      // cancelación cortan lo que quedó corriendo —cada pedido a la red
      // termina solo, con su propio límite, y lo largo consulta la
      // cancelación entre parte y parte—: la cola sigue y el resultado
      // tardío se descarta.
      final watchdog = _Watchdog(
        context,
        shortLimit: transformer.timeLimit,
        stallLimit: _longStallLimit,
      );
      final KnowledgeItem enriched;
      try {
        enriched = await Future.any([
          transformer.transform(item, context: watchdog),
          watchdog.expired<KnowledgeItem>(),
          context.whenCancelled.then<KnowledgeItem>(
            (_) => throw const ProcessingCancelledException(),
          ),
        ]);
      } finally {
        watchdog.dispose();
      }

      final proposed = reextract
          ? replaceExtractedText(original: item, enriched: enriched)
          : enriched;

      final result = await _repository.runInTransaction(() async {
        // Sobre la versión ACTUAL, leída en la misma transacción en la que se
        // escribe: mientras se procesaba, el usuario pudo ponerle etiquetas,
        // cambiarle el título o mandarlo a la papelera.
        final current = (await _repository.findById(
          item.id,
        )).getRight().toNullable();
        if (current == null || await _processingStates.isRemoved(item.id)) {
          throw const ProcessingCancelledException();
        }
        final saved = await _repository.save(
          mergeTransformResult(
            original: item,
            enriched: proposed,
            current: current,
          ).copyWith(
            processingState: ProcessingState.ready,
            updatedAt: _clock(),
          ),
        );
        final savedItem = saved.getRight().toNullable();
        if (!reextract || savedItem == null) return saved;
        return _relocateAnchors(before: current, after: savedItem, saved);
      });
      if (result.isRight()) await _processingStates.succeed(item.id);
      // El enlace resultó ser un archivo (F30): el elemento pasó a ser un
      // documento, una foto o un audio, todavía sin texto. Le toca al
      // transformador de esa clase, en la misma vuelta: si no, quedaba
      // "listo" y sin texto hasta que alguien lo volviera a procesar.
      final saved = result.getRight().toNullable();
      if (saved != null &&
          saved.source.kind != item.source.kind &&
          saved.renditions.isEmpty &&
          _registry.resolve(saved) != null) {
        return await _process(saved, context);
      }
      // Lo que la página ofrece para bajar, en la misma vuelta (F30): el
      // artículo ya quedó guardado y se puede leer mientras tanto.
      if (saved != null &&
          !identical(transformer, attachmentWork) &&
          await _hasAttachmentWork(saved.id)) {
        return await _process(saved, context, onlyAttachments: true);
      }
      _generateSuggestions(result);
      return result;
    } on ProcessingCancelledException {
      _logger.info('Se abandonó ${item.id}: se borró mientras se procesaba.');
      // En espera y no fallido: no falló nada, y si se lo restaura de la
      // papelera tiene que volver a procesarse.
      try {
        await _processingStates.requeue(item.id);
        // Ver el mismo resguardo en el registro de un fallo, abajo.
        // ignore: avoid_catches_without_on_clauses
      } catch (requeueError, requeueStack) {
        _logger.error(
          'No se pudo dejar en espera ${item.id}.',
          requeueError,
          requeueStack,
        );
      }
      return left(
        const Failure.unexpected(message: 'Se abandonó: el elemento se borró.'),
      );
      // Catch-all deliberado: acá entra cualquier cosa que pueda salir de la
      // red o de un parser ajeno, incluidos `Error`s que no son `Exception`.
      // Dejar escapar uno cortaría la cola entera y dejaría el elemento
      // atascado en "en curso" para siempre.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      final reason = processingFailureReasonFor(e);
      _logger.error(
        'No se pudo procesar ${item.id} (${reason.name}).',
        e,
        stackTrace,
      );
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'ProcessItemUseCase: ${item.source.kind.name}',
      );

      // Solo cambia el estado y el motivo: un fallo de red no puede costarle
      // al usuario el enlace que guardó, ni lo que editó mientras esperaba.
      try {
        await _processingStates.fail(item.id, reason);
        // Si ni siquiera se puede registrar el fallo, la base está en
        // problemas: se informa, pero no se deja escapar —cortaría la cola—.
        // ignore: avoid_catches_without_on_clauses
      } catch (failError, failStack) {
        _logger.error(
          'Tampoco se pudo registrar el fallo de ${item.id}.',
          failError,
          failStack,
        );
      }

      return left(Failure.unexpected(message: e.toString()));
    }
  }

  /// Fire-and-forget, dos veces: no bloquea `_process()` ni propaga un
  /// error de ningún generador — un fallo acá no puede tumbar el
  /// resultado de haber procesado el elemento con éxito. `.catchError` es
  /// una red de seguridad adicional a la que ya tiene cada `generate()`
  /// por su cuenta.
  ///
  /// Los dos corren en paralelo entre sí, sin ningún orden que respetar, y
  /// ninguno usa el modelo de lenguaje: los duplicados se detectan sin IA y
  /// la referencia (F15, D12) se lee del archivo —y puede no encontrar nada
  /// que leer, una nota, una imagen; eso no es un fallo—. Los vínculos y las
  /// propiedades, que antes se proponían acá, los hace la IA después, en su
  /// propia cola (F27, `AiOrganizeQueue`): el elemento queda listo sin
  /// esperarla.
  /// Si al elemento le queda trabajo del «Contenido». Un fallo al
  /// preguntarlo no frena al elemento: se registra y se sigue sin él.
  Future<bool> _hasAttachmentWork(String itemId) async {
    final work = _attachmentWork;
    if (work == null) return false;
    try {
      return await work.hasWork(itemId);
      // Ver el mismo resguardo en `_reextractionRequested`.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _logger.error(
        'No se pudo saber si a $itemId le queda algo por bajar.',
        e,
        stackTrace,
      );
      return false;
    }
  }

  void _generateSuggestions(Either<Failure, KnowledgeItem> result) {
    result.match((_) {}, (saved) {
      unawaited(
        _duplicateSuggestionGenerator.generate(saved).catchError((_, __) {}),
      );
      unawaited(
        _metadataSuggestionGenerator.generate(saved).catchError((_, __) {}),
      );
    });
  }
}

/// Vigila el trabajo de un transformador, entre él y la cola.
///
/// Dos reglas, según el carril: en el corto, un tope fijo —pasado ese tiempo
/// algo se trabó—; en el largo, que no deje de avanzar —una transcripción de
/// cuatro horas tarda lo que tarda, pero si pasa [_stallLimit] sin informar
/// nada, se colgó—. Esperar turno para entrar al carril largo no cuenta para
/// ninguna de las dos: detrás de una transcripción larga, esperar es lo
/// normal.
class _Watchdog implements TransformContext {
  _Watchdog(
    this._outer, {
    required Duration? shortLimit,
    required Duration stallLimit,
  }) : _stallLimit = stallLimit {
    if (shortLimit != null) _timer = Timer(shortLimit, _expire);
  }

  final TransformContext _outer;
  final Duration _stallLimit;
  final _expired = Completer<void>();
  Timer? _timer;
  var _inLongLane = false;
  var _disposed = false;

  /// Lanza [TimeoutException] cuando vence alguna de las dos reglas.
  Future<T> expired<T>() => _expired.future.then<T>(
    (_) => throw TimeoutException(
      _inLongLane
          ? 'Dejó de avanzar en el carril largo.'
          : 'Superó el tope del trabajo corto.',
    ),
  );

  void _expire() {
    if (!_expired.isCompleted) _expired.complete();
  }

  void _arm(Duration duration) {
    _timer?.cancel();
    if (!_disposed) _timer = Timer(duration, _expire);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  @override
  bool get isCancelled => _outer.isCancelled;

  @override
  Future<void> get whenCancelled => _outer.whenCancelled;

  @override
  void throwIfCancelled() => _outer.throwIfCancelled();

  @override
  Future<void> enterLongLane() async {
    if (_inLongLane) return;
    _inLongLane = true;
    // Esperar turno no cuenta: el tope del corto se desarma, y el de "sin
    // avance" se arma recién al entrar.
    _timer?.cancel();
    await _outer.enterLongLane();
    _arm(_stallLimit);
  }

  @override
  void reportProgress(int done, int total) {
    _outer.reportProgress(done, total);
    if (_inLongLane) _arm(_stallLimit);
  }
}
