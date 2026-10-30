import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/language_model_tasks.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/model_backend.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_style.dart';

/// Lo que se le mandó al motor en un intercambio.
typedef _Sent = ({String instruction, String prompt});

/// Un motor de mentira que contesta siempre una tarjeta y anota cada pedido.
class _Backend implements ModelBackend {
  final sent = <_Sent>[];

  @override
  int get contextTokens => 100000;

  @override
  ModelBackend get forBackground => this;

  @override
  bool get isWarm => true;

  @override
  Future<void> warmUp() async {}

  @override
  Future<ModelExchange> openExchange({
    required String instruction,
    required int maxOutputTokens,
  }) async => _Exchange(this, instruction);

  @override
  Future<ModelConversation> openConversation({
    required String instruction,
    required int maxOutputTokens,
  }) => throw UnimplementedError();
}

class _Exchange implements ModelExchange {
  _Exchange(this._backend, this._instruction);

  final _Backend _backend;
  final String _instruction;

  @override
  Future<int> countTokens(String text) async => (text.length / 3).ceil();

  @override
  Future<String> reply(
    String text, {
    LanguageModelReplyKind kind = LanguageModelReplyKind.task,
  }) async {
    _backend.sent.add((instruction: _instruction, prompt: text));
    return 'P: Who led the people?\nR: Moses.\nC: Moisés guía al pueblo.';
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {}
}

/// Las tarjetas de la cola con lo elegido en «Para cada documento» (F43,
/// M18): el idioma, la dificultad y el tema llegan al pedido; sin nada
/// elegido, el pedido es el de siempre.
void main() {
  late _Backend backend;
  late LanguageModelTasks tasks;

  setUp(() {
    backend = _Backend();
    tasks = LanguageModelTasks(gate: LanguageModelGate(), backend: backend);
  });

  test('sin estilo, el pedido de siempre, letra por letra', () async {
    await tasks.generate(content: 'Moisés guía al pueblo.', count: 3);

    final sent = backend.sent.single;
    expect(sent.instruction, startsWith('Respondé siempre en español. '));
    expect(
      sent.prompt,
      'Generá hasta 3 tarjetas a partir de este contenido:\n\n'
      'Moisés guía al pueblo.',
    );
    // Un estilo que no cambia el pedido es el mismo generador.
    expect(
      identical(tasks.flashcardsWith(FlashcardStyle.plain), tasks),
      isTrue,
    );
    expect(
      identical(
        tasks.flashcardsWith(
          const FlashcardStyle(amount: FlashcardAmount.more),
        ),
        tasks,
      ),
      isTrue,
    );
  });

  test('con otro idioma, la pregunta y la respuesta van en ese; la cita, en '
      'el del contenido', () async {
    final drafts = await tasks
        .flashcardsWith(const FlashcardStyle(languageCode: 'en'))
        .generate(content: 'Moisés guía al pueblo.', count: 2);

    expect(drafts.single.front, 'Who led the people?');
    final sent = backend.sent.single;
    expect(sent.instruction, isNot(contains('en español')));
    expect(sent.instruction, startsWith('Escribí la pregunta y la respuesta '));
    expect(sent.instruction, contains('inglés'));
    expect(sent.instruction, contains('La frase de C: va en el idioma del'));
    expect(sent.instruction, contains('P: <pregunta>'));
  });

  test('la dificultad y el tema van en el pedido', () async {
    await tasks
        .flashcardsWith(
          const FlashcardStyle(
            difficulty: FlashcardDifficulty.hard,
            topic: '  Moisés y Faraón ',
          ),
        )
        .generate(content: 'Moisés guía al pueblo.', count: 4);

    final sent = backend.sent.single;
    expect(sent.instruction, startsWith('Respondé siempre en español. '));
    expect(sent.prompt, startsWith('Generá hasta 4 tarjetas (preguntas '));
    expect(sent.prompt, contains('exigentes'));
    expect(sent.prompt, contains('«Moisés y Faraón»'));
    expect(sent.prompt, endsWith(':\n\nMoisés guía al pueblo.'));
  });

  test('cada dificultad se dice distinto', () {
    String ask(FlashcardDifficulty d) =>
        flashcardPromptFor('x', count: 1, style: FlashcardStyle(difficulty: d));
    expect(ask(FlashcardDifficulty.easy), contains('recién empieza'));
    expect(ask(FlashcardDifficulty.medium), contains('entender las ideas'));
    expect(ask(FlashcardDifficulty.hard), contains('comparar'));
  });

  test('el español con región sigue siendo el de siempre', () {
    const style = FlashcardStyle(languageCode: 'es-AR');
    expect(style.isSpanish, isTrue);
    expect(style.changesPrompt, isFalse);
    expect(
      flashcardInstructionFor(style),
      flashcardInstructionFor(FlashcardStyle.plain),
    );
  });
}
