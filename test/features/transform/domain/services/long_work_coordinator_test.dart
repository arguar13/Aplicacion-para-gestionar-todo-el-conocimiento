import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// Lo que se le pidió a la plataforma, en orden.
class _FakePlatform implements LongWorkPlatform {
  final calls = <String>[];

  @override
  Future<void> show(LongWorkNotice notice) async =>
      calls.add('mostrar ${notice.owner.name} ${notice.done}/${notice.total}');

  @override
  Future<void> stop() async => calls.add('apagar');
}

/// El servicio en primer plano, compartido por varios dueños (F21, F27),
/// contra una plataforma de mentira. Con `testWidgets` por el reloj falso: el
/// margen para soltar se prueba sin esperarlo de verdad.
void main() {
  late _FakePlatform platform;
  late LongWorkCoordinator coordinator;
  late LongWorkKeeper processing;
  late LongWorkKeeper ai;

  setUp(() {
    platform = _FakePlatform();
    // Suelta a los 15 segundos, el valor de la app.
    coordinator = LongWorkCoordinator(platform: platform);
    processing = coordinator.keeperFor(LongWorkOwner.processing);
    ai = coordinator.keeperFor(LongWorkOwner.aiOrganize);
  });

  testWidgets('solo avisa lo que cambia: otro porcentaje, no cada página', (
    tester,
  ) async {
    processing
      ..working(done: 1, total: 400)
      ..working(done: 2, total: 400)
      ..working(done: 3, total: 400)
      ..working(done: 4, total: 400);
    await tester.pump();

    expect(platform.calls, [
      'mostrar processing 1/400',
      'mostrar processing 4/400',
    ]);
  });

  testWidgets('soltar espera un momento: si en ese momento empieza otro '
      'trabajo largo, el servicio sigue', (tester) async {
    processing.working(done: 10, total: 10);
    await tester.pump();

    processing.idle();
    await tester.pump(const Duration(seconds: 5));
    processing.working(done: 0, total: 50);
    await tester.pump(const Duration(seconds: 30));

    expect(platform.calls, [
      'mostrar processing 10/10',
      'mostrar processing 0/50',
    ]);
  });

  testWidgets('pasado el momento, se suelta una sola vez', (tester) async {
    processing.working(done: 0, total: 0);
    await tester.pump();

    processing
      ..idle()
      ..idle();
    await tester.pump(const Duration(seconds: 16));

    expect(platform.calls, ['mostrar processing 0/0', 'apagar']);
  });

  testWidgets('sin trabajo previo, soltar no le habla a la plataforma', (
    tester,
  ) async {
    processing.idle();
    ai.idle();
    await tester.pump(const Duration(seconds: 16));

    expect(platform.calls, isEmpty);
  });

  group('con dos dueños (F27)', () {
    testWidgets('si suelta uno, el servicio sigue con el otro y dice lo '
        'suyo', (tester) async {
      ai.working(done: 3, total: 120);
      await tester.pump();
      processing.working(done: 1, total: 4);
      await tester.pump();

      // El procesamiento se ve antes: es lo que la persona acaba de pedir.
      ai.working(done: 4, total: 120);
      await tester.pump();
      expect(coordinator.shown?.owner, LongWorkOwner.processing);

      processing.idle();
      await tester.pump(const Duration(minutes: 1));

      expect(platform.calls, [
        'mostrar aiOrganize 3/120',
        'mostrar processing 1/4',
        'mostrar aiOrganize 4/120',
      ]);
      expect(coordinator.shown?.owner, LongWorkOwner.aiOrganize);
    });

    testWidgets('se apaga recién cuando sueltan los dos', (tester) async {
      processing.working(done: 0, total: 0);
      ai.working(done: 0, total: 10);
      await tester.pump();

      ai.idle();
      await tester.pump(const Duration(minutes: 1));
      expect(platform.calls, isNot(contains('apagar')));

      processing.idle();
      await tester.pump(const Duration(seconds: 16));
      expect(platform.calls.last, 'apagar');
      expect(coordinator.shown, isNull);
    });

    testWidgets('el avance de la IA, en elementos, también se avisa solo '
        'cuando cambia el porcentaje', (tester) async {
      ai
        ..working(done: 0, total: 1000)
        ..working(done: 1, total: 1000)
        ..working(done: 10, total: 1000);
      await tester.pump();

      expect(platform.calls, [
        'mostrar aiOrganize 0/1000',
        'mostrar aiOrganize 10/1000',
      ]);
    });
  });
}
