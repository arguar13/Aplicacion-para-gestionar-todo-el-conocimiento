import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_suggestion_generator.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/reference/domain/services/metadata_suggestion_generator.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_generator.dart';
import 'package:sinapsis/features/suggestions/domain/services/relation_suggestion_generator.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_state_repository.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/merge_transform_result.dart';
import 'package:sinapsis/features/transform/domain/usecases/processing_failure_classifier.dart';

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
    required PropertySuggestionGenerator suggestionGenerator,
    required RelationSuggestionGenerator relationSuggestionGenerator,
    required DuplicateSuggestionGenerator duplicateSuggestionGenerator,
    required MetadataSuggestionGenerator metadataSuggestionGenerator,
  }) : _registry = registry,
       _repository = repository,
       _processingStates = processingStates,
       _logger = logger,
       _telemetry = telemetry,
       _clock = clock,
       _suggestionGenerator = suggestionGenerator,
       _relationSuggestionGenerator = relationSuggestionGenerator,
       _duplicateSuggestionGenerator = duplicateSuggestionGenerator,
       _metadataSuggestionGenerator = metadataSuggestionGenerator;

  final TransformerRegistry _registry;
  final LibraryRepository _repository;
  final ProcessingStateRepository _processingStates;
  final AppLogger _logger;
  final TelemetryService _telemetry;
  final Clock _clock;
  final PropertySuggestionGenerator _suggestionGenerator;
  final RelationSuggestionGenerator _relationSuggestionGenerator;
  final DuplicateSuggestionGenerator _duplicateSuggestionGenerator;
  final MetadataSuggestionGenerator _metadataSuggestionGenerator;

  @override
  Future<Either<Failure, KnowledgeItem>> call(String itemId) => process(itemId);

  /// Procesa [itemId]. Si [cancellation] pide abandonar —el elemento se borró
  /// mientras tanto—, se lo suelta en el acto: no se espera a que termine lo
  /// que quedó corriendo, y su resultado no se guarda.
  Future<Either<Failure, KnowledgeItem>> process(
    String itemId, {
    CancellationSignal? cancellation,
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

    return _process(item, cancellation);
  }

  Future<Either<Failure, KnowledgeItem>> _process(
    KnowledgeItem item,
    CancellationSignal? cancellation,
  ) async {
    final transformer = _registry.resolve(item);

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

      // El tope del trabajo corto: pasado ese tiempo algo se trabó, y
      // esperarlo frenaría la cola entera. Ni el tope ni la cancelación
      // cortan lo que quedó corriendo —cada pedido a la red termina solo, con
      // su propio límite—: la cola sigue y el resultado tardío se descarta.
      final limit = transformer.timeLimit;
      var work = transformer.transform(item);
      if (limit != null) work = work.timeout(limit);
      final enriched = await _unlessCancelled(work, cancellation);

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
        return _repository.save(
          mergeTransformResult(
            original: item,
            enriched: enriched,
            current: current,
          ).copyWith(
            processingState: ProcessingState.ready,
            updatedAt: _clock(),
          ),
        );
      });
      if (result.isRight()) await _processingStates.succeed(item.id);
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

  /// [work], salvo que antes se pida abandonar: entonces lanza
  /// [ProcessingCancelledException] en el acto, sin esperar a [work].
  Future<T> _unlessCancelled<T>(
    Future<T> work,
    CancellationSignal? cancellation,
  ) {
    if (cancellation == null) return work;
    return Future.any([
      work,
      cancellation.whenCancelled.then<T>(
        (_) => throw const ProcessingCancelledException(),
      ),
    ]);
  }

  /// Fire-and-forget, cuatro veces: no bloquea `_process()` ni propaga un
  /// error de ningún generador — un fallo acá no puede tumbar el
  /// resultado de haber procesado el elemento con éxito. `.catchError` es
  /// una red de seguridad adicional a la que ya tiene cada `generate()`
  /// por su cuenta.
  ///
  /// Los cuatro generadores corren en paralelo entre sí, sin ningún orden
  /// que respetar: cada uno ya resuelve su propia dependencia interna de
  /// orden por su cuenta (ver F5, D8) — solo el motor de relaciones tiene
  /// pasos que dependen entre sí, y esos viven todos dentro de su propio
  /// `generate()`. El de referencia (F15, D12) es el único de los cuatro
  /// que puede no encontrar nada que leer —una nota, una imagen— y no
  /// generar ninguna sugerencia; eso no es un fallo.
  void _generateSuggestions(Either<Failure, KnowledgeItem> result) {
    result.match((_) {}, (saved) {
      unawaited(_suggestionGenerator.generate(saved).catchError((_, __) {}));
      unawaited(
        _relationSuggestionGenerator.generate(saved).catchError((_, __) {}),
      );
      unawaited(
        _duplicateSuggestionGenerator.generate(saved).catchError((_, __) {}),
      );
      unawaited(
        _metadataSuggestionGenerator.generate(saved).catchError((_, __) {}),
      );
    });
  }
}
