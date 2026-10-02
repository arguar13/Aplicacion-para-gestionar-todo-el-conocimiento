import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/audio/audio_focus.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_audio_focus.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';

/// Un lector de mentira que solo sabe sonar y pausarse.
class _FakeReadAloud extends ReadAloudController {
  int pauses = 0;

  @override
  ReadAloudState build() => const ReadAloudState();

  @override
  Future<void> play() async => state = state.copyWith(playing: true);

  @override
  Future<void> pause() async {
    pauses++;
    state = state.copyWith(playing: false);
  }
}

void main() {
  group('uno a la vez con el audio (F25)', () {
    late _FakeReadAloud reader;
    late ProviderContainer container;

    setUp(() {
      reader = _FakeReadAloud();
      container = ProviderContainer(
        overrides: [readAloudControllerProvider.overrideWith(() => reader)],
      );
      addTearDown(container.dispose);
      container.listen(readAloudAudioFocusProvider, (_, _) {});
    });

    test('empezar a leer toma el foco', () async {
      await reader.play();

      expect(container.read(audioFocusProvider), readAloudFocusOwner);
    });

    test('un audio que empieza a sonar pausa al lector', () async {
      await reader.play();

      container.read(audioFocusProvider.notifier).claim(Object());

      expect(reader.pauses, 1);
      expect(container.read(readAloudControllerProvider).playing, isFalse);
    });

    test('con el lector en pausa, un audio no le pide nada', () {
      container.read(audioFocusProvider.notifier).claim(Object());

      expect(reader.pauses, 0);
    });

    test('volver a tomar el foco siendo de uno mismo no avisa nada', () {
      final audio = Object();
      final focus = container.read(audioFocusProvider.notifier)..claim(audio);
      var notices = 0;
      container.listen(audioFocusProvider, (_, _) => notices++);

      focus.claim(audio);

      expect(notices, 0);
    });
  });
}
