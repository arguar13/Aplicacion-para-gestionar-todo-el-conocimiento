import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/capture/presentation/providers/shared_content_controller.dart';

import '../../../../support/fake_shared_content_listener.dart';

void main() {
  late FakeSharedContentListener listener;

  ProviderContainer buildContainer({List<CaptureRequest> initial = const []}) {
    listener = FakeSharedContentListener(initial: initial);
    final container = ProviderContainer(
      overrides: [sharedContentListenerProvider.overrideWithValue(listener)],
    );
    addTearDown(container.dispose);
    // Los providers de Riverpod son perezosos: sin esta lectura, el
    // controller ni se construye, y `initial()` nunca llega a pedirse.
    container.read(sharedContentControllerProvider);
    return container;
  }

  /// Dos cosas que este controller hace de forma asincrónica —pedir lo
  /// inicial y sumar lo que llegue por el stream— necesitan que pase al
  /// menos un microtask antes de que el estado las refleje.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('sin nada compartido, la cola arranca vacía', () async {
    final container = buildContainer();
    await settle();

    expect(container.read(sharedContentControllerProvider), isEmpty);
  });

  test('lo que trajo el arranque de la app queda en la cola', () async {
    const request = CaptureRequest.text(rawInput: 'https://ejemplo.org');
    final container = buildContainer(initial: [request]);
    await settle();

    expect(container.read(sharedContentControllerProvider), [request]);
  });

  test('lo que llega con la app ya abierta se suma, sin perder lo que había '
      'del arranque', () async {
    const fromLaunch = CaptureRequest.text(rawInput: 'del arranque');
    const fromStream = CaptureRequest.text(rawInput: 'ya con la app abierta');
    final container = buildContainer(initial: [fromLaunch]);
    await settle();

    listener.add([fromStream]);
    await settle();

    expect(container.read(sharedContentControllerProvider), [
      fromLaunch,
      fromStream,
    ]);
  });

  group('takeNext()', () {
    test('sin nada pendiente, devuelve null', () async {
      final container = buildContainer();
      await settle();

      final notifier = container.read(sharedContentControllerProvider.notifier);
      expect(notifier.takeNext(), isNull);
    });

    test('saca de la cola en el orden en que llegó, no al revés', () async {
      const first = CaptureRequest.text(rawInput: 'primero');
      const second = CaptureRequest.text(rawInput: 'segundo');
      final container = buildContainer(initial: [first, second]);
      await settle();

      final notifier = container.read(sharedContentControllerProvider.notifier);

      expect(notifier.takeNext(), first);
      expect(container.read(sharedContentControllerProvider), [second]);
    });

    test('lo ya consumido no se vuelve a ofrecer', () async {
      const request = CaptureRequest.text(rawInput: 'algo');
      final container = buildContainer(initial: [request]);
      await settle();

      final notifier = container.read(sharedContentControllerProvider.notifier);

      expect(notifier.takeNext(), request);
      expect(notifier.takeNext(), isNull);
    });
  });
}
