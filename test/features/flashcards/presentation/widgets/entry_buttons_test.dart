import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/my_cards_entry_button.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_stats_entry_button.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Los dos botones sueltos que el integrador enchufa en la sesión de repaso
/// (F31, ola 2, decisión 72).
void main() {
  final es = AppLocalizationsEs();

  Future<GoRouter> pump(
    WidgetTester tester, {
    StudyScope scope = const StudyScope.all(),
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            appBar: AppBar(
              actions: [
                MyCardsEntryButton(scope: scope),
                const ReviewStatsEntryButton(),
              ],
            ),
          ),
        ),
        GoRoute(
          path: kRouteCards,
          builder: (context, state) => Text('cards ${state.uri}'),
        ),
        GoRoute(
          path: kRouteReviewStats,
          builder: (context, state) => const Text('stats'),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('cada botón tiene su ayuda', (tester) async {
    await pump(tester);

    expect(find.byTooltip(es.myCardsEntryTooltip), findsOneWidget);
    expect(find.byTooltip(es.cardStatsEntryTooltip), findsOneWidget);
  });

  testWidgets('«Mis tarjetas» lleva a /cards', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('my-cards-entry')));
    await tester.pumpAndSettle();

    expect(find.text('cards /cards'), findsOneWidget);
  });

  testWidgets('con un recorte, lo lleva en la dirección', (tester) async {
    await pump(tester, scope: const StudyScope.item('roma'));

    await tester.tap(find.byKey(const Key('my-cards-entry')));
    await tester.pumpAndSettle();

    expect(find.text('cards /cards?item=roma'), findsOneWidget);
  });

  testWidgets('las estadísticas llevan a /review/stats', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('review-stats-entry')));
    await tester.pumpAndSettle();

    expect(find.text('stats'), findsOneWidget);
  });
}
