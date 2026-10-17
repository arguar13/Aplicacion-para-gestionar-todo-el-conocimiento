import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_reviewer.dart';
import 'package:sinapsis/features/chat/data/services/language_model_tasks.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/model_backend.dart';

/// Un motor de mentira que anota cada intercambio que abre y contesta
/// siempre lo mismo.
class _Backend implements ModelBackend {
  _Backend(this.name);

  final String name;
  final String reply = 'TARJETA 1: bien';
  int opened = 0;
  _Backend? background;

  /// Si está, cada respuesta espera a que se complete o a que la corten.
  Completer<void>? hold;

  @override
  ModelBackend get forBackground => background ?? this;

  @override
  int get contextTokens => 1000000;

  @override
  bool get isWarm => true;

  @override
  Future<void> warmUp() async {}

  @override
  Future<ModelExchange> openExchange({
    required String instruction,
    required int maxOutputTokens,
  }) async {
    opened++;
    return _Exchange(reply, hold?.future);
  }

  @override
  Future<ModelConversation> openConversation({
    required String instruction,
    required int maxOutputTokens,
  }) => throw UnimplementedError();
}

class _Exchange implements ModelExchange {
  _Exchange(this._reply, this._hold);

  final String _reply;
  final Future<void>? _hold;
  final _stopped = Completer<void>();

  @override
  Future<int> countTokens(String text) async => text.length;

  @override
  Future<String> reply(
    String text, {
    LanguageModelReplyKind kind = LanguageModelReplyKind.task,
  }) async {
    if (_hold case final hold?) {
      await Future.any([hold, _stopped.future]);
    }
    return _reply;
  }

  @override
  Future<void> stop() async {
    if (!_stopped.isCompleted) _stopped.complete();
  }

  @override
  Future<void> close() async {}
}

/// Lo que la persona pidió y corre de fondo (F33): con el turno de la cola,
/// pero gastando como la persona.
void main() {
  const cards = [
    FlashcardToReview(front: '¿Qué?', back: 'Eso.', passage: 'Eso.'),
  ];

  late _Backend person;
  late _Backend background;
  late LanguageModelGate gate;
  late LanguageModelTasks tasks;

  setUp(() {
    person = _Backend('persona');
    background = _Backend('fondo');
    person.background = background;
    gate = LanguageModelGate();
    tasks = LanguageModelTasks(gate: gate, backend: person);
  });

  test(
    'gasta con el motor de la persona, no con el de la IA de fondo',
    () async {
      await tasks.requestedInBackground.reviewFlashcards(cards);

      expect(person.opened, 1);
      expect(background.opened, 0);
    },
  );

  test('la IA de fondo de siempre sigue gastando con el suyo', () async {
    await tasks.background.reviewFlashcards(cards);

    expect(background.opened, 1);
    expect(person.opened, 0);
  });

  test('espera a que la persona suelte el modelo, como la cola', () async {
    final holding = Completer<void>();
    final mine = gate.runForUser(() => holding.future);

    final review = tasks.requestedInBackground.reviewFlashcards(cards);
    await pumpEventQueue();
    expect(person.opened, 0);

    holding.complete();
    await mine;
    await review;
    expect(person.opened, 1);
  });

  test('si la persona pide el modelo a mitad, le cede el paso y repite '
      'después', () async {
    person.hold = Completer<void>();
    final review = tasks.requestedInBackground.reviewFlashcards(cards);
    await pumpEventQueue();
    expect(person.opened, 1);

    var personDone = false;
    final mine = gate.runForUser(() async => personDone = true);
    await pumpEventQueue();

    // Lo de la persona no esperó a la revisión: la cortó.
    expect(personDone, isTrue);
    await mine;
    person.hold!.complete();
    await review;
    expect(person.opened, 2);
  });
}
