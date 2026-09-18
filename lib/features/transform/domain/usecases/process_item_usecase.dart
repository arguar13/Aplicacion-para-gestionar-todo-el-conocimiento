import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_generator.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';

/// Trae el contenido de un elemento que quedó pendiente.
///
/// El orden de los pasos importa, y todos existen por una razón:
///
/// 1. Se marca **en curso** y se guarda, antes de empezar. Eso es lo que hace
///    que la interfaz pueda mostrar que algo está trabajando — la lista
///    escucha los cambios de la base, así que ve el cambio de estado sola.
/// 2. Se transforma. Acá es donde se sale a la red, se tarda y se puede
///    fallar.
/// 3. Se guarda el resultado como **listo**.
///
/// Si el paso 2 falla, el elemento queda **fallido** pero conserva todo lo
/// que ya tenía: su enlace, su título provisional, la nota del usuario. Nunca
/// se borra nada por un error de red. Rechazar algo porque una etapa opcional
/// no funcionó sería peor que aceptarlo incompleto, y además se puede
/// reintentar cuando haya conexión.
class ProcessItemUseCase implements UseCase<KnowledgeItem, String> {
  const ProcessItemUseCase({
    required TransformerRegistry registry,
    required LibraryRepository repository,
    required AppLogger logger,
    required TelemetryService telemetry,
    required Clock clock,
    required PropertySuggestionGenerator suggestionGenerator,
  }) : _registry = registry,
       _repository = repository,
       _logger = logger,
       _telemetry = telemetry,
       _clock = clock,
       _suggestionGenerator = suggestionGenerator;

  final TransformerRegistry _registry;
  final LibraryRepository _repository;
  final AppLogger _logger;
  final TelemetryService _telemetry;
  final Clock _clock;
  final PropertySuggestionGenerator _suggestionGenerator;

  @override
  Future<Either<Failure, KnowledgeItem>> call(String itemId) async {
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

    return _process(item);
  }

  Future<Either<Failure, KnowledgeItem>> _process(KnowledgeItem item) async {
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
      _generateSuggestions(result);
      return result;
    }

    // Se publica el "en curso" antes de empezar, para que la interfaz lo
    // muestre mientras dura.
    await _repository.save(
      item.copyWith(
        processingState: ProcessingState.processing,
        updatedAt: _clock(),
      ),
    );

    try {
      final enriched = await transformer.transform(item);

      final result = await _repository.save(
        enriched.copyWith(
          processingState: ProcessingState.ready,
          updatedAt: _clock(),
        ),
      );
      _generateSuggestions(result);
      return result;
      // Catch-all deliberado: acá entra cualquier cosa que pueda salir de la
      // red o de un parser ajeno, incluidos `Error`s que no son `Exception`.
      // Dejar escapar uno cortaría la cola entera y dejaría el elemento
      // atascado en "en curso" para siempre.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _logger.error('No se pudo procesar ${item.id}.', e, stackTrace);
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'ProcessItemUseCase: ${item.source.kind.name}',
      );

      // Se guarda lo que el elemento ya tenía, solo con el estado cambiado:
      // un fallo de red no puede costarle al usuario el enlace que guardó.
      await _repository.save(
        item.copyWith(
          processingState: ProcessingState.failed,
          updatedAt: _clock(),
        ),
      );

      return left(Failure.unexpected(message: e.toString()));
    }
  }

  /// Fire-and-forget: no bloquea `_process()` ni propaga un error del
  /// generador — un fallo acá no puede tumbar el resultado de haber
  /// procesado el elemento con éxito. `.catchError` es una red de
  /// seguridad adicional a la que ya tiene `generate()` por su cuenta.
  void _generateSuggestions(Either<Failure, KnowledgeItem> result) {
    result.match(
      (_) {},
      (saved) => unawaited(
        _suggestionGenerator.generate(saved).catchError((_, __) {}),
      ),
    );
  }
}
