import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';

/// Lo que se calcula de lo medido (F30).
void main() {
  test('la velocidad se cuenta mientras escribe, sin la espera inicial', () {
    const reply = LanguageModelReply(
      kind: LanguageModelReplyKind.chat,
      firstToken: Duration(seconds: 2),
      total: Duration(seconds: 12),
      tokens: 101,
      words: 50,
    );

    // 100 tokens después del primero, en los 10 s que tardó en escribir.
    expect(reply.tokensPerSecond, closeTo(10, 0.001));
    expect(reply.wordsPerSecond, closeTo(5, 0.001));
  });

  test('sin primera palabra o con un solo token, no hay velocidad', () {
    const empty = LanguageModelReply(
      kind: LanguageModelReplyKind.task,
      total: Duration(seconds: 3),
      words: 0,
    );
    const single = LanguageModelReply(
      kind: LanguageModelReplyKind.task,
      firstToken: Duration(seconds: 1),
      total: Duration(seconds: 1),
      tokens: 1,
      words: 1,
    );

    expect(empty.tokensPerSecond, isNull);
    expect(empty.wordsPerSecond, isNull);
    expect(single.tokensPerSecond, isNull);
    expect(single.wordsPerSecond, isNull);
  });

  test('cayó a la CPU solo si no se la pidió', () {
    const fellBack = LanguageModelLoad(
      duration: Duration(seconds: 9),
      backend: LanguageModelBackend.cpu,
      requestedBackend: null,
      vision: false,
    );
    const chosen = LanguageModelLoad(
      duration: Duration(seconds: 9),
      backend: LanguageModelBackend.cpu,
      requestedBackend: LanguageModelBackend.cpu,
      vision: false,
    );

    expect(fellBack.fellBackToCpu, isTrue);
    expect(chosen.fellBackToCpu, isFalse);
  });
}
