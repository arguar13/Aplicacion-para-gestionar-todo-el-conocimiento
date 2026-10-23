import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/services/link_strength.dart';
import 'package:sinapsis/features/map/presentation/widgets/link_strength_selector.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// El selector «Más fuertes · Menos fuertes · Todos» de la vista «Vínculos»
/// (F39, paso 8).
void main() {
  final es = AppLocalizationsEs();

  Future<void> pump(
    WidgetTester tester, {
    required LinkStrengthFilter strength,
    required ValueChanged<LinkStrengthFilter> onChanged,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LinkStrengthSelector(strength: strength, onChanged: onChanged),
      ),
    ),
  );

  bool selected(WidgetTester tester, String label) => tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
      .selected;

  testWidgets('ofrece las tres opciones, en orden, con la elegida marcada', (
    tester,
  ) async {
    await pump(tester, strength: LinkStrengthFilter.weakest, onChanged: (_) {});

    expect(find.text(es.mapLinksStrengthLabel), findsOneWidget);
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(
      [for (final chip in chips) (chip.label as Text).data],
      [
        es.mapLinksStrengthStrongest,
        es.mapLinksStrengthWeakest,
        es.mapLinksStrengthAll,
      ],
    );
    expect(selected(tester, es.mapLinksStrengthWeakest), isTrue);
    expect(selected(tester, es.mapLinksStrengthStrongest), isFalse);
    expect(selected(tester, es.mapLinksStrengthAll), isFalse);
  });

  testWidgets('tocar una opción avisa cuál es', (tester) async {
    final chosen = <LinkStrengthFilter>[];
    await pump(tester, strength: LinkStrengthFilter.all, onChanged: chosen.add);

    await tester.tap(find.text(es.mapLinksStrengthStrongest));
    await tester.tap(find.text(es.mapLinksStrengthWeakest));

    expect(chosen, [LinkStrengthFilter.strongest, LinkStrengthFilter.weakest]);
  });
}
