import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';
import 'package:sinapsis/features/chat/domain/usecases/ask_vault_question_usecase.dart';

class _FakeVaultRetriever implements VaultRetriever {
  _FakeVaultRetriever(this.sources);

  final List<ChatSource> sources;
  String? lastQuestion;
  Set<String>? lastScopeIds;

  @override
  Future<List<ChatSource>> retrieve(
    String question, {
    int limit = 4,
    Set<String>? scopeIds,
  }) async {
    lastQuestion = question;
    lastScopeIds = scopeIds;
    return sources;
  }
}

class _FakeChatModelManager implements ChatModelManager {
  _FakeChatModelManager({required this.ready});

  final bool ready;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<int?> downloadSizeInBytes() async => null;

  @override
  Stream<double> download({String? huggingFaceToken}) => const Stream.empty();

  @override
  Future<bool> isDownloading() async => false;

  @override
  Future<void> cancelDownload() async {}
}

class _FakeChatModel implements ChatModel {
  _FakeChatModel({this.response, this.error});

  final String? response;
  final Object? error;
  List<ChatSource>? lastSources;

  @override
  Future<String> answer({
    required String question,
    required List<ChatSource> sources,
  }) async {
    lastSources = sources;
    final err = error;
    // El campo es `Object?` a propósito, para poder simular cualquier
    // fallo del motor de inferencia, no solo los que extienden Exception.
    // ignore: only_throw_errors
    if (err != null) throw err;
    return response!;
  }

  @override
  Future<FreeConversation> startConversation() =>
      throw UnimplementedError('no lo usa este caso de uso');

  @override
  Future<VaultConversation> startVaultConversation() =>
      throw UnimplementedError('no lo usa este caso de uso');
}

void main() {
  const source = ChatSource(
    itemId: 'item-1',
    itemTitle: 'Un artículo',
    excerpt: 'contenido relevante',
  );

  test(
    'sin ninguna fuente encontrada, no llama al modelo y devuelve vacío',
    () async {
      final model = _FakeChatModel(response: 'no debería usarse');
      final usecase = AskVaultQuestionUseCase(
        retriever: _FakeVaultRetriever(const []),
        model: model,
        modelManager: _FakeChatModelManager(ready: true),
      );

      final result = await usecase(
        const AskVaultQuestionParams(question: 'cualquier pregunta'),
      );

      final answer = result.getRight().toNullable()!;
      expect(answer.text, isNull);
      expect(answer.sources, isEmpty);
      expect(model.lastSources, isNull);
    },
  );

  test(
    'con fuentes pero sin el modelo listo, devuelve las fuentes sin texto',
    () async {
      final model = _FakeChatModel(response: 'no debería usarse');
      final usecase = AskVaultQuestionUseCase(
        retriever: _FakeVaultRetriever([source]),
        model: model,
        modelManager: _FakeChatModelManager(ready: false),
      );

      final result = await usecase(
        const AskVaultQuestionParams(question: 'una pregunta'),
      );

      final answer = result.getRight().toNullable()!;
      expect(answer.text, isNull);
      expect(answer.sources, [source]);
      expect(model.lastSources, isNull);
    },
  );

  test(
    'con fuentes y el modelo listo, redacta una respuesta con ellas',
    () async {
      final usecase = AskVaultQuestionUseCase(
        retriever: _FakeVaultRetriever([source]),
        model: _FakeChatModel(response: 'La respuesta redactada [1].'),
        modelManager: _FakeChatModelManager(ready: true),
      );

      final result = await usecase(
        const AskVaultQuestionParams(question: 'una pregunta'),
      );

      final answer = result.getRight().toNullable()!;
      expect(answer.text, 'La respuesta redactada [1].');
      expect(answer.sources, [source]);
    },
  );

  test('la pregunta llega tal cual al buscador de fuentes', () async {
    final retriever = _FakeVaultRetriever([source]);
    final usecase = AskVaultQuestionUseCase(
      retriever: retriever,
      model: _FakeChatModel(response: 'x'),
      modelManager: _FakeChatModelManager(ready: true),
    );

    await usecase(
      const AskVaultQuestionParams(question: '¿qué dice sobre esto?'),
    );

    expect(retriever.lastQuestion, '¿qué dice sobre esto?');
  });

  test('el alcance de un cuaderno llega tal cual al buscador', () async {
    final retriever = _FakeVaultRetriever([source]);
    final usecase = AskVaultQuestionUseCase(
      retriever: retriever,
      model: _FakeChatModel(response: 'x'),
      modelManager: _FakeChatModelManager(ready: true),
    );

    await usecase(
      const AskVaultQuestionParams(
        question: 'una pregunta',
        scopeIds: {'a', 'b'},
      ),
    );

    expect(retriever.lastScopeIds, {'a', 'b'});
  });

  test('un fallo del motor de inferencia se traduce a un Failure', () async {
    final usecase = AskVaultQuestionUseCase(
      retriever: _FakeVaultRetriever([source]),
      model: _FakeChatModel(error: StateError('el motor nativo explotó')),
      modelManager: _FakeChatModelManager(ready: true),
    );

    final result = await usecase(
      const AskVaultQuestionParams(question: 'una pregunta'),
    );

    expect(result.getLeft().toNullable(), isA<UnexpectedFailure>());
  });
}
