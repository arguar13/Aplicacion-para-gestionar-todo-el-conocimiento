import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/config_providers.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/ai_organize/presentation/screens/ai_activity_screen.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_model_screen.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/reference_styles.dart';
import 'package:sinapsis/features/citations/presentation/providers/citation_preferences.dart';
import 'package:sinapsis/features/dev_seed/presentation/widgets/sample_library_tile.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_preferences.dart';
import 'package:sinapsis/features/links/presentation/screens/broken_links_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/trash/presentation/screens/trash_screen.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/merge_conflicts_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/vault_compaction_screen.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Agranda la ventana hasta que Ajustes entra entero, sin desplazar.
  ///
  /// Estas pruebas miran y tocan filas de toda la lista, y una lista perezosa
  /// no construye lo que está lejos de la vista. Antes la ventana tenía un
  /// alto fijo (1600, o 1400 con el router), y cada sección nueva —F7, F15,
  /// la IA de F27— dejaba afuera las del final y rompía pruebas que no
  /// tenían nada que ver. Medir lo que falta desplazar y sumarlo deja la
  /// ventana del tamaño de la lista, crezca lo que crezca.
  Future<void> fitWholeSettings(WidgetTester tester) async {
    final scrollable = find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    final overflow = tester
        .state<ScrollableState>(scrollable)
        .position
        .maxScrollExtent;
    final ratio = tester.view.devicePixelRatio;
    final size = tester.view.physicalSize;
    tester.view.physicalSize = Size(size.width, size.height + overflow * ratio);
    await tester.pumpAndSettle();
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness.wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
    await fitWholeSettings(tester);
  }

  testWidgets('muestra las cinco secciones', (tester) async {
    await pumpSettings(tester);

    expect(find.text(es.settingsAppearanceSection), findsOneWidget);
    expect(find.text(es.settingsCitationsSection), findsOneWidget);
    expect(find.text(es.settingsAiSection), findsOneWidget);
    expect(find.text(es.settingsVaultSection), findsOneWidget);
    expect(find.text(es.settingsHabitSection), findsOneWidget);
  });

  group('desarrollo: la biblioteca de ejemplo', () {
    testWidgets('en dev hay una sección más, con la fila para cargarla', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text(es.settingsDevelopmentSection), findsOneWidget);
      expect(find.byType(SampleLibraryTile), findsOneWidget);
      expect(find.text(es.sampleLibraryTitle), findsOneWidget);
    });

    testWidgets('en prod no existe: ni la sección ni la fila', (tester) async {
      harness = await LibraryHarness.create(
        extraOverrides: [appFlavorProvider.overrideWithValue(AppFlavor.prod)],
      );
      await pumpSettings(tester);

      expect(find.text(es.settingsDevelopmentSection), findsNothing);
      expect(find.byType(SampleLibraryTile), findsNothing);
      expect(find.text(es.sampleLibraryTitle), findsNothing);
      // El resto de Ajustes, igual.
      expect(find.text(es.settingsHabitSection), findsOneWidget);
    });
  });

  group('citas (F15)', () {
    testWidgets('arrancan en APA 7 y el idioma de la app', (tester) async {
      await pumpSettings(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('settings-citation-style')),
          matching: find.text('APA 7'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-citation-language')),
          matching: find.text(es.settingsCitationLanguageApp),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tocar el estilo pasa al siguiente y se recuerda', (
      tester,
    ) async {
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings-citation-style')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('settings-citation-style')),
          matching: find.text('MLA 9'),
        ),
        findsOneWidget,
      );
      expect(
        harness.container.read(citationPreferencesProvider).styleId,
        'mla9',
      );
    });

    testWidgets('los estilos dan la vuelta y vuelven al primero', (
      tester,
    ) async {
      await pumpSettings(tester);

      for (var i = 0; i < kReferenceStyles.styles.length; i++) {
        await tester.tap(find.byKey(const Key('settings-citation-style')));
        await tester.pumpAndSettle();
      }

      expect(
        harness.container.read(citationPreferencesProvider).styleId,
        'apa7',
      );
    });

    testWidgets('tocar el idioma pasa por español, inglés y el de la app', (
      tester,
    ) async {
      await pumpSettings(tester);
      Future<void> tapLanguage() async {
        await tester.tap(find.byKey(const Key('settings-citation-language')));
        await tester.pumpAndSettle();
      }

      await tapLanguage();
      expect(
        harness.container.read(citationPreferencesProvider).language,
        CitationLanguage.es,
      );
      await tapLanguage();
      expect(
        harness.container.read(citationPreferencesProvider).language,
        CitationLanguage.en,
      );
      expect(find.text(es.citationLanguageEn), findsOneWidget);
      await tapLanguage();
      expect(
        harness.container.read(citationPreferencesProvider).language,
        isNull,
      );
    });
  });

  group('idioma', () {
    testWidgets('muestra el idioma efectivo actual', (tester) async {
      await pumpSettings(tester);

      expect(find.text('ES'), findsOneWidget);
    });

    testWidgets('tocarlo lo cambia al siguiente de la lista', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(es.languageTooltip));
      await tester.pumpAndSettle();

      expect(find.text('EN'), findsOneWidget);
    });
  });

  group('tema', () {
    testWidgets('arranca en "sistema"', (tester) async {
      await pumpSettings(tester);

      expect(find.text(es.themeModeSystem), findsOneWidget);
    });

    testWidgets('tocarlo lo cambia al siguiente de la lista', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(es.themeModeTooltip));
      await tester.pumpAndSettle();

      expect(find.text(es.themeModeLight), findsOneWidget);
      expect(
        harness.container.read(themeModeNotifierProvider),
        ThemeMode.light,
      );
    });
  });

  group('IA (F27)', () {
    /// Los interruptores de cada tipo: todos menos el general.
    final types = [
      for (final toggle in AiOrganizeToggle.values)
        if (toggle != AiOrganizeToggle.enabled) toggle,
    ];

    SwitchListTile toggleTile(WidgetTester tester, AiOrganizeToggle toggle) =>
        tester.widget<SwitchListTile>(
          find.byKey(Key('ai-toggle-${toggle.name}')),
        );

    testWidgets('el general y uno por cada cosa que organiza, todos '
        'prendidos', (tester) async {
      await pumpSettings(tester);

      expect(find.text(es.settingsAiOrganize), findsOneWidget);
      for (final toggle in [AiOrganizeToggle.enabled, ...types]) {
        expect(toggleTile(tester, toggle).value, isTrue, reason: toggle.name);
      }
      expect(find.text(es.settingsAiBackfill), findsOneWidget);
      expect(find.text(es.settingsAiBackfillSubtitle), findsOneWidget);
    });

    testWidgets('cada interruptor se guarda', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('ai-toggle-flashcards')));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(aiOrganizeSettingsProvider).flashcards,
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ai_organize_flashcards'), isFalse);
      expect(toggleTile(tester, AiOrganizeToggle.flashcards).value, isFalse);
    });

    testWidgets('con el general apagado, los de cada tipo se apagan y '
        'conservan lo elegido', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('ai-toggle-atlas')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-toggle-enabled')));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(aiOrganizeSettingsProvider).enabled,
        isFalse,
      );
      for (final toggle in types) {
        expect(
          toggleTile(tester, toggle).onChanged,
          isNull,
          reason: toggle.name,
        );
      }
      // Tocarlos no cambia nada.
      await tester.tap(find.byKey(const Key('ai-toggle-relations')));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(aiOrganizeSettingsProvider).relations,
        isTrue,
      );
      // Lo que cada uno tenía queda para cuando se vuelva a prender.
      expect(toggleTile(tester, AiOrganizeToggle.atlas).value, isFalse);

      await tester.tap(find.byKey(const Key('ai-toggle-enabled')));
      await tester.pumpAndSettle();
      expect(
        toggleTile(tester, AiOrganizeToggle.relations).onChanged,
        isNotNull,
      );
    });

    testWidgets('la línea de la cola dice en qué anda y cuántos esperan', (
      tester,
    ) async {
      await pumpSettings(tester);
      expect(find.text(es.aiStatusIdleTitle), findsOneWidget);

      harness.container
          .read(aiOrganizeStatusProvider.notifier)
          .state = const AiOrganizeWorking(
        itemTitle: 'Roma',
        pending: 3,
        source: AiWorkSource.fresh,
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          '${es.aiStatusWorkingTitle('Roma')} · ${es.aiStatusQueued(3)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('cuenta lo que espera revisión', (tester) async {
      await insertItemRows(harness.database, id: 'a', title: 'Roma');
      await insertItemRows(harness.database, id: 'b', title: 'Cartago');
      await harness.container
          .read(suggestionRepositoryProvider)
          .createRelationSuggestion(
            targetItemId: 'a',
            relatedItemId: 'b',
            relatedItemTitle: 'Cartago',
            kind: RelationKind.relatedTo,
            reason: 'La misma guerra',
          );
      await pumpSettings(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('settings-ai-review-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    group('la biblioteca existente', () {
      // El reloj de la harness es el 11 de septiembre: la IA organiza sola
      // desde entonces, y lo guardado antes es la biblioteca que ya existía.
      Future<void> seedExisting(int count) async {
        for (var i = 0; i < count; i++) {
          await insertItemRows(
            harness.database,
            id: 'antes-$i',
            title: 'De antes $i',
            createdAt: DateTime(2026, 9, 1, 10, i),
          );
        }
      }

      final progress = find.byKey(const Key('ai-backfill-progress'));
      final bar = find.byKey(const Key('ai-backfill-progress-bar'));

      void setStatus(AiOrganizeStatus status) =>
          harness.container.read(aiOrganizeStatusProvider.notifier).state =
              status;

      String progressText(WidgetTester tester) => tester
          .widget<Text>(
            find.descendant(of: progress, matching: find.byType(Text)),
          )
          .data!;

      testWidgets('debajo de su interruptor, cuántos quedan', (tester) async {
        await seedExisting(2);
        await pumpSettings(tester);

        expect(progressText(tester), es.settingsAiBackfillRemaining(2));
        expect(bar, findsNothing);
        // Justo debajo del interruptor, alineada con su texto.
        final toggle = find.byKey(const Key('ai-toggle-backfillWhileCharging'));
        expect(
          tester.getTopLeft(progress).dy,
          moreOrLessEquals(tester.getBottomLeft(toggle).dy),
        );
        expect(
          tester.getTopLeft(find.text(es.settingsAiBackfill)).dx,
          moreOrLessEquals(
            tester.getTopLeft(find.text(progressText(tester))).dx,
          ),
        );
      });

      testWidgets('sin nada de antes, dice que ya está ordenada', (
        tester,
      ) async {
        await pumpSettings(tester);

        expect(progressText(tester), es.settingsAiBackfillDone);
      });

      testWidgets('si espera el cargador, lo dice', (tester) async {
        await seedExisting(3);
        await pumpSettings(tester);

        setStatus(const AiOrganizePaused(pending: 3, waitingForCharger: true));
        await tester.pumpAndSettle();

        expect(progressText(tester), es.settingsAiBackfillCharger(3));
        expect(bar, findsNothing);
      });

      testWidgets('mientras la ordena, una barra fina', (tester) async {
        await seedExisting(2);
        await pumpSettings(tester);

        setStatus(
          const AiOrganizeWorking(
            itemTitle: 'De antes 1',
            pending: 1,
            source: AiWorkSource.existingLibrary,
          ),
        );
        // La barra es indeterminada y anima siempre: alcanza con dejar pasar
        // la cuenta nueva y el cambio de alto.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(progressText(tester), es.settingsAiBackfillWorking(2));
        expect(bar, findsOneWidget);
      });

      testWidgets('si organiza algo pedido a mano, no dice que ordena la '
          'biblioteca de antes, aunque queden elementos viejos', (
        tester,
      ) async {
        await seedExisting(2);
        await pumpSettings(tester);

        // Antes se deducía —trabajando, sin nada nuevo y con elementos de
        // antes—, y esto mostraba la barra sin que fuera la biblioteca.
        setStatus(
          const AiOrganizeWorking(
            itemTitle: 'De antes 1',
            pending: 1,
            source: AiWorkSource.requested,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(progressText(tester), es.settingsAiBackfillRemaining(2));
        expect(bar, findsNothing);
      });

      testWidgets('si está con algo nuevo, no dice que la ordena: lo nuevo '
          'va primero', (tester) async {
        await seedExisting(2);
        await insertItemRows(harness.database, id: 'nuevo', title: 'Nuevo');
        await pumpSettings(tester);

        setStatus(
          const AiOrganizeWorking(
            itemTitle: 'Nuevo',
            pending: 2,
            source: AiWorkSource.fresh,
          ),
        );
        await tester.pumpAndSettle();

        expect(progressText(tester), es.settingsAiBackfillRemaining(2));
        expect(bar, findsNothing);
      });

      testWidgets('se vuelve a contar cuando la cola termina una pasada', (
        tester,
      ) async {
        await seedExisting(2);
        await pumpSettings(tester);
        expect(progressText(tester), es.settingsAiBackfillRemaining(2));

        // La cola organizó uno de antes y quedó esperando el cargador.
        final runs = harness.container.read(aiRunRepositoryProvider);
        final runId = (await runs.startRun(
          'antes-0',
        )).getOrElse((f) => fail('$f'));
        await runs.finishRun(runId);
        setStatus(const AiOrganizePaused(pending: 1, waitingForCharger: true));
        await tester.pumpAndSettle();

        expect(progressText(tester), es.settingsAiBackfillCharger(1));
      });

      testWidgets('apagado, cuántos quedan sin ordenar', (tester) async {
        await seedExisting(2);
        await pumpSettings(tester);

        await tester.tap(
          find.byKey(const Key('ai-toggle-backfillWhileCharging')),
        );
        await tester.pumpAndSettle();

        expect(progressText(tester), es.settingsAiBackfillOff(2));
      });
    });

    Future<void> openFromSettings(WidgetTester tester, Key key) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();
      await fitWholeSettings(tester);

      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    testWidgets('«Lo que hizo la IA» abre su pantalla, con el router real', (
      tester,
    ) async {
      await openFromSettings(tester, const Key('settings-ai-activity'));

      expect(find.byType(AiActivityScreen), findsOneWidget);
    });

    testWidgets('el modelo de lenguaje se alcanza desde Ajustes, con el '
        'router real', (tester) async {
      await openFromSettings(tester, const Key('settings-chat-model'));

      expect(find.byType(ChatModelScreen), findsOneWidget);
    });
  });

  group('hábito (F17, D9)', () {
    testWidgets('arranca encendido', (tester) async {
      await pumpSettings(tester);

      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('settings-habit-features-toggle')),
      );
      expect(toggle.value, isTrue);
      expect(harness.container.read(habitFeaturesEnabledProvider), isTrue);
    });

    testWidgets('tocarlo lo apaga y se recuerda', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings-habit-features-toggle')));
      await tester.pumpAndSettle();

      expect(harness.container.read(habitFeaturesEnabledProvider), isFalse);
    });
  });

  group('bóveda', () {
    testWidgets('bloquear la bóveda actualiza la sesión', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(es.lockVaultTooltip));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(vaultSessionControllerProvider),
        isA<VaultLocked>(),
      );
    });

    testWidgets('muestra la opción de posibles duplicados (F7)', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text(es.duplicatesSettingsTooltip), findsOneWidget);
    });

    testWidgets('muestra la opción del vocabulario (F8)', (tester) async {
      await pumpSettings(tester);

      expect(find.text(es.vocabularySettingsTooltip), findsOneWidget);
    });

    testWidgets('tocar el vocabulario abre su pantalla, con el router real', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();
      await fitWholeSettings(tester);

      await tester.tap(find.text(es.vocabularySettingsTooltip));
      // Sin `pumpAndSettle`: la pantalla real calcula los candidatos en un
      // isolate (`compute`), que no corre bajo el reloj simulado, y su
      // indicador de carga anima para siempre. Para probar la navegación
      // alcanzan unos cuadros.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(VocabularyScreen), findsOneWidget);
      expect(find.text(es.vocabularyTitle), findsOneWidget);
    });

    testWidgets('muestra la opción de enlaces rotos (F9)', (tester) async {
      await pumpSettings(tester);

      expect(find.text(es.brokenLinksTitle), findsOneWidget);
    });

    testWidgets('tocar los enlaces rotos abre su pantalla, con el router '
        'real', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();
      await fitWholeSettings(tester);

      await tester.tap(find.text(es.brokenLinksTitle));
      await tester.pumpAndSettle();

      expect(find.byType(BrokenLinksScreen), findsOneWidget);
      // La bóveda de la prueba no tiene ningún enlace roto.
      expect(find.text(es.brokenLinksEmpty), findsOneWidget);
    });

    testWidgets('muestra la papelera (F11)', (tester) async {
      await pumpSettings(tester);

      expect(find.text(es.trashTitle), findsOneWidget);
    });

    testWidgets('tocar la papelera abre su pantalla, con el router real', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();
      await fitWholeSettings(tester);

      await tester.tap(find.text(es.trashTitle));
      await tester.pumpAndSettle();

      expect(find.byType(TrashScreen), findsOneWidget);
      // La bóveda de la prueba no borró nada.
      expect(find.text(es.trashEmptyTitle), findsOneWidget);
    });

    testWidgets('muestra los cambios para revisar, con cuántos hay (F11)', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text(es.conflictsTitle), findsOneWidget);
      // La bóveda de la prueba no fusionó nada.
      expect(find.text(es.conflictsSettingsSubtitle(0)), findsOneWidget);
    });

    testWidgets('tocarlos abre su pantalla, con el router real', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();
      await fitWholeSettings(tester);

      await tester.tap(find.text(es.conflictsTitle));
      await tester.pumpAndSettle();

      expect(find.byType(MergeConflictsScreen), findsOneWidget);
      expect(find.text(es.conflictsEmptyTitle), findsOneWidget);
    });

    group('el espacio de la bóveda (F12)', () {
      /// Lo que un borrado deja: páginas libres dentro de la base.
      Future<void> leaveFreePages() async {
        final db = harness.database;
        await db.customStatement(
          'CREATE TABLE relleno (id INTEGER PRIMARY KEY, v BLOB NOT NULL)',
        );
        await db.customStatement('''
          WITH RECURSIVE n(x) AS (
            SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 400
          )
          INSERT INTO relleno (v) SELECT randomblob(3000) FROM n''');
        await db.customStatement('DELETE FROM relleno');
      }

      testWidgets('con la bóveda al día, dice que no hay nada que recuperar', (
        tester,
      ) async {
        await pumpSettings(tester);

        expect(find.text(es.vaultCompactionSettingsTooltip), findsOneWidget);
        expect(find.text(es.vaultCompactionSettingsNothing), findsOneWidget);
      });

      testWidgets('con páginas libres, dice cuánto se puede recuperar', (
        tester,
      ) async {
        await leaveFreePages();

        await pumpSettings(tester);

        expect(find.text(es.vaultCompactionSettingsNothing), findsNothing);
        expect(find.textContaining('Se pueden recuperar'), findsOneWidget);
      });

      testWidgets('tocarla abre su pantalla, con el router real', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(harness.wrapWithAppRouter());
        await tester.pumpAndSettle();
        harness.goTo(RoutePaths.settings);
        await tester.pumpAndSettle();
        await fitWholeSettings(tester);

        await tester.tap(find.text(es.vaultCompactionSettingsTooltip));
        await tester.pumpAndSettle();

        expect(find.byType(VaultCompactionScreen), findsOneWidget);
        expect(find.text(es.vaultCompactionNothingLine), findsOneWidget);
      });
    });
  });
}
