import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_reviewer.dart';
import 'package:sinapsis/features/ai_organize/domain/services/things_reviewer.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';

import '../../../../support/fake_inference_chat.dart';
import '../../../../support/fake_inference_model.dart';

/// `GemmaChatModel` sobre un `flutter_gemma` de mentira (F30).
void main() {
  late FakeInferenceModel model;
  late GemmaChatModel gemma;

  /// Con qué se pidió cargar el modelo, cada vez.
  late List<GemmaLoadRequest> loads;

  setUp(() {
    loads = [];
    model = FakeInferenceModel(
      newChat: (n) => FakeInferenceChat(
        id: n,
        answer: (_, prompt) => [
          if (prompt.contains('Temas:')) 'TEMA: 1 | alta' else 'Un resumen.',
        ],
      ),
    );
    final meter = LanguageModelMeter();
    gemma = GemmaChatModel(
      gate: LanguageModelGate(),
      engine: GemmaEngine(
        ensureReady: () async => true,
        meter: meter,
        load: (request) async {
          loads.add(request);
          return model;
        },
      ),
      meter: meter,
      countTokens: (_, text) async => (text.length / 4).ceil(),
    );
  });

  group('cada uso tiene su tope de largo', () {
    test('elegir un tema: una lÃ­nea', () async {
      final choice = await gemma.chooseSpace(
        itemTitle: 'El Senado',
        excerpt: 'El Senado romanoâ€¦',
        spaces: ['Roma', 'Grecia'],
      );

      expect(choice, isNotNull);
      expect(model.opened.single.maxOutputTokens, kChoiceReplyTokens);
      expect(model.chats.single.closed, isTrue);
    });

    test('un resumen: unos pÃ¡rrafos', () async {
      expect(await gemma.summarize(content: 'Texto largoâ€¦'), 'Un resumen.');
      expect(model.opened.single.maxOutputTokens, kSummaryReplyTokens);
    });

    test('las tarjetas: segÃºn cuÃ¡ntas se piden', () async {
      await gemma.generate(content: 'Textoâ€¦', count: 4);

      expect(model.opened.single.maxOutputTokens, draftsReplyTokens(4));
      expect(draftsReplyTokens(4), greaterThan(draftsReplyTokens(1)));
    });

    test('una charla: lo de una respuesta del chat', () async {
      final conversation = await gemma.startConversation();

      expect(model.opened.single.maxOutputTokens, kChatReplyTokens);
      await conversation.close();
    });
  });

  test('un derivado nunca le manda más de lo que entra en la ventana, '
      'contado con su tokenizador (F30)', () async {
    final sources = [
      for (var i = 0; i < 10; i++)
        ChatSource(
          itemId: 'f$i',
          itemTitle: 'Fuente $i',
          excerpt: List.filled(200, 'roma ').join(),
          sourceCharStart: 0,
          sourceCharEnd: 1000,
        ),
    ];

    final draft = await gemma.generateDerivedNote(
      type: DerivedNoteType.studyGuide,
      sources: sources,
    );

    expect(draft.isEmpty, isTrue);
    final instruction = model.opened.single.instruction!;
    final room =
        kGemmaContextTokens -
        kDerivedNoteReplyTokens -
        (instruction.length / 4).ceil() -
        kPromptMarginTokens;
    final sent = model.chats.single.received.single;
    expect((sent.length / 4).ceil(), lessThanOrEqualTo(room));
    expect(sent, contains('Fuente 0'));
    expect(model.chats.single.closed, isTrue);
  });

  test('«Crear con IA» le pregunta cuáles van, con la lista numerada, y lee '
      'su línea VAN (F30)', () async {
    model = FakeInferenceModel(
      newChat: (n) =>
          FakeInferenceChat(id: n, answer: (_, _) => ['VAN: 1, ', '3']),
    );

    final picks = await gemma.judgeNotebookCandidates(
      topic: 'mi tesis sobre Roma',
      candidates: [
        (title: 'El foro', excerpt: 'El centro de Roma.'),
        (title: 'Recetas', excerpt: 'Una torta.'),
        (title: 'El Senado', excerpt: 'Trescientos miembros.'),
      ],
    );

    expect(picks, {0, 2});
    expect(model.opened.single.maxOutputTokens, kNotebookPicksReplyTokens);
    final sent = model.chats.single.received.single;
    expect(sent, startsWith('Tema del cuaderno: mi tesis sobre Roma'));
    expect(sent, contains('3. El Senado\nTrescientos miembros.'));
    expect(model.chats.single.closed, isTrue);
  });

  test('«Revisar con otro modelo» le da cada tarjeta numerada con su pasaje, '
      'con su instrucción y su tope, y lee lo que propone (F33)', () async {
    model = FakeInferenceModel(
      newChat: (n) => FakeInferenceChat(
        id: n,
        answer: (_, _) => [
          'TARJETA 1: bien\nTARJETA 2: corregir\nP: ¿Quién escribió el ',
          'Quijote?\nR: Cervantes.\nPOR QUÉ: Lo dice el pasaje.\n',
        ],
      ),
    );

    final verdicts = await gemma.reviewFlashcards(const [
      FlashcardToReview(
        front: '¿Cuándo cayó Roma?',
        back: 'En 476.',
        passage: 'Roma cayó en 476.',
      ),
      FlashcardToReview(
        front: '¿Quién escribió el Quijote?',
        back: 'Lope de Vega.',
        passage: 'El Quijote lo escribió Cervantes.',
      ),
    ]);

    expect(verdicts, const [
      FlashcardCorrection(
        index: 1,
        reason: 'Lo dice el pasaje.',
        front: '¿Quién escribió el Quijote?',
        back: 'Cervantes.',
      ),
    ]);
    final opened = model.opened.single;
    expect(opened.maxOutputTokens, flashcardReviewReplyTokens(2));
    expect(opened.instruction, contains('TARJETA <número>: corregir'));
    expect(opened.instruction, contains('No agregues tarjetas nuevas'));
    final sent = model.chats.single.received.single;
    expect(
      sent,
      contains(
        'TARJETA 2\nP: ¿Quién escribió el Quijote?\nR: Lope de Vega.\n'
        'PASAJE: El Quijote lo escribió Cervantes.',
      ),
    );
    expect(sent, contains('TARJETA 1\nP: ¿Cuándo cayó Roma?'));
    expect(model.chats.single.closed, isTrue);
  });

  test(
    '«Revisar con otro modelo» le da lo demás numerado, con lo que tiene '
    'puesto, sus opciones y sus reglas, y lee lo que propone (F33)',
    () async {
      model = FakeInferenceModel(
        newChat: (n) => FakeInferenceChat(
          id: n,
          answer: (_, _) => [
            'DATO 1: bien\nDATO 2: corregir\nVALOR: novela\n',
            'POR QUÉ: Es una novela.\n',
          ],
        ),
      );

      final verdicts = await gemma.reviewThings(
        itemTitle: 'Rayuela',
        itemExcerpt: 'Una novela de Cortázar.',
        things: const [
          ThingToReview(
            subject: CorrectionSubject.relation,
            name: 'vínculo con «Cortázar»',
            value: 'relacionado',
            note: 'El autor.',
            options: ['relacionado', 'cita'],
            context: 'Un escritor argentino.',
          ),
          ThingToReview(
            subject: CorrectionSubject.property,
            name: 'etiqueta',
            value: 'Cuento',
            options: ['Cuento', 'Novela'],
          ),
          ThingToReview(
            subject: CorrectionSubject.mapIntro,
            name: 'introducción',
            value: 'Lo que dice.',
            canRemove: false,
          ),
          ThingToReview(
            subject: CorrectionSubject.property,
            name: 'propiedad «Páginas»',
            value: '320',
            options: ['320'],
            canFix: false,
          ),
        ],
      );

      expect(verdicts, const [
        ThingCorrection(index: 1, reason: 'Es una novela.', value: 'Novela'),
      ]);
      final opened = model.opened.single;
      expect(opened.maxOutputTokens, thingsReviewReplyTokens(4));
      expect(opened.instruction, contains('DATO <número>: corregir'));
      expect(opened.instruction, contains('No agregues cosas nuevas'));
      final sent = model.chats.single.received.single;
      expect(sent, startsWith('Elemento: Rayuela\nUna novela de Cortázar.\n'));
      expect(
        sent,
        contains(
          'DATO 1: vínculo con «Cortázar»\nTIPO: relacionado\n'
          'FRASE: El autor.\nCONTEXTO: Un escritor argentino.\n'
          'OPCIONES: relacionado, cita\n',
        ),
      );
      expect(
        sent,
        contains('DATO 2: etiqueta\nVALOR: Cuento\nOPCIONES: Cuento, Novela\n'),
      );
      expect(sent, contains('DATO 3: introducción (no se saca)\n'));
      // Lo que no se corrige no muestra opciones.
      expect(
        sent,
        contains('DATO 4: propiedad «Páginas» (no se corrige)\nVALOR: 320\n'),
      );
      expect(sent, isNot(contains('OPCIONES: 320')));
      expect(model.chats.single.closed, isTrue);
    },
  );

  test('sin nada que revisar, no le pide nada al modelo (F33)', () async {
    expect(
      await gemma.reviewThings(
        itemTitle: 'x',
        itemExcerpt: '',
        things: const [],
      ),
      isEmpty,
    );
    expect(model.opened, isEmpty);
  });

  test('sin tarjetas, la revisión no le pide nada al modelo (F33)', () async {
    expect(await gemma.reviewFlashcards(const []), isEmpty);
    expect(model.opened, isEmpty);
  });

  test('los cuadernos sugeridos: le da cada tema con sus títulos de ejemplo '
      'y lee una línea CUADERNO por tema (F30)', () async {
    model = FakeInferenceModel(
      newChat: (n) => FakeInferenceChat(
        id: n,
        answer: (_, _) => [
          'CUADERNO: 1 | La república romana | Fuentes sobre su política\n',
          'CUADERNO: 2 | Filosofía griega |',
        ],
      ),
    );

    final names = await gemma.nameNotebooks([
      (topic: 'Roma', itemCount: 12, titles: ['El foro', 'El Senado']),
      (topic: 'Filosofía', itemCount: 4, titles: <String>[]),
    ]);

    expect(names[0]?.name, 'La república romana');
    expect(names[0]?.description, 'Fuentes sobre su política');
    expect(names[1]?.name, 'Filosofía griega');
    expect(names[1]?.description, isNull);
    expect(model.opened.single.maxOutputTokens, notebookNamesReplyTokens(2));
    final sent = model.chats.single.received.single;
    expect(sent, startsWith('Temas:\n1. Roma (12 elementos)'));
    expect(sent, contains('Ejemplos: El foro; El Senado'));
    expect(sent, contains('2. Filosofía (4 elementos)'));
    expect(model.chats.single.closed, isTrue);
  });

  test('si la persona pide el modelo mientras la cola escribe, la cola se '
      'corta y repite su paso entero despuÃ©s (F30)', () async {
    model = FakeInferenceModel(
      newChat: (n) => FakeInferenceChat(
        id: n,
        gated: n == 1,
        answer: (_, prompt) => prompt.contains('Temas:')
            ? ['TEMA: ', '2 | alta']
            : ['Un resumen.'],
      ),
    );
    final background = gemma.background.chooseSpace(
      itemTitle: 'El Senado',
      excerpt: 'El Senado romanoâ€¦',
      spaces: ['Grecia', 'Roma'],
    );
    while (model.chats.isEmpty || !model.chats.first.generating) {
      await pumpEventQueue();
    }
    model.chats.first.releasePiece();
    await pumpEventQueue();

    final summary = await gemma.summarize(content: 'Textoâ€¦');

    expect(summary, 'Un resumen.');
    expect(model.chats.first.stopRequests, 1);
    final choice = await background;
    expect(choice?.index, 1);
    // La cortada, la de la persona y la repetida, en ese orden.
    expect(model.chats, hasLength(3));
    expect(model.opened[1].maxOutputTokens, kSummaryReplyTokens);
    expect(model.opened[2].maxOutputTokens, kChoiceReplyTokens);
    expect(model.chats.every((c) => c.closed), isTrue);
  });

  test('una foto en la charla llega al modelo, cargado para mirarla '
      '(F30)', () async {
    final conversation = await gemma.startConversation();
    await conversation.send('Hola').last;
    expect(loads.map((l) => l.vision), [false]);

    // El modelo de mentira es el mismo objeto: lo que importa es que se pide
    // de nuevo con la parte de las fotos y que la foto llega.
    model = FakeInferenceModel();
    await conversation
        .send(
          '¿Qué es?',
          images: [
            Uint8List.fromList(const [1]),
          ],
        )
        .last;

    expect(loads.map((l) => l.vision), [false, true]);
    expect(model.chats.single.imagesReceived, 1);
    await conversation.close();
  });
}
