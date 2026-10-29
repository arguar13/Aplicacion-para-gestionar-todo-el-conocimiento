import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_notice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_notice_listener.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Los avisos de la IA con su ✕, y el de la espera del tope por minuto con
/// su cuenta atrás (F43, M1).
void main() {
  final l10n = AppLocalizationsEs();
  final now = DateTime(2026, 10, 28, 20, 39);
  final account = AiAccount(
    id: 'a',
    provider: AiProvider.gemini,
    label: 'Personal',
    addedAt: now,
  );
  final other = AiAccount(
    id: 'b',
    provider: AiProvider.gemini,
    label: 'Trabajo',
    addedAt: now,
  );

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  Future<void> pumpListener(
    WidgetTester tester, {
    ThemeData? theme,
    double textScale = 1,
    List<int>? opened,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: AiNoticeListener(
              now: () => now,
              onOpenAccounts: () => opened?.add(1),
              child: child!,
            ),
          ),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
  }

  /// Avisa y deja que el aviso termine de entrar.
  Future<void> notify(WidgetTester tester, AiNotice notice) async {
    container.read(aiNoticeBusProvider).notify(notice);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Deja pasar [time] y lo que tarde un aviso en salir.
  Future<void> wait(WidgetTester tester, Duration time) async {
    await tester.pump(time);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder close() => find.byTooltip('Cerrar');

  RateLimitWaitNotice rateWait(int seconds, {AiAccount? of}) =>
      RateLimitWaitNotice(
        at: now,
        account: of ?? account,
        wait: Duration(seconds: seconds),
      );

  final everyKind = <String, AiNotice>{
    'cambio de cuenta': AccountSwitchedNotice(
      at: now,
      from: account,
      to: other,
      reason: CloudModelFailure.quotaExhausted,
    ),
    'sin cuentas': AllAccountsExhaustedNotice(
      at: now,
      provider: AiProvider.gemini,
      accounts: 2,
    ),
    'la espera': rateWait(28),
    'clave rechazada': AccountKeyRejectedNotice(
      at: now,
      account: account,
      reason: CloudModelFailure.invalidKey,
    ),
    'tope de fondo': BackgroundCapReachedNotice(at: now, cap: 50),
    'pedido fallido': AiRequestFailedNotice(
      at: now,
      provider: AiProvider.gemini,
      failure: CloudModelFailure.network,
    ),
  };

  group('la ✕', () {
    for (final MapEntry(key: name, value: notice) in everyKind.entries) {
      testWidgets('«$name» la tiene, a la derecha, y se cierra en el acto', (
        tester,
      ) async {
        await pumpListener(tester);
        await notify(tester, notice);

        final bar = find.byType(SnackBar);
        expect(bar, findsOneWidget);
        expect(close(), findsOneWidget);
        expect(
          tester.getCenter(close()).dx,
          greaterThan(tester.getCenter(bar).dx),
        );

        await tester.tap(close());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(SnackBar), findsNothing);
      });
    }

    testWidgets('el del botón de las cuentas también se va solo, a su tiempo, '
        'y el botón sigue andando', (tester) async {
      final opened = <int>[];
      await pumpListener(tester, opened: opened);
      await notify(tester, everyKind['cambio de cuenta']!);

      await tester.tap(find.text(l10n.noticeActionAccounts));
      expect(opened, [1]);
      await wait(tester, Duration.zero);
      expect(find.byType(SnackBar), findsNothing);

      await notify(tester, everyKind['sin cuentas']!);
      expect(find.text(l10n.noticeAllExhaustedTitle), findsOneWidget);
      await wait(tester, const Duration(seconds: 10));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('cerrado con la ✕, el mismo aviso seguido no vuelve a salir', (
      tester,
    ) async {
      await pumpListener(tester);
      await notify(tester, everyKind['pedido fallido']!);
      await tester.tap(close());
      await wait(tester, Duration.zero);

      await notify(tester, everyKind['pedido fallido']!);

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('la espera del tope por minuto', () {
    testWidgets('cuenta hacia atrás en vivo y se va sola cuando la IA sigue', (
      tester,
    ) async {
      await pumpListener(tester);
      await notify(tester, rateWait(28));

      expect(find.text(l10n.noticeRateWaitBody(28)), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text(l10n.noticeRateWaitBody(27)), findsOneWidget);

      await tester.pump(const Duration(seconds: 26));
      expect(find.text(l10n.noticeRateWaitBody(1)), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);

      await wait(tester, const Duration(seconds: 1));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('una espera larga no se va antes de tiempo', (tester) async {
      await pumpListener(tester);
      await notify(tester, rateWait(45));

      await tester.pump(const Duration(seconds: 30));

      expect(find.text(l10n.noticeRateWaitBody(15)), findsOneWidget);
    });

    testWidgets('otra espera con el aviso abierto corrige la cuenta, sin abrir '
        'otro', (tester) async {
      await pumpListener(tester);
      await notify(tester, rateWait(10));
      await tester.pump(const Duration(seconds: 6));
      expect(find.text(l10n.noticeRateWaitBody(4)), findsOneWidget);

      await notify(tester, rateWait(20));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.noticeRateWaitBody(20)), findsOneWidget);
      await wait(tester, const Duration(seconds: 10));
      expect(find.byType(SnackBar), findsOneWidget);
      await wait(tester, const Duration(seconds: 10));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('si vuelve a esperar después de seguir, se avisa de nuevo', (
      tester,
    ) async {
      await pumpListener(tester);
      await notify(tester, rateWait(3));
      await wait(tester, const Duration(seconds: 3));
      expect(find.byType(SnackBar), findsNothing);

      await notify(tester, rateWait(5));

      expect(find.text(l10n.noticeRateWaitBody(5)), findsOneWidget);
    });

    testWidgets('cerrada con la ✕, la cuenta se detiene y no cierra otro '
        'aviso', (tester) async {
      await pumpListener(tester);
      await notify(tester, rateWait(5));
      await tester.tap(close());
      await wait(tester, Duration.zero);

      await notify(tester, everyKind['pedido fallido']!);
      await tester.pump(const Duration(seconds: 6));

      // El de la espera ya no estaba: su cuenta no cierra el que vino
      // después, que dura sus nueve segundos.
      expect(find.text(l10n.noticeRequestFailedTitle), findsOneWidget);
    });
  });

  group('se ve bien', () {
    testWidgets(
      'a 360 dp y con letra doble, sin desbordes y con la ✕ adentro',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpListener(tester, textScale: 2);
        for (final notice in [
          everyKind['cambio de cuenta']!,
          everyKind['la espera']!,
          everyKind['pedido fallido']!,
        ]) {
          await notify(tester, notice);
          expect(tester.takeException(), isNull);
          final x = tester.getRect(close());
          expect(x.left, greaterThanOrEqualTo(0));
          expect(x.right, lessThanOrEqualTo(360));
          expect(x.bottom, lessThanOrEqualTo(780));
        }
      },
    );

    /// Los nueve temas: el claro, el oscuro y los siete con nombre.
    final themes = {
      for (final choice in AppThemeChoice.values)
        if (choice != AppThemeChoice.system)
          choice.name: choice.previews.single,
    };

    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final MapEntry(key: name, value: theme) in themes.entries) {
      testWidgets('en el tema «$name», la ✕ se distingue del aviso', (
        tester,
      ) async {
        await pumpListener(tester, theme: theme);
        await notify(tester, everyKind['clave rechazada']!);

        final icon = tester.widget<Icon>(
          find.descendant(of: close(), matching: find.byIcon(Icons.close)),
        );
        final color =
            IconTheme.of(tester.element(find.byIcon(Icons.close))).color ??
            icon.color!;
        final bar = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Material),
              )
              .first,
        );
        // Lo que pide WCAG para un ícono: 3 a 1.
        expect(contrast(color, bar.color!), greaterThanOrEqualTo(3));
      });
    }
  });
}
