import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_events_reply.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_passage_selector.dart';

import '../../../../support/fake_inference_chat.dart';
import '../../../../support/fake_inference_model.dart';

/// Pedirle al modelo de la persona los hechos fechados de un documento (F40),
/// con un Gemma de mentira que contesta lo grabado.
void main() {
  late FakeInferenceModel model;
  late GemmaChatModel gemma;
  var reply = '';

  const text =
      'Charles Darwin fue un naturalista inglés. '
      'En 1859 publicó El origen de las especies. '
      'Murió en 1882 en Down House.';

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
    reply =
        'HECHO: 1859 | - | Publica El origen de las especies | '
        'En 1859 publicó El origen de las especies.\n'
        'HECHO: 1882 | - | Muere Darwin | Murió en 1882 en Down House.';
    model = FakeInferenceModel(
      newChat: (n) => FakeInferenceChat(id: n, answer: (_, _) => [reply]),
    );
    gemma = build();
  });

  DatedTextPart partOf(String content) =>
      selectDatedParts(content, maxChars: 3000).single;

  test('pide los pasajes numerados, con su instrucción y su tope, y lee los '
      'hechos', () async {
    final part = partOf(text);

    final outcome = await gemma.datedEventsOf(part);

    final opened = model.opened.single;
    expect(opened.instruction, contains('HECHO: <fecha> | <fin> | <título>'));
    expect(opened.instruction, contains('| <cita>'));
    expect(opened.instruction, contains('TEXTUALMENTE'));
    expect(opened.instruction, contains('ÚNICAMENTE'));
    // El formato de cada fecha, con un ejemplo de cada precisión.
    for (final example in [
      '1859 (año)',
      '1809-02 (mes)',
      '1809-02-12 (día)',
      '44 a.C.',
      '476 d.C.',
      's. XIX (siglo)',
      's. V a.C.',
      'década 1920',
      'c. 1500',
    ]) {
      expect(opened.instruction, contains(example), reason: example);
    }
    expect(opened.instruction, contains('precisión que dice el texto'));
    expect(opened.instruction, contains('o - si no duró'));
    expect(opened.instruction, contains('idioma del texto'));
    expect(opened.instruction, contains('Ejemplo:\nHECHO: 1859 | - |'));
    expect(
      opened.instruction,
      contains(
        'Publica El origen de las especies | '
        'En 1859 Darwin publicó El origen de las especies.',
      ),
    );
    expect(opened.instruction, contains('no escribas nada'));
    expect(opened.maxOutputTokens, datedEventsReplyTokens(1));
    expect(model.chats.single.received.single, buildDatedEventsPrompt(part));
    expect(model.chats.single.closed, isTrue);

    expect(outcome.analyzed, 1);
    expect(outcome.events.map((e) => e.date.year), [1859, 1882]);
    expect(outcome.events.map((e) => e.title), [
      'Publica El origen de las especies',
      'Muere Darwin',
    ]);
    for (final event in outcome.events) {
      expect(text.substring(event.start, event.end), event.excerpt);
    }
  });

  test('descarta lo que el texto no dice: fecha o cita inventadas', () async {
    reply =
        'HECHO: 1860 | - | Publica su libro | '
        'En 1859 publicó El origen de las especies.\n'
        'HECHO: 1859 | - | Escribe un libro | '
        'En 1859 escribió un libro nuevo.\n'
        'HECHO: 1882 | - | Muere Darwin | Murió en 1882 en Down House.';

    final outcome = await gemma.datedEventsOf(partOf(text));

    expect(outcome.analyzed, 1);
    expect(outcome.events.map((e) => e.title), ['Muere Darwin']);
  });

  test(
    'si no contesta en el formato, no hay hechos, pero el pedido se leyó',
    () async {
      reply = 'Darwin fue un gran científico.';

      final outcome = await gemma.datedEventsOf(partOf(text));

      expect(outcome.analyzed, 1);
      expect(outcome.events, isEmpty);
    },
  );

  test('las fechas se leen con su precisión', () async {
    const content = 'Nació el 12 de febrero de 1809 en Shrewsbury.';
    reply =
        'HECHO: 1809-02-12 | - | Nace Darwin | '
        'Nació el 12 de febrero de 1809 en Shrewsbury.';

    final outcome = await gemma.datedEventsOf(partOf(content));

    expect(outcome.events.single.date.precision, DatePrecision.day);
    expect(outcome.events.single.date.month, 2);
  });

  test(
    'si el pedido no entra en la ventana, lee los primeros pasajes que entran, '
    'con el tope de respuesta de esos',
    () async {
      // Seis pasajes de unos 340 caracteres, separados por párrafos sin fechas.
      final filler = 'Relleno sin fecha alguna. ' * 3;
      final detail = 'y siguió ' * 36;
      final content = [
        for (var i = 0; i < 6; i++)
          'En ${1800 + i} pasó el hecho número $i $detail.\n\n$filler',
      ].join('\n\n');
      final part = selectDatedParts(content, maxChars: 3000).single;
      expect(part.passages, hasLength(6));
      gemma = build(contextTokens: 900);

      final outcome = await gemma.datedEventsOf(part);

      expect(outcome.analyzed, lessThan(6));
      expect(outcome.analyzed, greaterThan(0));
      // Se midió con una sesión y se pidió con otra, con el tope de lo que
      // entró; la primera se cerró antes de abrir la segunda.
      expect(model.opened, hasLength(2));
      expect(model.chats.first.received, isEmpty);
      expect(model.chats.first.closed, isTrue);
      expect(
        model.opened.last.maxOutputTokens,
        datedEventsReplyTokens(outcome.analyzed),
      );
      final fitted = DatedTextPart(part.passages.sublist(0, outcome.analyzed));
      final sent = model.chats.last.received.single;
      expect(sent, buildDatedEventsPrompt(fitted));
      final room =
          900 -
          datedEventsReplyTokens(outcome.analyzed) -
          (model.opened.last.instruction!.length / 4).ceil() -
          kPromptMarginTokens;
      expect((sent.length / 4).ceil(), lessThanOrEqualTo(room));
      expect(model.chats.last.closed, isTrue);

      // Lo que falta se puede pedir después, sin repetir ni perder nada.
      final rest = part.after(outcome.analyzed);
      expect(rest, isNotNull);
      expect(outcome.analyzed + rest!.passages.length, part.passages.length);
    },
  );

  test('un solo pasaje que no entra se manda igual: al menos uno', () async {
    final content = 'En 1859 pasó algo. ${'palabra ' * 80}';
    gemma = build(contextTokens: 200);

    final outcome = await gemma.datedEventsOf(partOf(content));

    expect(outcome.analyzed, 1);
    expect(model.opened, hasLength(1));
  });

  test('el tamaño de pedido sale de la ventana del modelo elegido', () {
    expect(
      build().datedPartCharBudget,
      textBudgetFor(kGemmaContextTokens).partChars,
    );
    expect(build().datedPartCharBudget, 3000);
    expect(build(contextTokens: 1 << 20).datedPartCharBudget, kMaxPartChars);
    expect(
      build(contextTokens: 1 << 20).datedPartCharBudget,
      greaterThan(build().datedPartCharBudget),
    );
  });

  test('de punta a punta: del texto de un documento a los hechos del texto '
      'entero', () async {
    const birth =
        'Charles Darwin nació en Shrewsbury. Nació el 12 de febrero de 1809 '
        'en una familia rica.';
    final document = [
      'Biografía de Darwin.',
      birth,
      'Relleno ' * 60,
      'Zarpó en el Beagle en 1831 rumbo a Sudamérica.',
    ].join('\n\n');
    final part = selectDatedParts(
      document,
      maxChars: gemma.datedPartCharBudget,
    ).single;
    reply =
        'HECHO: 1809-02-12 | - | Nace Darwin | '
        'Nació el 12 de febrero de 1809 en una familia rica.\n'
        'HECHO: 1831 | - | Zarpa el Beagle | '
        'Zarpó en el Beagle en 1831 rumbo a Sudamérica.';

    final outcome = await gemma.datedEventsOf(part);

    expect(outcome.events, hasLength(2));
    expect(outcome.events[0].start, document.indexOf('Nació el 12 de febrero'));
    expect(outcome.events[1].start, document.indexOf('Zarpó en el Beagle'));
    for (final event in outcome.events) {
      expect(document.substring(event.start, event.end), event.excerpt);
    }
  });
}
