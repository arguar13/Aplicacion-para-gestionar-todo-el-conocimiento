import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/config_providers.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/domain/usecases/load_sample_library_usecase.dart';
import 'package:sinapsis/features/dev_seed/presentation/providers/sample_library_providers.dart';
import 'package:sinapsis/features/dev_seed/presentation/providers/sample_library_state.dart';
import 'package:sinapsis/features/dev_seed/presentation/widgets/sample_library_tile.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/silent_logger.dart';
import '../dev_seed_fakes.dart';

/// Lo que se le pidió al servicio en primer plano.
class _RecordingKeeper implements LongWorkKeeper {
  final calls = <String>[];

  @override
  void working({required int done, required int total}) =>
      calls.add('$done/$total');

  @override
  void idle() => calls.add('libre');
}

const _web = SampleLink(
  id: 'web-roma',
  title: 'Imperio romano',
  why: 'Una página.',
  kind: SampleLinkKind.webArticle,
  url: 'https://es.wikipedia.org/wiki/Imperio_romano',
  approxBytes: 2 * 1024 * 1024,
);

const _pdf = SampleFile(
  id: 'pdf-laudato',
  title: "Laudato si'",
  why: 'Un PDF.',
  kind: SampleFileKind.pdf,
  url: 'https://ejemplo.org/laudato.pdf',
  fileName: 'laudato_si.pdf',
  approxBytes: 3 * 1024 * 1024,
);

const _audio = SampleFile(
  id: 'audio-apologia',
  title: 'Apología de Sócrates',
  why: 'Un audio.',
  kind: SampleFileKind.audio,
  url: 'https://archivo.org/apologia.mp3',
  fileName: 'apologia.mp3',
  approxBytes: 5 * 1024 * 1024,
);

void main() {
  final es = AppLocalizationsEs();
  late InMemorySampleLibraryLedger ledger;
  late FakeSampleFileDownloader downloader;
  late FakeCaptureItem capture;
  late _RecordingKeeper keeper;

  setUp(() {
    ledger = InMemorySampleLibraryLedger();
    downloader = FakeSampleFileDownloader();
    capture = FakeCaptureItem();
    keeper = _RecordingKeeper();
  });

  ProviderContainer container({
    List<SampleResource> resources = const [_web, _pdf, _audio],
    AppFlavor flavor = AppFlavor.dev,
  }) {
    final container = ProviderContainer(
      overrides: [
        appFlavorProvider.overrideWithValue(flavor),
        appLoggerProvider.overrideWithValue(const SilentLogger()),
        sampleLibraryResourcesProvider.overrideWithValue(resources),
        sampleLibraryLongWorkKeeperProvider.overrideWithValue(keeper),
        loadSampleLibraryUseCaseProvider.overrideWith(
          (ref) => LoadSampleLibraryUseCase(
            resources: ref.watch(sampleLibraryResourcesProvider),
            ledger: ledger,
            downloader: downloader,
            captureItem: capture,
            repository: FakeLibraryRepository(),
            enqueue: (_) {},
            ids: FakeIdGenerator(),
            clock: () => DateTime.utc(2026, 10, 3),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('disponible según la flavor', () {
    test('en dev y en staging sí, en prod no', () {
      expect(container().read(sampleLibraryAvailableProvider), isTrue);
      expect(
        container(
          flavor: AppFlavor.staging,
        ).read(sampleLibraryAvailableProvider),
        isTrue,
      );
      expect(
        container(flavor: AppFlavor.prod).read(sampleLibraryAvailableProvider),
        isFalse,
      );
    });
  });

  group('SampleLibraryNotifier', () {
    test('carga, mantiene viva la app mientras tanto y termina con el '
        'informe', () async {
      final c = container();
      final states = <SampleLibraryState>[];
      c.listen(sampleLibraryProvider, (_, next) => states.add(next));

      await c.read(sampleLibraryProvider.notifier).start();

      final finished = c.read(sampleLibraryProvider) as SampleLibraryFinished;
      expect(finished.report.loaded, 3);
      expect(states.whereType<SampleLibraryLoading>(), isNotEmpty);
      expect(keeper.calls.first, '0/3');
      expect(keeper.calls, contains('3/3'));
      expect(keeper.calls.last, 'libre');
    });

    test('tocar dos veces no arranca dos cargas', () async {
      final c = container();
      final notifier = c.read(sampleLibraryProvider.notifier);

      await Future.wait([notifier.start(), notifier.start()]);

      expect(capture.requests, hasLength(3));
      expect(downloader.downloaded, ['pdf-laudato', 'audio-apologia']);
    });

    test('cancelar corta y deja el informe como cancelado', () async {
      downloader = FakeSampleFileDownloader(
        blockUntilCancelled: {'pdf-laudato'},
      );
      final c = container();
      final notifier = c.read(sampleLibraryProvider.notifier);

      final running = notifier.start();
      await downloader.blocked.future;
      notifier.cancel();
      expect(
        (c.read(sampleLibraryProvider) as SampleLibraryLoading).cancelling,
        isTrue,
      );
      await running;

      final finished = c.read(sampleLibraryProvider) as SampleLibraryFinished;
      expect(finished.report.cancelled, isTrue);
      expect(keeper.calls.last, 'libre');
    });
  });

  group('la fila de Ajustes', () {
    Future<ProviderContainer> pumpTile(
      WidgetTester tester, {
      List<SampleResource> resources = const [_web, _pdf, _audio],
    }) async {
      final c = container(resources: resources);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            locale: Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SampleLibraryTile()),
          ),
        ),
      );
      return c;
    }

    testWidgets('dice cuántos faltan y cuánto pesan', (tester) async {
      await pumpTile(tester);

      expect(find.text(es.sampleLibraryTitle), findsOneWidget);
      expect(find.text(es.sampleLibrarySubtitle(3, '10.0 MB')), findsOneWidget);
    });

    testWidgets('pide confirmación con lo que se baja, y cancelar no carga '
        'nada', (tester) async {
      await pumpTile(tester);

      await tester.tap(find.byKey(const Key('sample-library-tile')));
      await tester.pumpAndSettle();

      expect(find.text(es.sampleLibraryConfirmTitle), findsOneWidget);
      expect(
        find.text(es.sampleLibraryConfirmBody(3, '8.0 MB', '2.0 MB')),
        findsOneWidget,
      );

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(capture.requests, isEmpty);
    });

    testWidgets('al confirmar carga en segundo plano y avisa al terminar, '
        'con lo que falló a un toque', (tester) async {
      downloader = FakeSampleFileDownloader(failFor: {'audio-apologia'});
      await pumpTile(tester);

      await tester.tap(find.byKey(const Key('sample-library-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sample-library-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(es.sampleLibraryDoneSnack(2, 1)), findsOneWidget);
      expect(find.text(es.sampleLibraryLastRun(2, 1, 0)), findsOneWidget);

      await tester.tap(find.byKey(const Key('sample-library-failures')));
      await tester.pumpAndSettle();

      expect(find.text(es.sampleLibraryFailuresTitle), findsOneWidget);
      expect(find.text('Apología de Sócrates'), findsOneWidget);
      expect(find.text('El servidor respondió 404.'), findsOneWidget);
    });

    testWidgets('mientras carga muestra el avance y deja cancelar', (
      tester,
    ) async {
      downloader = FakeSampleFileDownloader(
        blockUntilCancelled: {'pdf-laudato'},
      );
      final c = await pumpTile(tester);

      final running = c.read(sampleLibraryProvider.notifier).start();
      await tester.pump();

      expect(find.text(es.sampleLibraryLoadingTitle), findsOneWidget);
      expect(find.text(es.sampleLibraryProgress(2, 3, 1, 1)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.tap(find.byKey(const Key('sample-library-cancel')));
      await tester.pump();
      await running;
      await tester.pumpAndSettle();

      expect(find.text(es.sampleLibraryLastRunCancelled(2, 0)), findsOneWidget);
    });

    testWidgets('con todo cargado, lo dice y no ofrece cargar', (tester) async {
      ledger.ids.addAll({'web-roma', 'pdf-laudato', 'audio-apologia'});
      await pumpTile(tester);

      expect(find.text(es.sampleLibraryAllLoaded(3)), findsOneWidget);
      await tester.tap(find.byKey(const Key('sample-library-tile')));
      await tester.pumpAndSettle();
      expect(find.text(es.sampleLibraryConfirmTitle), findsNothing);
    });
  });
}
