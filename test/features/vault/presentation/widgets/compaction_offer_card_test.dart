import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/services/compaction_advisor.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_compaction_providers.dart';
import 'package:sinapsis/features/vault/presentation/widgets/compaction_offer_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

const _mib = 1024 * 1024;
const _answeredKey = 'compaction_offer_answered';

/// 1 GiB de archivo con [freePages] páginas libres de 4 KiB y el disco que la
/// prueba diga.
CompactionAssessment _vault({
  int freePages = 131072,
  int pageCount = 262144,
  int? freeSpaceBytes = 10 * 1024 * _mib,
}) => CompactionAssessment(
  pageSize: 4096,
  pageCount: pageCount,
  freePages: freePages,
  autoVacuum: AutoVacuumMode.none,
  freeSpaceBytes: freeSpaceBytes,
);

class _FakeAdvisor implements CompactionAdvisor {
  _FakeAdvisor(this.assessment);

  CompactionAssessment assessment;

  @override
  Future<CompactionAssessment> assess() async => assessment;
}

/// La oferta única de compactar (F12): aparece cuando hay bastante para
/// devolver, se contesta una vez y no vuelve.
void main() {
  final es = AppLocalizationsEs();
  late _FakeAdvisor advisor;
  late SharedPreferences prefs;

  setUp(() async {
    advisor = _FakeAdvisor(_vault());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// La oferta sobre una pantalla, con un router de verdad: «Ver» navega.
  Future<void> pumpCard(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: Column(children: [CompactionOfferCard(), Text('la lista')]),
          ),
        ),
        GoRoute(
          path: RoutePaths.vaultCompaction,
          builder: (context, state) =>
              const Scaffold(body: Text('pantalla de compactación')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          compactionAdvisorProvider.overrideWithValue(advisor),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder offer() => find.byKey(const ValueKey('compaction-offer'));

  group('cuándo aparece', () {
    testWidgets('con bastante para devolver, dice cuánto', (tester) async {
      await pumpCard(tester);

      expect(offer(), findsOneWidget);
      // 1 GiB de archivo, la mitad libre.
      expect(
        find.text(es.vaultCompactionOfferTitle('512,0 MB')),
        findsOneWidget,
      );
      expect(find.text(es.vaultCompactionOfferBody), findsOneWidget);
    });

    testWidgets('con poco para devolver, no', (tester) async {
      // 32 MiB: bajo el mínimo de 64.
      advisor.assessment = _vault(freePages: 8192);
      await pumpCard(tester);

      expect(offer(), findsNothing);
    });

    testWidgets('con unos MB sueltos en una bóveda enorme, no', (tester) async {
      // 4 GiB de archivo, 100 MiB libres: pasa el mínimo pero no el 15 %.
      advisor.assessment = _vault(pageCount: 1048576, freePages: 25600);
      await pumpCard(tester);

      expect(offer(), findsNothing);
    });

    testWidgets('sin lugar en el disco no se ofrece lo que no se puede', (
      tester,
    ) async {
      advisor.assessment = _vault(freeSpaceBytes: 50 * _mib);
      await pumpCard(tester);

      expect(offer(), findsNothing);
    });

    testWidgets('sin dato de disco se ofrece: se puede intentar', (
      tester,
    ) async {
      advisor.assessment = _vault(freeSpaceBytes: null);
      await pumpCard(tester);

      expect(offer(), findsOneWidget);
    });

    testWidgets('sin nada que recuperar, no', (tester) async {
      advisor.assessment = _vault(freePages: 0);
      await pumpCard(tester);

      expect(offer(), findsNothing);
    });

    testWidgets('sin oferta no ocupa nada de la pantalla', (tester) async {
      advisor.assessment = _vault(freePages: 0);
      await pumpCard(tester);

      expect(tester.getSize(find.byType(CompactionOfferCard)).height, 0);
    });
  });

  group('se contesta una sola vez', () {
    testWidgets('«Ahora no» la quita y no vuelve', (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text(es.vaultCompactionOfferNotNow));
      await tester.pumpAndSettle();

      expect(offer(), findsNothing);
      expect(prefs.getBool(_answeredKey), isTrue);
      // Aunque siga habiendo lo mismo para devolver, una pantalla nueva con
      // las mismas preferencias —otra sesión— no la vuelve a mostrar.
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester);
      expect(offer(), findsNothing);
    });

    testWidgets('«Ver» abre la pantalla de compactación y también la '
        'contesta', (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text(es.vaultCompactionOfferReview));
      await tester.pumpAndSettle();

      expect(find.text('pantalla de compactación'), findsOneWidget);
      expect(prefs.getBool(_answeredKey), isTrue);
    });

    testWidgets('si ya se contestó antes, no aparece', (tester) async {
      SharedPreferences.setMockInitialValues({_answeredKey: true});
      prefs = await SharedPreferences.getInstance();

      await pumpCard(tester);

      expect(offer(), findsNothing);
    });
  });
}
