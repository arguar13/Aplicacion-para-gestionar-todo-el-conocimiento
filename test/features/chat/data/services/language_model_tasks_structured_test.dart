import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/language_model_tasks.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/model_backend.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Lo que se le mandó al motor en un intercambio.
typedef _Sent = ({String instruction, String prompt, int maxOutputTokens});

/// Un motor de mentira que contesta, en orden, lo de `replies` —o lo que
/// arme [answer] con el pedido— y anota cada pedido.
class _Backend implements ModelBackend {
  _Backend({
    List<String> replies = const [],
    this.answer,
    this.contextTokens = 100000,
  }) : _replies = [...replies];

  final List<String> _replies;
  final String Function(_Sent sent)? answer;
  final sent = <_Sent>[];
  _Backend? background;

  /// Si está, cada respuesta espera a que se complete o a que la corten.
  Completer<void>? hold;
  int stops = 0;

  @override
  final int contextTokens;

  @override
  ModelBackend get forBackground => background ?? this;

  @override
  bool get isWarm => true;

  @override
  Future<void> warmUp() async {}

  @override
  Future<ModelExchange> openExchange({
    required String instruction,
    required int maxOutputTokens,
  }) async => _Exchange(this, instruction, maxOutputTokens);

  @override
  Future<ModelConversation> openConversation({
    required String instruction,
    required int maxOutputTokens,
  }) => throw UnimplementedError();
}

class _Exchange implements ModelExchange {
  _Exchange(this._backend, this._instruction, this._maxOutputTokens);

  final _Backend _backend;
  final String _instruction;
  final int _maxOutputTokens;
  final _stopped = Completer<void>();

  @override
  Future<int> countTokens(String text) async => (text.length / 3).ceil();

  @override
  Future<String> reply(
    String text, {
    LanguageModelReplyKind kind = LanguageModelReplyKind.task,
  }) async {
    final sent = (
      instruction: _instruction,
      prompt: text,
      maxOutputTokens: _maxOutputTokens,
    );
    _backend.sent.add(sent);
    if (_backend.hold case final hold?) {
      await Future.any([hold.future, _stopped.future]);
      if (_stopped.isCompleted) return '';
    }
    final answer = _backend.answer;
    if (answer != null) return answer(sent);
    return _backend._replies.removeAt(0);
  }

  @override
  Future<void> stop() async {
    _backend.stops++;
    if (!_stopped.isCompleted) _stopped.complete();
  }

  @override
  Future<void> close() async {}
}

/// Un mapa con su `titulo` y sus `ideas`: lo que «pide» la prueba.
({String titulo, List<String> ideas}) _parse(Object? json) {
  if (json is! Map<String, Object?>) {
    throw const FormatException('No es un objeto.');
  }
  final titulo = json['titulo'];
  final ideas = json['ideas'];
  if (titulo is! String || titulo.trim().isEmpty) {
    throw const FormatException('Falta «titulo».');
  }
  if (ideas is! List || ideas.any((i) => i is! String)) {
    throw const FormatException('«ideas» tiene que ser una lista de textos.');
  }
  return (titulo: titulo, ideas: ideas.cast<String>());
}

void main() {
  const budget = CreationBudget(
    contextTokens: 100000,
    reservedOutputTokens: 1000,
  );

  const single = CreationMaterial(
    mode: CreationMaterialMode.fullText,
    text: '## Éxodo\n\nMoisés guía al pueblo.',
    sources: [
      CreationMaterialSource(documentId: 'doc', title: 'Éxodo', chars: 22),
    ],
  );

  CreationMaterial byParts(int count) => CreationMaterial(
    mode: CreationMaterialMode.byParts,
    parts: [
      for (var i = 0; i < count; i++)
        CreationMaterialPart(
          documentId: 'doc',
          text: '## Éxodo\n\nParte número $i.',
          index: i,
        ),
    ],
    totalParts: count,
    partsBase: CreationPartsBase.fullText,
    sources: const [
      CreationMaterialSource(documentId: 'doc', title: 'Éxodo', chars: 100),
    ],
  );

  StructuredRequest<({String titulo, List<String> ideas})> request(
    CreationMaterial material, {
    CancellationSignal? cancellation,
    void Function(double, CreationStep)? onProgress,
    String languageCode = 'es',
    String? guidance,
    CreationBudget requestBudget = budget,
  }) => StructuredRequest(
    task: 'armar un mapa de las ideas del material',
    schema: '{"titulo": "…", "ideas": ["…"]}',
    material: material,
    budget: requestBudget,
    maxOutputTokens: 800,
    partMaxOutputTokens: 300,
    parse: _parse,
    languageCode: languageCode,
    guidance: guidance,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  const good = '{"titulo": "Éxodo", "ideas": ["Moisés", "El mar"]}';

  LanguageModelTasks tasksOn(_Backend backend) =>
      LanguageModelTasks(gate: LanguageModelGate(), backend: backend);

  group('de una vez', () {
    test(
      'le pide la tarea, el idioma y el esquema, y lee lo que contesta',
      () async {
        final backend = _Backend(replies: [good]);

        final result = await tasksOn(backend).writeStructured(
          request(single, languageCode: 'en', guidance: 'centrate en Moisés'),
        );

        expect(result.titulo, 'Éxodo');
        expect(result.ideas, ['Moisés', 'El mar']);
        final sent = backend.sent.single;
        expect(sent.instruction, contains('armar un mapa de las ideas'));
        expect(sent.instruction, contains('inglés'));
        expect(sent.instruction, contains('{"titulo": "…", "ideas": ["…"]}'));
        expect(sent.instruction, contains('«centrate en Moisés»'));
        expect(sent.instruction, contains('SOLO con un JSON'));
        expect(sent.prompt, contains('Moisés guía al pueblo.'));
        expect(sent.maxOutputTokens, 800);
      },
    );

    test('con un bloque de código y una frase antes, igual se lee', () async {
      final backend = _Backend(
        replies: [
          '¡Claro! Acá va:\n```json\n$good\n```\nCualquier cosa, avisá.',
        ],
      );

      final result = await tasksOn(backend).writeStructured(request(single));

      expect(result.titulo, 'Éxodo');
      expect(backend.sent, hasLength(1), reason: 'sin pedir que corrija');
    });

    test('si no se puede leer, le devuelve su respuesta con el motivo y lee '
        'la corregida', () async {
      final backend = _Backend(replies: ['{"titulo": "Éxodo"}', good]);

      final result = await tasksOn(backend).writeStructured(request(single));

      expect(result.ideas, ['Moisés', 'El mar']);
      expect(backend.sent, hasLength(2));
      final repair = backend.sent.last;
      expect(repair.prompt, contains('no se pudo leer'));
      expect(repair.prompt, contains('«ideas» tiene que ser una lista'));
      expect(repair.prompt, contains('{"titulo": "Éxodo"}'));
      expect(repair.instruction, backend.sent.first.instruction);
    });

    test(
      'si tampoco se puede leer la corregida, lo dice: una sola vez',
      () async {
        final backend = _Backend(replies: ['No sé.', 'Sigo sin saber.']);

        await expectLater(
          tasksOn(backend).writeStructured(request(single)),
          throwsA(
            isA<UnreadableStructuredReply>().having(
              (e) => e.reason,
              'motivo',
              contains('ningún JSON'),
            ),
          ),
        );
        expect(backend.sent, hasLength(2));
      },
    );

    test('lo que no entra en la ventana se achica, nunca se pasa', () async {
      final big = CreationMaterial(
        mode: CreationMaterialMode.fullText,
        text: 'palabra ' * 3000,
        sources: const [
          CreationMaterialSource(documentId: 'doc', title: 'T', chars: 24000),
        ],
      );
      final backend = _Backend(replies: [good], contextTokens: 3000);

      await tasksOn(backend).writeStructured(request(big));

      final sent = backend.sent.single;
      final tokens =
          (sent.prompt.length / 3).ceil() +
          (sent.instruction.length / 3).ceil() +
          sent.maxOutputTokens;
      expect(tokens, lessThanOrEqualTo(3000));
      expect(sent.prompt.length, lessThan(24000));
    });

    test('el avance va de 0 a 1', () async {
      final progress = <double>[];
      await tasksOn(
        _Backend(replies: [good]),
      ).writeStructured(request(single, onProgress: (p, _) => progress.add(p)));
      expect(progress, [0, 1]);
    });
  });

  group('por partes', () {
    test('un borrador por parte y un último paso que los une', () async {
      final steps = <CreationStep>[];
      final progress = <double>[];
      final backend = _Backend(
        answer: (sent) {
          final match = RegExp(r'Parte número (\d+)').firstMatch(sent.prompt);
          if (match != null) {
            return jsonEncode({
              'titulo': 'Borrador ${match[1]}',
              'ideas': ['idea ${match[1]}'],
            });
          }
          return '{"titulo": "Éxodo entero", "ideas": ["todas"]}';
        },
      );

      final result = await tasksOn(backend).writeStructured(
        request(
          byParts(3),
          onProgress: (p, step) {
            progress.add(p);
            steps.add(step);
          },
        ),
      );

      expect(result.titulo, 'Éxodo entero');
      expect(backend.sent, hasLength(4));
      for (var i = 0; i < 3; i++) {
        final part = backend.sent[i];
        expect(part.prompt, contains('Parte ${i + 1} de 3'));
        expect(part.instruction, contains('borrador parcial'));
        expect(part.maxOutputTokens, 300);
      }
      final merge = backend.sent.last;
      expect(merge.instruction, contains('unir en uno solo'));
      expect(merge.prompt, contains('"Borrador 0"'));
      expect(merge.prompt, contains('"Borrador 2"'));
      expect(merge.maxOutputTokens, 800);
      expect(steps.first, CreationStep.readingParts);
      expect(steps.last, CreationStep.joining);
      expect(progress.last, 1);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test(
      'borradores que juntos no entran se unen de a grupos, hasta uno',
      () async {
        var merges = 0;
        final backend = _Backend(
          answer: (sent) {
            if (sent.prompt.startsWith('Borradores')) {
              merges++;
              return jsonEncode({
                'titulo': 'Unión $merges',
                'ideas': ['x' * 60],
              });
            }
            return jsonEncode({
              'titulo': 'Parte',
              'ideas': ['y' * 60],
            });
          },
        );
        // Entran unos tres borradores por grupo.
        const tight = CreationBudget(
          contextTokens: 1000 + 600 + 90,
          reservedOutputTokens: 1000,
        );

        final result = await tasksOn(
          backend,
        ).writeStructured(request(byParts(8), requestBudget: tight));

        expect(merges, greaterThan(1), reason: 'más de una vuelta de unir');
        expect(result.titulo, 'Unión $merges');
      },
    );

    test('una sola parte: su borrador ya es el final', () async {
      final backend = _Backend(replies: [good]);

      final result = await tasksOn(
        backend,
      ).writeStructured(request(byParts(1)));

      expect(result.titulo, 'Éxodo');
      expect(backend.sent, hasLength(1));
    });

    test('un borrador roto se corrige como cualquier respuesta', () async {
      final backend = _Backend(
        replies: ['{"titulo": "A", "ideas": ["a"]}', 'roto', good, good],
      );

      final result = await tasksOn(
        backend,
      ).writeStructured(request(byParts(2)));

      expect(result.titulo, 'Éxodo');
      expect(backend.sent, hasLength(4));
      expect(backend.sent[2].prompt, contains('no se pudo leer'));
    });
  });

  group('cancelar', () {
    test('ya cancelada no le pide nada al motor', () async {
      final backend = _Backend(replies: [good]);
      final signal = CancellationSignal()..cancel();

      await expectLater(
        tasksOn(backend).writeStructured(request(single, cancellation: signal)),
        throwsA(isA<CreationCancelledException>()),
      );
      expect(backend.sent, isEmpty);
    });

    test(
      'a mitad, corta lo que el motor escribe y no sigue con las partes',
      () async {
        final backend = _Backend(replies: [good, good, good])
          ..hold = Completer<void>();
        final signal = CancellationSignal();

        final writing = tasksOn(
          backend,
        ).writeStructured(request(byParts(3), cancellation: signal));
        await pumpEventQueue();
        expect(backend.sent, hasLength(1));

        signal.cancel();
        await expectLater(writing, throwsA(isA<CreationCancelledException>()));
        expect(backend.stops, 1);
        expect(backend.sent, hasLength(1));
      },
    );
  });

  group('el turno (F27)', () {
    test('«más tarde» va con el motor de la IA de fondo; «ahora», con el de la '
        'persona', () async {
      final person = _Backend(replies: [good]);
      final background = _Backend(replies: [good]);
      person.background = background;
      final tasks = tasksOn(person);

      await tasks.background.writeStructured(request(single));
      expect(background.sent, hasLength(1));
      expect(person.sent, isEmpty);

      await tasks.writeStructured(request(single));
      expect(person.sent, hasLength(1));
    });

    test('de fondo espera a que la persona suelte el modelo', () async {
      final backend = _Backend(replies: [good]);
      final gate = LanguageModelGate();
      final tasks = LanguageModelTasks(gate: gate, backend: backend);
      final holding = Completer<void>();
      final mine = gate.runForUser(() => holding.future);

      final writing = tasks.background.writeStructured(request(single));
      await pumpEventQueue();
      expect(backend.sent, isEmpty);

      holding.complete();
      await mine;
      await writing;
      expect(backend.sent, hasLength(1));
    });

    test('la ventana es la del motor', () {
      expect(tasksOn(_Backend(contextTokens: 2048)).contextTokens, 2048);
    });
  });
}
