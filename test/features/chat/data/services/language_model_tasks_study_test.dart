import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';

import '../../../../support/fake_inference_chat.dart';
import '../../../../support/fake_inference_model.dart';

/// Marcar una parte de un documento para estudiarlo (F36), con el modelo de
/// la persona —acá, un Gemma de mentira que contesta lo grabado—.
void main() {
  late FakeInferenceModel model;
  late GemmaChatModel gemma;
  var reply = 'RESUMEN: 1\nSINTESIS: 1\nCLAVE 1: revolución';

  const content =
      'La revolución industrial empezó en Inglaterra. '
      'Las fábricas usaban vapor. '
      'El trabajo infantil era común.';
  final part = splitStudySentences(content, markdown: false);

  GemmaChatModel build({int contextTokens = kGemmaContextTokens}) {
    final meter = LanguageModelMeter();
    return GemmaChatModel(
      gate: LanguageModelGate(),
      engine: GemmaEngine(
        ensureReady: () async => true,
        meter: meter,
        contextTokens: contextTokens,
        load: (_) async => model,
      ),
      meter: meter,
      countTokens: (_, text) async => (text.length / 4).ceil(),
    );
  }

  setUp(() {
    reply = 'RESUMEN: 1\nSINTESIS: 1\nCLAVE 1: revolución';
    model = FakeInferenceModel(
      newChat: (n) => FakeInferenceChat(id: n, answer: (_, _) => [reply]),
    );
    gemma = build();
  });

  test('pide la parte numerada, con su instrucción y su tope, y lee lo que '
      'marca', () async {
    final outcome = await gemma.markPart(content: content, part: part);

    final opened = model.opened.single;
    expect(opened.instruction, contains('RESUMEN: <números'));
    expect(opened.instruction, contains('SINTESIS: <números'));
    expect(opened.instruction, contains('CLAVE <número>:'));
    expect(opened.instruction, contains('TEXTUALMENTE'));
    // Las palabras clave de todas las oraciones, no solo de las marcadas
    // (F39).
    expect(opened.instruction, contains('para CADA oración'));
    expect(opened.instruction, contains('sin saltear ninguna'));
    expect(opened.maxOutputTokens, studyReplyTokens(part.length));
    expect(model.chats.single.received.single, buildStudyPrompt(content, part));
    expect(model.chats.single.closed, isTrue);

    expect(outcome.analyzed, part.length);
    expect(outcome.marks!.summary, [part.first]);
    expect(outcome.marks!.synthesis, [part.first]);
    expect(
      outcome.marks!.keywords.map((w) => content.substring(w.start, w.end)),
      ['revolución'],
    );
  });

  test(
    'si no contesta en el formato, no hay marcas, pero la parte se leyó',
    () async {
      reply = 'Es un texto sobre historia.';

      final outcome = await gemma.markPart(content: content, part: part);

      expect(outcome.analyzed, part.length);
      expect(outcome.marks, isNull);
    },
  );

  test(
    'si la parte no entra en la ventana, analiza las primeras que entran, '
    'con el tope de respuesta de esas: cada oración trae su línea CLAVE',
    () async {
      final long = [
        for (var i = 0; i < 60; i++)
          'Una oración bastante larga, la número $i, para llenar la ventana.',
      ].join(' ');
      final sentences = splitStudySentences(long, markdown: false);
      gemma = build(contextTokens: 1024);

      final outcome = await gemma.markPart(content: long, part: sentences);

      expect(outcome.analyzed, lessThan(sentences.length));
      expect(outcome.analyzed, greaterThan(1));
      // Se midió con una sesión y se pidió con otra, con el tope de lo que
      // entró; la primera se cerró antes de abrir la segunda.
      expect(model.opened, hasLength(2));
      expect(model.chats.first.received, isEmpty);
      expect(model.chats.first.closed, isTrue);
      expect(
        model.opened.last.maxOutputTokens,
        studyReplyTokens(outcome.analyzed),
      );
      final sent = model.chats.last.received.single;
      expect(
        sent,
        buildStudyPrompt(long, sentences.sublist(0, outcome.analyzed)),
      );
      final room =
          1024 -
          studyReplyTokens(outcome.analyzed) -
          (model.opened.last.instruction!.length / 4).ceil() -
          kPromptMarginTokens;
      expect((sent.length / 4).ceil(), lessThanOrEqualTo(room));
      expect(model.chats.last.closed, isTrue);
    },
  );

  test('el tamaño de parte sale de la ventana del modelo elegido', () async {
    expect(build().partCharBudget, studyPartCharBudget(kGemmaContextTokens));
    expect(
      build(contextTokens: 1 << 20).partCharBudget,
      studyPartCharBudget(1 << 20),
    );
    expect(
      studyPartCharBudget(1 << 20),
      greaterThan(studyPartCharBudget(kGemmaContextTokens)),
    );
  });
}
