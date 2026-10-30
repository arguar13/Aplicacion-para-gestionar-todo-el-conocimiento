import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pick_living_note_dialog.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La tarjeta de triar y su barra, ordenadas por lo que se hace (F45, paso
/// 2): la decisión fija abajo, lo demás en un renglón o en «⋯», el aviso
/// compacto de la referencia, «Ver completo» como enlace, los atajos solo en
/// la computadora, «Deshacer» con el ícono del historial y la ficha de lo
/// pendiente. En 360 dp con la letra al doble, en claro y en oscuro.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  final now = DateTime(2026, 10, 30, 9);

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> seedSource({String id = 'fuente'}) => harness.container
      .read(libraryRepositoryProvider)
      .save(
        KnowledgeItem(
          id: id,
          title: 'El Imperio romano',
          source: Source(
            id: id,
            kind: SourceKind.document,
            capturedAt: now,
            authorName: 'Mary Beard',
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
          renditions: [
            Rendition.text(
              id: 'texto-$id',
              itemId: id,
              kind: RenditionKind.plainText,
              content: 'Roma fue una ciudad que se hizo imperio.',
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );

  Future<void> pumpInbox(
    WidgetTester tester, {
    Size size = const Size(900, 1400),
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      harness.wrap(
        Theme(
          data: themeMode == ThemeMode.dark
              ? ThemeData.dark()
              : ThemeData.light(),
          child: const InboxScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect rectOf(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

  group('la decisión', () {
    testWidgets('Descartar con borde y Triar relleno, fijos abajo, a lo ancho '
        'y del mismo alto', (tester) async {
      await seedSource();
      await pumpInbox(tester);

      final discard = find.byKey(const Key('inbox-discard'));
      final triage = find.byKey(const Key('inbox-triage'));
      expect(tester.widget(discard), isA<OutlinedButton>());
      expect(tester.widget(triage), isA<FilledButton>());
      expect(find.text(es.inboxActionTriage), findsOneWidget);

      final left = tester.getRect(discard);
      final right = tester.getRect(triage);
      expect(left.height, right.height);
      expect(left.top, right.top);
      expect(left.right, lessThan(right.left));
      expect(left.width, closeTo(right.width, 1));
      // La última fila de la tarjeta: debajo de todo lo demás, y no pegada al
      // borde de la pantalla, donde la taparía el aviso.
      expect(
        find.ancestor(of: discard, matching: find.byType(Card)),
        findsOneWidget,
      );
      expect(
        left.top,
        greaterThan(tester.getRect(find.byKey(const Key('inbox-link'))).bottom),
      );
    });

    testWidgets('con la letra al doble y un renglón más en uno, siguen del '
        'mismo alto', (tester) async {
      await seedSource();
      await pumpInbox(tester, size: const Size(360, 780), textScale: 2);

      final left = rectOf(tester, const Key('inbox-discard'));
      final right = rectOf(tester, const Key('inbox-triage'));
      expect(left.height, right.height);
      expect(tester.takeException(), isNull);
    });
  });

  group('lo demás', () {
    testWidgets('en ancho, un renglón de botones con ícono, sin «⋯»', (
      tester,
    ) async {
      await seedSource();
      await pumpInbox(tester);

      for (final key in [
        'inbox-pass-unchanged',
        'inbox-extract',
        'inbox-link',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('inbox-more-actions')), findsNothing);
      final pass = rectOf(tester, const Key('inbox-pass-unchanged'));
      final link = rectOf(tester, const Key('inbox-link'));
      expect(pass.top, link.top);
    });

    testWidgets('en angosto con la letra al doble, lo que no entra va a «⋯», '
        'y desde ahí se usa igual', (tester) async {
      await seedSource();
      await pumpInbox(tester, size: const Size(360, 780), textScale: 2);
      expect(tester.takeException(), isNull);

      final more = find.byKey(const Key('inbox-more-actions'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      expect(more, findsOneWidget);
      expect(find.byTooltip(es.f45S2MoreActions), findsOneWidget);
      // «Vincular», el último, no entró en el renglón.
      expect(find.byKey(const Key('inbox-link')), findsNothing);

      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inbox-link')), findsOneWidget);
      await tester.tap(find.byKey(const Key('inbox-link')));
      await tester.pumpAndSettle();
      expect(find.byType(PickLivingNoteDialog), findsOneWidget);
    });

    testWidgets('«Ver completo» es un enlace al pie del texto', (tester) async {
      final semantics = tester.ensureSemantics();
      await seedSource();
      await pumpInbox(tester);

      final link = find.byKey(const Key('inbox-view-full'));
      expect(
        tester.getRect(link).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const Key('pending-excerpt'))).bottom,
        ),
      );
      expect(
        tester.getSemantics(link),
        isSemantics(isLink: true, hasTapAction: true, label: es.inboxViewFull),
      );
      semantics.dispose();
    });

    testWidgets('los datos de la referencia, en un aviso compacto con «Usar» '
        'y la ✕', (tester) async {
      await seedSource();
      await harness.container
          .read(suggestionRepositoryProvider)
          .createMetadataSuggestion(
            targetItemId: 'fuente',
            extracted: const ExtractedMetadata(
              reference: ReferenceData(
                contributors: [
                  Contributor(
                    name: PersonName(family: 'García', given: 'Ana'),
                  ),
                ],
                doi: '10.1000/xyz',
              ),
            ),
          );
      await pumpInbox(tester);

      expect(find.text(es.referenceSuggestionBanner), findsOneWidget);
      final use = find.byKey(const Key('metadata-suggestion-use'));
      final close = find.byKey(const Key('metadata-suggestion-discard'));
      expect(tester.widget(use), isA<TextButton>());
      expect(tester.widget(close), isA<IconButton>());
      expect(find.byTooltip(es.referenceSuggestionDiscard), findsOneWidget);
      // En un solo renglón: el texto y, a su derecha, «Usar» y la ✕.
      expect(tester.getRect(use).center.dy, tester.getRect(close).center.dy);

      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text(es.referenceSuggestionBanner), findsNothing);
    });
  });

  group('los atajos', () {
    testWidgets('en el teléfono no se muestran', (tester) async {
      await seedSource();
      await pumpInbox(tester);

      expect(find.byKey(const Key('inbox-shortcuts-hint')), findsNothing);
    });

    testWidgets('en la computadora, sí, en una línea gris', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await seedSource();
      await pumpInbox(tester);

      expect(find.text(es.inboxShortcutsHint), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('la barra de arriba', () {
    testWidgets('«Deshacer» con el ícono del historial, y su texto en ancho', (
      tester,
    ) async {
      await seedSource();
      await pumpInbox(tester);

      final undo = find.byKey(const Key('inbox-undo'));
      expect(
        find.descendant(of: undo, matching: find.byIcon(Icons.history)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.undo), findsNothing);
      expect(
        find.descendant(of: undo, matching: find.text(es.inboxUndo)),
        findsOneWidget,
      );
      // Sin nada que deshacer, apagado.
      expect(tester.widget<ButtonStyleButton>(undo).onPressed, isNull);
    });

    testWidgets('en angosto, solo el ícono, con su nombre para el lector de '
        'pantalla', (tester) async {
      await seedSource();
      await pumpInbox(tester, size: const Size(360, 780));

      final undo = find.byKey(const Key('inbox-undo'));
      expect(tester.widget(undo), isA<IconButton>());
      expect(find.byTooltip(es.inboxUndo), findsOneWidget);
    });

    testWidgets('«1 pendiente» es una ficha que abre la cola', (tester) async {
      await seedSource();
      await pumpInbox(tester);

      final chip = find.byKey(const Key('inbox-pending-chip'));
      expect(tester.widget(chip), isA<ActionChip>());
      expect(
        find.descendant(of: chip, matching: find.text(es.inboxPendingCount(1))),
        findsOneWidget,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('se ve bien', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('en 360 con la letra al doble, en ${mode.name}, sin '
          'desbordarse', (tester) async {
        await seedSource();
        await pumpInbox(
          tester,
          size: const Size(360, 780),
          textScale: 2,
          themeMode: mode,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('inbox-triage')), findsOneWidget);
        expect(find.byKey(const Key('inbox-pending-chip')), findsOneWidget);
      });
    }
  });
}
