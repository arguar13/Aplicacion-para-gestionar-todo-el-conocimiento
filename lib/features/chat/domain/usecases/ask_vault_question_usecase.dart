import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/chat_answer.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';

/// Le pregunta algo a la bóveda: busca qué es relevante y, si el modelo de
/// lenguaje ya está descargado, redacta una respuesta citándolo.
///
/// Las dos mitades de RAG están separadas a propósito —`VaultRetriever` y
/// `ChatModel`, ver la decisión 20 en docs/arquitectura.md— y este caso de
/// uso es lo único que las conoce a las dos a la vez.
class AskVaultQuestionUseCase
    implements UseCase<ChatAnswer, AskVaultQuestionParams> {
  const AskVaultQuestionUseCase({
    required VaultRetriever retriever,
    required ChatModel model,
    required ChatModelManager modelManager,
  }) : _retriever = retriever,
       _model = model,
       _modelManager = modelManager;

  final VaultRetriever _retriever;
  final ChatModel _model;
  final ChatModelManager _modelManager;

  @override
  Future<Either<Failure, ChatAnswer>> call(
    AskVaultQuestionParams params,
  ) async {
    final question = params.question;
    final sources = await _retriever.retrieve(
      question,
      scopeIds: params.scopeIds,
    );

    // Sin ninguna fuente, no hay nada que contestar — ni el modelo de
    // lenguaje más grande inventa un dato que no está en la bóveda sin que
    // eso sea, en los hechos, una alucinación con buena redacción.
    if (sources.isEmpty) {
      return right(const ChatAnswer());
    }

    final modelReady = await _modelManager.isReady();
    if (!modelReady) {
      // Degradar antes que fallar (principio 4): sin el modelo, se listan
      // las fuentes igual, sin redactar nada. Buscar ya sirve de algo antes
      // de pedirle a nadie que baje varios gigas.
      return right(ChatAnswer(sources: sources));
    }

    try {
      final text = await _model.answer(question: question, sources: sources);
      return right(ChatAnswer(text: text, sources: sources));
      // El motor de inferencia es de terceros (flutter_gemma); puede fallar
      // de formas que no tienen un tipo propio en Dart —memoria
      // insuficiente, un error nativo de la biblioteca de inferencia—.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}

class AskVaultQuestionParams {
  const AskVaultQuestionParams({required this.question, this.scopeIds});

  final String question;

  /// Acota la búsqueda a estos elementos (F16, D1) — lo que un cuaderno
  /// resuelve—; `null` es "toda la bóveda".
  final Set<String>? scopeIds;
}
