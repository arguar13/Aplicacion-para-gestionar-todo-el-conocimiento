import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// Lo que se le pidió a la plataforma, en orden.
class _FakePlatform implements LongWorkPlatform {
  final calls = <String>[];
  final notices = <LongWorkNotice>[];

  /// Android cortando el servicio por su cuenta.
  final systemStops = StreamController<void>.broadcast();

  @override
  Future<void> show(LongWorkNotice notice) async {
    notices.add(notice);
    calls.add('mostrar ${notice.owner.name} ${notice.done}/${notice.total}');
  }

  @override
  Future<void> stop() async => calls.add('apagar');

  @override
  Stream<void> get stoppedBySystem => systemStops.stream;
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

  testWidgets('la biblioteca de ejemplo va última: mientras se procesa lo '
      'que carga, se ve el procesamiento, y después ella', (tester) async {
    final sample = coordinator.keeperFor(LongWorkOwner.sampleLibrary)
      ..working(done: 2, total: 80);
    await tester.pump();
    processing.working(done: 1, total: 4);
    await tester.pump();
    expect(coordinator.shown?.owner, LongWorkOwner.processing);

    processing.idle();
    await tester.pump();
    expect(coordinator.shown?.owner, LongWorkOwner.sampleLibrary);

    sample.idle();
    await tester.pump(const Duration(seconds: 16));
    expect(platform.calls, [
      'mostrar sampleLibrary 2/80',
      'mostrar processing 1/4',
      'mostrar sampleLibrary 2/80',
      'apagar',
    ]);
  });

  group('varios trabajos del mismo dueño', () {
    testWidgets('dos descargas a la vez: soltar una no apaga la de la '
        'otra', (tester) async {
      final language = coordinator.keeperFor(LongWorkOwner.modelDownload)
        ..working(done: 10, total: 100, detail: LongWorkDetail.languageModel);
      final relations = coordinator.keeperFor(LongWorkOwner.modelDownload)
        ..working(done: 1, total: 100, detail: LongWorkDetail.relationsModel);
      await tester.pump();
      // Se ve la que empezó antes.
      expect(coordinator.shown?.detail, LongWorkDetail.languageModel);

      language.idle();
      await tester.pump(const Duration(minutes: 1));

      expect(coordinator.shown?.detail, LongWorkDetail.relationsModel);
      expect(platform.calls, isNot(contains('apagar')));

      relations.idle();
      await tester.pump(const Duration(seconds: 16));
      expect(platform.calls.last, 'apagar');
    });
  });

  group('los tipos del servicio', () {
    testWidgets('corre con los tipos de todos los trabajos en curso, no solo '
        'del que se ve', (tester) async {
      processing.working(done: 1, total: 4, kind: LongWorkKind.mediaProcessing);
      coordinator
          .keeperFor(LongWorkOwner.modelDownload)
          .working(done: 0, total: 100);
      await tester.pump();

      expect(coordinator.shown?.owner, LongWorkOwner.processing);
      expect(coordinator.shown?.kinds, {
        LongWorkKind.mediaProcessing,
        LongWorkKind.dataSync,
      });
    });

    testWidgets('cambiar de clase de trabajo se avisa aunque el porcentaje '
        'sea el mismo', (tester) async {
      processing.working(done: 0, total: 0);
      await tester.pump();
      processing.working(done: 0, total: 0, kind: LongWorkKind.mediaProcessing);
      await tester.pump();

      expect(platform.notices.map((n) => n.kinds), [
        {LongWorkKind.dataSync},
        {LongWorkKind.mediaProcessing},
      ]);
    });
  });

  group('si Android corta el servicio (Android 15: el tope de horas)', () {
    testWidgets('no se le insiste desde segundo plano: lo que siga avanzando '
        'no le habla a la plataforma', (tester) async {
      processing.working(done: 1, total: 100);
      await tester.pump();

      platform.systemStops.add(null);
      await tester.pump();
      processing.working(done: 50, total: 100);
      await tester.pump(const Duration(minutes: 1));

      expect(platform.calls, ['mostrar processing 1/100']);
      expect(coordinator.shown, isNull);
    });

    testWidgets('al volver al frente, el servicio vuelve con lo que siga en '
        'curso', (tester) async {
      processing.working(done: 1, total: 100);
      await tester.pump();
      platform.systemStops.add(null);
      await tester.pump();
      processing.working(done: 50, total: 100);

      coordinator.appResumed();
      await tester.pump();

      expect(platform.calls, [
        'mostrar processing 1/100',
        'mostrar processing 50/100',
      ]);
    });

    testWidgets('si al volver ya no hay nada en curso, no se prende', (
      tester,
    ) async {
      processing.working(done: 1, total: 100);
      await tester.pump();
      platform.systemStops.add(null);
      await tester.pump();
      processing.idle();

      coordinator.appResumed();
      await tester.pump(const Duration(seconds: 16));

      expect(platform.calls, ['mostrar processing 1/100']);
    });

    testWidgets('volver al frente sin que Android haya cortado nada no repite '
        'el aviso', (tester) async {
      processing.working(done: 1, total: 100);
      await tester.pump();

      coordinator.appResumed();
      await tester.pump();

      expect(platform.calls, ['mostrar processing 1/100']);
    });
  });

  testWidgets('sin margen para soltar, se apaga en el acto', (tester) async {
    final quick = LongWorkCoordinator(
      platform: platform,
      releaseDelay: Duration.zero,
    );
    final keeper = quick.keeperFor(LongWorkOwner.processing)
      ..working(done: 1, total: 2);
    await tester.pump();

    keeper.idle();

    expect(platform.calls, ['mostrar processing 1/2', 'apagar']);
    expect(quick.shown, isNull);
  });
}
