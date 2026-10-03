import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_result.dart';
import 'package:sinapsis/features/vault/domain/services/compaction_advisor.dart';
import 'package:sinapsis/features/vault/domain/services/vault_compactor.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_compaction_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/vault_compaction_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/silent_logger.dart';

const _mib = 1024 * 1024;

/// Una bóveda de 100 MiB con 50 de páginas libres, sin compactar nunca, y el
/// disco que cada prueba diga.
CompactionAssessment _assessment({
  int freePages = 12800,
  AutoVacuumMode autoVacuum = AutoVacuumMode.none,
  int? freeSpaceBytes = 10 * 1024 * _mib,
}) => CompactionAssessment(
  pageSize: 4096,
  pageCount: 25600,
  freePages: freePages,
  autoVacuum: autoVacuum,
  freeSpaceBytes: freeSpaceBytes,
);

class _FakeAdvisor implements CompactionAdvisor {
  _FakeAdvisor(this.assessment);

  CompactionAssessment assessment;
  int assessed = 0;

  @override
  Future<CompactionAssessment> assess() async {
    assessed++;
    return assessment;
  }
}

/// Un compactador al que la prueba le dice en qué fase va y cómo termina.
class _FakeCompactor implements VaultCompactor {
  var _outcome = Completer<CompactionResult>();
  void Function(CompactionProgress)? onProgress;
  CompactionCancellation? cancellation;
  int calls = 0;

  @override
  Future<CompactionResult> compact({
    void Function(CompactionProgress progress)? onProgress,
    CompactionCancellation? cancellation,
  }) {
    calls++;
    _outcome = Completer<CompactionResult>();
    this.onProgress = onProgress;
    this.cancellation = cancellation;
    return _outcome.future;
  }

  void progress(CompactionPhase phase, {int done = 0, int total = 0}) =>
      onProgress!(CompactionProgress(phase, done: done, total: total));

  void finish(CompactionResult result) => _outcome.complete(result);

  void fail(Object error) => _outcome.completeError(error);
}

void main() {
  final es = AppLocalizationsEs();
  late _FakeAdvisor advisor;
  late _FakeCompactor compactor;

  setUp(() {
    advisor = _FakeAdvisor(_assessment());
    compactor = _FakeCompactor();
  });

  /// La pantalla abierta desde otra, como en la app: así se ve si se puede
  /// salir de ella y a dónde se vuelve.
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compactionAdvisorProvider.overrideWithValue(advisor),
          vaultCompactorProvider.overrideWithValue(compactor),
          appLoggerProvider.overrideWithValue(const SilentLogger()),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const VaultCompactionScreen(),
                    ),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester, {String? label}) async {
    await tester.tap(find.text(label ?? es.vaultCompactionAction));
    await tester.pump();
  }

  Finder stopButton() => find.text(es.vaultCompactionStop);

  group('antes de empezar', () {
    testWidgets('dice cuánto ocupa, cuánto se puede recuperar y qué pide la '
        'primera vez', (tester) async {
      await pumpScreen(tester);

      expect(find.text(es.vaultCompactionTitle), findsOneWidget);
      expect(find.text(es.vaultCompactionExplanation), findsOneWidget);
      expect(find.text(es.vaultCompactionSizeLine('100,0 MB')), findsOneWidget);
      expect(
        find.text(es.vaultCompactionReclaimableLine('50,0 MB')),
        findsOneWidget,
      );
      // Reescribir pide el doble de lo útil (100) más 10 % (10) y 16 de resto.
      expect(
        find.text(es.vaultCompactionFirstTimeNote('126,0 MB')),
        findsOneWidget,
      );
      expect(find.text(es.vaultCompactionAction), findsOneWidget);
    });

    testWidgets('ya en modo incremental, avisa que se devuelve de a poco', (
      tester,
    ) async {
      advisor.assessment = _assessment(autoVacuum: AutoVacuumMode.incremental);
      await pumpScreen(tester);

      expect(find.text(es.vaultCompactionStepsNote), findsOneWidget);
      expect(find.textContaining('reescribe la bóveda entera'), findsNothing);
      expect(find.text(es.vaultCompactionAction), findsOneWidget);
    });

    testWidgets('sin nada que recuperar, lo dice y no ofrece compactar', (
      tester,
    ) async {
      advisor.assessment = _assessment(freePages: 0);
      await pumpScreen(tester);

      expect(find.text(es.vaultCompactionNothingLine), findsOneWidget);
      expect(find.text(es.vaultCompactionAction), findsNothing);
      expect(find.text(es.vaultCompactionActionAnyway), findsNothing);
    });

    testWidgets('sin lugar en el disco, dice cuánto hace falta, cuánto hay y '
        'cuánto falta, y no deja compactar', (tester) async {
      advisor.assessment = _assessment(freeSpaceBytes: 20 * _mib);
      await pumpScreen(tester);

      expect(
        find.text(es.vaultCompactionNoSpace('126,0 MB', '20,0 MB', '106,0 MB')),
        findsOneWidget,
      );
      expect(find.text(es.vaultCompactionAction), findsNothing);
      expect(find.text(es.vaultCompactionActionAnyway), findsNothing);
    });

    testWidgets('sin dato de disco, avisa y deja intentarlo igual', (
      tester,
    ) async {
      advisor.assessment = _assessment(freeSpaceBytes: null);
      await pumpScreen(tester);

      expect(find.text(es.vaultCompactionSpaceUnknown), findsOneWidget);
      expect(find.text(es.vaultCompactionActionAnyway), findsOneWidget);
      expect(find.text(es.vaultCompactionAction), findsNothing);

      await start(tester, label: es.vaultCompactionActionAnyway);

      expect(compactor.calls, 1);
    });
  });

  group('compactando', () {
    testWidgets('empezar llama al compactador y muestra la fase', (
      tester,
    ) async {
      await pumpScreen(tester);

      await start(tester);

      expect(compactor.calls, 1);
      expect(find.text(es.vaultCompactionPhaseChecking), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text(es.vaultCompactionKeepOpen), findsOneWidget);
      // Ya no está el botón de empezar.
      expect(find.text(es.vaultCompactionAction), findsNothing);
    });

    testWidgets('reescribir no se puede parar y no inventa un porcentaje', (
      tester,
    ) async {
      await pumpScreen(tester);
      await start(tester);

      compactor.progress(CompactionPhase.rewriting);
      await tester.pump();

      expect(find.text(es.vaultCompactionPhaseRewriting), findsOneWidget);
      expect(stopButton(), findsNothing);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull);
    });

    testWidgets('devolver de a tramos muestra el avance y se puede parar', (
      tester,
    ) async {
      await pumpScreen(tester);
      await start(tester);

      compactor.progress(CompactionPhase.returning, done: 10, total: 40);
      await tester.pump();

      expect(
        find.text(es.vaultCompactionPhaseReturning(10, 40)),
        findsOneWidget,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.25);
      expect(stopButton(), findsOneWidget);
    });

    testWidgets('parar le pasa el pedido al compactador, una sola vez', (
      tester,
    ) async {
      await pumpScreen(tester);
      await start(tester);
      compactor.progress(CompactionPhase.returning, done: 10, total: 40);
      await tester.pump();
      expect(compactor.cancellation!.isRequested, isFalse);

      await tester.tap(stopButton());
      await tester.pump();

      expect(compactor.cancellation!.isRequested, isTrue);
      // Pedirlo una vez alcanza: el botón ya no está activo.
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, es.vaultCompactionStop),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('la comprobación cuenta las fuentes y no se puede parar', (
      tester,
    ) async {
      await pumpScreen(tester);
      await start(tester);

      compactor.progress(CompactionPhase.verifying);
      await tester.pump();
      expect(find.text(es.vaultCompactionPhaseVerifying), findsOneWidget);

      compactor.progress(CompactionPhase.verifying, done: 25, total: 100);
      await tester.pump();

      expect(
        find.text(es.vaultCompactionPhaseVerifyingCount(25, 100)),
        findsOneWidget,
      );
      expect(stopButton(), findsNothing);
    });

    testWidgets('mientras compacta no se puede salir de la pantalla', (
      tester,
    ) async {
      await pumpScreen(tester);
      await start(tester);
      compactor.progress(CompactionPhase.rewriting);
      await tester.pump();

      // Ni con el botón —no hay— ni con el gesto de volver del sistema.
      expect(find.byType(BackButton), findsNothing);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      // El indicador sin fin nunca «se asienta»: se avanza un rato a mano.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(VaultCompactionScreen), findsOneWidget);
      expect(find.text('abrir'), findsNothing);
    });
  });

  group('cómo termina', () {
    const done = CompactionResult(
      bytesBefore: 100 * _mib,
      bytesAfter: 50 * _mib,
      elapsed: Duration(seconds: 42),
      sourcesVerified: 7,
    );

    Future<void> startAndFinish(
      WidgetTester tester,
      CompactionResult result,
    ) async {
      await pumpScreen(tester);
      await start(tester);
      compactor.finish(result);
      await tester.pumpAndSettle();
    }

    testWidgets('dice cuánto se devolvió y cuánto se comprobó', (tester) async {
      await startAndFinish(tester, done);

      expect(
        find.text(es.vaultCompactionDone('50,0 MB', '100,0 MB', '50,0 MB')),
        findsOneWidget,
      );
      expect(find.text(es.vaultCompactionVerified(7)), findsOneWidget);
    });

    testWidgets('«Listo» vuelve a la pantalla de antes', (tester) async {
      await startAndFinish(tester, done);

      await tester.tap(find.text(es.vaultCompactionDoneAction));
      await tester.pumpAndSettle();

      expect(find.byType(VaultCompactionScreen), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('lo devuelto cambia lo que la ficha de Ajustes dice', (
      tester,
    ) async {
      await pumpScreen(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VaultCompactionScreen)),
      );
      expect(
        (await container.read(compactionAssessmentProvider.future)).freePages,
        12800,
      );
      await start(tester);

      // La bóveda ya no tiene páginas libres cuando termina.
      advisor.assessment = _assessment(freePages: 0);
      compactor.finish(done);
      await tester.pumpAndSettle();

      expect(
        (await container.read(compactionAssessmentProvider.future)).freePages,
        0,
      );
    });

    testWidgets('si se paró, dice cuánto se devolvió hasta ahí y no afirma '
        'una comprobación que no hizo', (tester) async {
      await startAndFinish(
        tester,
        const CompactionResult(
          bytesBefore: 100 * _mib,
          bytesAfter: 80 * _mib,
          elapsed: Duration(seconds: 3),
          wasCancelled: true,
        ),
      );

      expect(find.text(es.vaultCompactionStopped('20,0 MB')), findsOneWidget);
      expect(find.textContaining('íntegro'), findsNothing);
    });

    testWidgets('si no había nada que devolver, lo dice sin festejar', (
      tester,
    ) async {
      await startAndFinish(
        tester,
        const CompactionResult(
          bytesBefore: 100 * _mib,
          bytesAfter: 100 * _mib,
          elapsed: Duration.zero,
        ),
      );

      expect(find.text(es.vaultCompactionNothingReturned), findsOneWidget);
      expect(find.textContaining('íntegro'), findsNothing);
    });
  });

  group('cuando no se pudo', () {
    Future<void> startAndFail(WidgetTester tester, Object error) async {
      await pumpScreen(tester);
      await start(tester);
      compactor.fail(error);
      await tester.pumpAndSettle();
    }

    testWidgets('sin lugar en el disco a último momento, dice cuánto falta', (
      tester,
    ) async {
      await startAndFail(
        tester,
        VaultCompactionNoSpaceException(_assessment(freeSpaceBytes: 30 * _mib)),
      );

      expect(
        find.text(es.vaultCompactionNoSpace('126,0 MB', '30,0 MB', '96,0 MB')),
        findsOneWidget,
      );
    });

    testWidgets('si SQLite falló, dice que la bóveda sigue completa', (
      tester,
    ) async {
      await startAndFail(tester, const VaultCompactionFailedException('x'));

      expect(find.text(es.vaultCompactionFailed), findsOneWidget);
    });

    testWidgets('si la comprobación encontró una diferencia, la muestra', (
      tester,
    ) async {
      await startAndFail(
        tester,
        const VaultCompactionVerificationException('chunks 40 → 39'),
      );

      expect(
        find.text(es.vaultCompactionVerificationFailed('chunks 40 → 39')),
        findsOneWidget,
      );
    });

    testWidgets('después de un fallo se puede volver a medir', (tester) async {
      await startAndFail(tester, const VaultCompactionFailedException('x'));
      final measuredBefore = advisor.assessed;

      await tester.tap(find.text(es.vaultCompactionDoneAction));
      await tester.pumpAndSettle();

      expect(advisor.assessed, greaterThan(measuredBefore));
      expect(find.text(es.vaultCompactionAction), findsOneWidget);
    });
  });
}
