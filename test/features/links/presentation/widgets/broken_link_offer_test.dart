import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/features/links/presentation/widgets/broken_link_offer.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();

  NoteKind? created;
  var dismissed = 0;

  setUp(() {
    created = null;
    dismissed = 0;
  });

  Future<void> pumpOffer(
    WidgetTester tester, {
    String title = 'Cartago',
    int moreCount = 0,
    bool busy = false,
    Widget? above,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              ?above,
              BrokenLinkOffer(
                title: title,
                moreCount: moreCount,
                busy: busy,
                onCreate: (kind) => created = kind,
                onDismiss: () => dismissed++,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('pregunta si crear la nota y muestra el enlace como se '
      'escribió', (tester) async {
    await pumpOffer(tester);

    expect(find.text(es.blocksBrokenLinkTitle), findsOneWidget);
    expect(find.text('Esa nota no existe. ¿La creamos?'), findsOneWidget);
    expect(find.text('[[Cartago]]'), findsOneWidget);
  });

  testWidgets('avisa cuántos enlaces más faltan, y calla si no hay '
      'ninguno', (tester) async {
    await pumpOffer(tester, moreCount: 2);
    expect(find.text(es.blocksBrokenLinkMore(2)), findsOneWidget);

    await pumpOffer(tester);
    expect(find.textContaining('sin nota'), findsNothing);
  });

  testWidgets('el subtipo por defecto es viva', (tester) async {
    await pumpOffer(tester);

    await tester.tap(find.text(es.blocksBrokenLinkCreate));

    expect(created, NoteKind.living);
  });

  testWidgets('ofrece los tres subtipos y crea con el elegido', (tester) async {
    await pumpOffer(tester);
    expect(find.widgetWithText(ChoiceChip, es.noteKindAtomic), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, es.noteKindLiving), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, es.noteKindMap), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, es.noteKindMap));
    await tester.pump();
    await tester.tap(find.text(es.blocksBrokenLinkCreate));

    expect(created, NoteKind.map);
  });

  testWidgets('el subtipo elegido para un enlace no queda elegido para el '
      'siguiente', (tester) async {
    await pumpOffer(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, es.noteKindAtomic));
    await tester.pump();

    await pumpOffer(tester, title: 'Atenas');
    await tester.tap(find.text(es.blocksBrokenLinkCreate));

    expect(created, NoteKind.living);
  });

  testWidgets('"Ahora no" descarta sin crear nada', (tester) async {
    await pumpOffer(tester);

    await tester.tap(find.text(es.blocksBrokenLinkDismiss));

    expect(dismissed, 1);
    expect(created, isNull);
  });

  testWidgets('mientras se crea, ningún control responde', (tester) async {
    await pumpOffer(tester, busy: true);

    await tester.tap(find.text(es.blocksBrokenLinkCreate));
    await tester.tap(find.text(es.blocksBrokenLinkDismiss));
    await tester.tap(find.widgetWithText(ChoiceChip, es.noteKindMap));
    await tester.pump();

    expect(created, isNull);
    expect(dismissed, 0);
    final map = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, es.noteKindMap),
    );
    expect(map.selected, isFalse);
  });

  testWidgets('tocar el aviso no le quita el foco al campo de texto, ni con '
      'el mouse', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpOffer(tester, above: TextField(focusNode: focus));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);

    await tester.tap(
      find.widgetWithText(ChoiceChip, es.noteKindMap),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);

    await tester.tap(
      find.text(es.blocksBrokenLinkCreate),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(created, NoteKind.map);
    expect(focus.hasPrimaryFocus, isTrue);
  });

  testWidgets('no desborda en una pantalla angosta', (tester) async {
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpOffer(
      tester,
      title: 'Un título de nota bastante largo',
      moreCount: 3,
    );

    expect(tester.takeException(), isNull);
  });
}
