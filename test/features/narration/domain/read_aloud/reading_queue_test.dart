import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/reading_queue.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/sleep_timer.dart';

QueuedReading _reading(String id, {ReadScope scope = ReadScope.all}) =>
    QueuedReading(
      ReadableDocument(id: id, title: id, segments: const []),
      scope: scope,
    );

List<String> _ids(ReadingQueue queue) => [
  for (final reading in queue.upcoming) reading.document.id,
];

void main() {
  final a = _reading('a');
  final b = _reading('b');
  final c = _reading('c');
  final now = _reading('ahora');

  group('la cola', () {
    test('suma al final, sin repetir lo que ya está', () {
      final queue = const ReadingQueue().add(a).add(b).add(_reading('a'));

      expect(_ids(queue), ['a', 'b']);
    });

    test('la misma lectura con otra parte es otra', () {
      final queue = const ReadingQueue()
          .add(a)
          .add(_reading('a', scope: ReadScope.summary));

      expect(queue.upcoming, hasLength(2));
    });

    test('saca, limpia y conserva la repetición', () {
      final queue = const ReadingQueue(
        repeat: ReadAloudRepeat.all,
      ).add(a).add(b).add(c);

      expect(_ids(queue.removeAt(1)), ['a', 'c']);
      expect(queue.removeAt(7), same(queue));
      expect(queue.clear().isEmpty, isTrue);
      expect(queue.clear().repeat, ReadAloudRepeat.all);
    });

    test('reordena a la posición en que queda', () {
      final queue = const ReadingQueue().add(a).add(b).add(c);

      expect(_ids(queue.move(0, 1)), ['b', 'a', 'c']);
      expect(_ids(queue.move(0, 2)), ['b', 'c', 'a']);
      expect(_ids(queue.move(2, 0)), ['c', 'a', 'b']);
      expect(_ids(queue.move(0, 9)), ['b', 'c', 'a']);
      expect(queue.move(1, 1), same(queue));
      expect(queue.move(5, 0), same(queue));
    });

    test('no se puede cambiar desde afuera', () {
      final queue = const ReadingQueue().add(a);

      expect(() => queue.upcoming.add(b), throwsUnsupportedError);
    });
  });

  group('al terminar', () {
    test('sin repetir, sigue la cola; sin cola, nada', () {
      final queue = const ReadingQueue().add(a).add(b);

      final after = queue.afterFinishing(now);
      expect(after.next, a);
      expect(_ids(after.rest), ['b']);

      expect(const ReadingQueue().afterFinishing(now).next, isNull);
    });

    test('repitiendo la cola, lo que terminó vuelve al final', () {
      final queue = const ReadingQueue(
        repeat: ReadAloudRepeat.all,
      ).add(a).add(b);

      final after = queue.afterFinishing(now);
      expect(after.next, a);
      expect(_ids(after.rest), ['b', 'ahora']);
      expect(after.rest.repeat, ReadAloudRepeat.all);
    });

    test('repitiendo la cola sin nada en ella, vuelve a sonar lo mismo', () {
      const queue = ReadingQueue(repeat: ReadAloudRepeat.all);

      final after = queue.afterFinishing(now);
      expect(after.next, now);
      expect(after.rest.isEmpty, isTrue);
    });

    test('repitiendo lo que suena, vuelve a empezar y la cola espera', () {
      final queue = const ReadingQueue(repeat: ReadAloudRepeat.one).add(a);

      final after = queue.afterFinishing(now);
      expect(after.next, now);
      expect(after.rest, queue);
    });

    test('«siguiente» pasa a la cola aunque se repita lo que suena', () {
      final queue = const ReadingQueue(
        repeat: ReadAloudRepeat.one,
      ).add(a).add(b);

      final skipped = queue.skipFrom(now);
      expect(skipped.next, a);
      expect(_ids(skipped.rest), ['b']);
      expect(
        const ReadingQueue(repeat: ReadAloudRepeat.one).skipFrom(now).next,
        isNull,
      );
    });
  });

  test('⟲ pasa por no repetir, la cola y lo que suena', () {
    expect(ReadAloudRepeat.off.next, ReadAloudRepeat.all);
    expect(ReadAloudRepeat.all.next, ReadAloudRepeat.one);
    expect(ReadAloudRepeat.one.next, ReadAloudRepeat.off);
  });

  group('el Temporizador para dormir', () {
    const start = Duration(minutes: 3);

    test('cuenta desde que se elige', () {
      final timer = SleepTimer.start(SleepTimerChoice.minutes15, now: start);

      expect(timer.deadline, start + const Duration(minutes: 15));
      expect(timer.atEndOfReading, isFalse);
      expect(
        timer.remaining(start + const Duration(minutes: 5)),
        const Duration(minutes: 10),
      );
    });

    test('dice los minutos redondeados para arriba, y nunca menos de '
        'nada', () {
      final timer = SleepTimer.start(SleepTimerChoice.minutes30, now: start);

      expect(timer.minutesLeft(start), 30);
      expect(timer.minutesLeft(start + const Duration(minutes: 29)), 1);
      expect(
        timer.minutesLeft(start + const Duration(minutes: 29, seconds: 30)),
        1,
      );
      expect(timer.minutesLeft(start + const Duration(minutes: 30)), 0);
      expect(timer.remaining(start + const Duration(hours: 2)), Duration.zero);
    });

    test('las cuatro duraciones', () {
      expect(SleepTimerChoice.minutes45.after, const Duration(minutes: 45));
      expect(SleepTimerChoice.minutes60.after, const Duration(minutes: 60));
    });

    test('al terminar lo que suena no tiene hora', () {
      final timer = SleepTimer.start(SleepTimerChoice.endOfReading, now: start);

      expect(timer.atEndOfReading, isTrue);
      expect(timer.remaining(start), isNull);
      expect(timer.minutesLeft(start), isNull);
    });
  });
}
