import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';

import '../../../../support/read_aloud_test_support.dart';

class _MockOrganizeRepository extends Mock implements OrganizeRepository {}

class _MockCaptureItemUseCase extends Mock implements CaptureItemUseCase {}

/// Un lector flotante que solo anota qué le pidieron leer.
class _RecordingReadAloud extends FakeReadAloudController {
  ReadableDocument? opened;

  @override
  Future<void> open(ReadableDocument document, {int fromSegment = 0}) async {
    opened = document;
  }
}

/// Verifica que resaltar funcione de punta a punta desde la barrita que
/// aparece junto a la selección (F38), no un botón aparte.
///
/// Esto reemplaza un diseño anterior —un botón que aparecía debajo de todo el
/// texto seleccionable— encontrado roto validando la app de punta a punta: en
/// cualquier contenido más largo que una pantalla, ese botón quedaba a miles
/// de píxeles de la selección real, invisible en la práctica.
/// `contextMenuBuilder` lo agrega junto a la selección, que Flutter ya
/// posiciona.
void main() {
  final en = AppLocalizationsEn();
  const content = 'Conocemos bien el amor y las reglas del juego.';

  setUpAll(() {
    registerFallbackValue(RelationKind.relatedTo);
    registerFallbackValue(HighlightStyle.fill);
  });

  late _MockOrganizeRepository repository;
  late _MockCaptureItemUseCase captureUseCase;

  /// El texto pregunta si el lector flotante lo está leyendo (F25), y el
  /// lector arranca con la voz y la velocidad guardadas.
  late SharedPreferences prefs;

  /// Lo que se guardó con `createHighlight`, en orden.
  late List<Map<Symbol, dynamic>> created;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repository = _MockOrganizeRepository();
    captureUseCase = _MockCaptureItemUseCase();
    created = [];
    when(
      () => repository.watchHighlightsForRendition(any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => repository.createHighlight(
        renditionId: any(named: 'renditionId'),
        startOffset: any(named: 'startOffset'),
        endOffset: any(named: 'endOffset'),
        excerpt: any(named: 'excerpt'),
        note: any(named: 'note'),
        color: any(named: 'color'),
        style: any(named: 'style'),
      ),
    ).thenAnswer((invocation) async {
      created.add(invocation.namedArguments);
      return right(_highlight('h-new'));
    });
  });

  Future<void> pumpText(
    WidgetTester tester, {
    String text = content,
    List<Highlight> highlights = const [],
    List<PaintedRange> paints = const [],
    ThemeData? theme,
    List<Override> overrides = const [],
  }) async {
    when(
      () => repository.watchHighlightsForRendition(any()),
    ).thenAnswer((_) => Stream.value(highlights));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          organizeRepositoryProvider.overrideWithValue(repository),
          captureItemUseCaseProvider.overrideWithValue(captureUseCase),
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
        ],
        child: MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HighlightableText(
                itemId: 'item-1',
                renditionId: 'rendition-1',
                content: text,
                paints: paints,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Selecciona `[base, extent)` y abre el menú, igual que hace Flutter
  /// internamente tras una pulsación larga: el mismo camino que usan las
  /// pruebas del propio framework para ejercitar un `contextMenuBuilder` sin
  /// depender de la geometría exacta de un gesto real.
  Future<void> select(WidgetTester tester, int base, int extent) async {
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection(baseOffset: base, extentOffset: extent),
      ),
      SelectionChangedCause.tap,
    );
    state.showToolbar();
    await tester.pumpAndSettle();
  }

  /// Un toque sin arrastrar en la posición [offset] del texto: el mismo
  /// camino que recorre Flutter con un toque de verdad.
  Future<void> tapAt(WidgetTester tester, int offset) async {
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection.collapsed(offset: offset),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pumpAndSettle();
  }

  Finder color(HighlightColor color) =>
      find.byKey(Key('highlight-color-${color.name}'));

  /// Los tramos del texto con su fondo, su línea y su letra.
  List<(String, Color?, Color?)> pieces(WidgetTester tester) => [
    for (final span
        in tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textSpan!
            .children!
            .cast<TextSpan>())
      (
        span.text!,
        span.style?.backgroundColor,
        span.style?.decoration == TextDecoration.underline
            ? span.style?.decorationColor
            : null,
      ),
  ];

  group('la barrita de resaltado', () {
    testWidgets('aparece al seleccionar, junto a la selección', (tester) async {
      await pumpText(tester);
      expect(find.byType(HighlightToolbar), findsNothing);

      await select(tester, 0, 9);

      expect(find.byType(HighlightToolbar), findsOneWidget);
      for (final highlightColor in HighlightColor.values) {
        expect(color(highlightColor), findsOneWidget);
      }
      for (final tooltip in [
        en.highlightCopy,
        en.highlightListen,
        en.highlightAddNote,
        en.detailExtractSelection,
        en.flashcardsFromSelection,
      ]) {
        expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      }
    });

    testWidgets('cada color crea el resaltado con ese color, de fondo y con '
        'el fragmento exacto, sin pedir nota', (tester) async {
      await pumpText(tester);

      for (final highlightColor in HighlightColor.values) {
        await select(tester, 0, 9);
        await tester.tap(color(highlightColor));
        await tester.pumpAndSettle();
      }

      expect([for (final c in created) c[#color]], HighlightColor.values);
      for (final c in created) {
        expect(c[#style], HighlightStyle.fill);
        expect(c[#renditionId], 'rendition-1');
        expect(c[#startOffset], 0);
        expect(c[#endOffset], 9);
        expect(c[#excerpt], 'Conocemos');
        expect(c[#note], isNull);
      }
      // Sin diálogo de nota de por medio, y la barrita se fue.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(HighlightToolbar), findsNothing);
    });

    testWidgets('Subrayar crea un subrayado con una línea, con el primer '
        'color si no se eligió ninguno', (tester) async {
      await pumpText(tester);
      await select(tester, 0, 9);

      expect(
        find.byTooltip(
          en.highlightUnderlineWithColor(en.highlightColorLightYellow),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('highlight-underline')));
      await tester.pumpAndSettle();

      expect(created, hasLength(1));
      expect(created.single[#style], HighlightStyle.underline);
      expect(created.single[#color], HighlightColor.lightYellow);
      expect(created.single[#excerpt], 'Conocemos');
    });

    testWidgets('Subrayar usa el último color que se eligió', (tester) async {
      await pumpText(tester);
      await select(tester, 0, 9);
      await tester.tap(color(HighlightColor.violet));
      await tester.pumpAndSettle();

      await select(tester, 10, 14);
      expect(
        find.byTooltip(en.highlightUnderlineWithColor(en.highlightColorViolet)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('highlight-underline')));
      await tester.pumpAndSettle();

      expect(created.last[#color], HighlightColor.violet);
      expect(created.last[#style], HighlightStyle.underline);
      expect(created.last[#excerpt], 'bien');
    });

    testWidgets('Subrayar con un color deja ese color como el último', (
      tester,
    ) async {
      await pumpText(tester);
      await select(tester, 0, 9);
      await tester.tap(find.byKey(const Key('highlight-underline')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HighlightableText)),
      );

      expect(
        container.read(lastHighlightColorProvider),
        HighlightColor.lightYellow,
      );
      await select(tester, 0, 9);
      await tester.tap(color(HighlightColor.turquoise));
      await tester.pumpAndSettle();

      expect(
        container.read(lastHighlightColorProvider),
        HighlightColor.turquoise,
      );
    });

    testWidgets('Nota pide la nota y resalta con el último color', (
      tester,
    ) async {
      await pumpText(tester);
      await select(tester, 0, 9);
      await tester.tap(color(HighlightColor.orange));
      await tester.pumpAndSettle();

      await select(tester, 10, 14);
      await tester.tap(find.byTooltip(en.highlightAddNote));
      await tester.pumpAndSettle();
      expect(created, hasLength(1), reason: 'todavía falta la nota');
      await tester.enterText(find.byType(TextField), 'por qué');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(created, hasLength(2));
      expect(created.last[#note], 'por qué');
      expect(created.last[#color], HighlightColor.orange);
      expect(created.last[#style], HighlightStyle.fill);
      expect(created.last[#excerpt], 'bien');
    });

    testWidgets('cancelar la nota no resalta nada', (tester) async {
      await pumpText(tester);
      await select(tester, 0, 9);

      await tester.tap(find.byTooltip(en.highlightAddNote));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(created, isEmpty);
    });

    testWidgets('una nota en blanco resalta igual, sin nota', (tester) async {
      await pumpText(tester);
      await select(tester, 0, 9);

      await tester.tap(find.byTooltip(en.highlightAddNote));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(created, hasLength(1));
      expect(created.single[#note], isNull);
    });

    testWidgets('Copiar deja lo seleccionado en el portapapeles', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpText(tester);
      await select(tester, 0, 9);

      await tester.tap(find.byTooltip(en.highlightCopy));
      await tester.pumpAndSettle();

      expect(copied, 'Conocemos');
      expect(find.byType(HighlightToolbar), findsNothing);
    });

    testWidgets('Escuchar lee en voz alta lo seleccionado', (tester) async {
      await pumpText(
        tester,
        overrides: [
          readAloudControllerProvider.overrideWith(_RecordingReadAloud.new),
        ],
      );
      await select(tester, 0, 9);

      await tester.tap(find.byTooltip(en.highlightListen));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HighlightableText)),
      );
      final reader =
          container.read(readAloudControllerProvider.notifier)
              as _RecordingReadAloud;
      expect(
        reader.opened?.segments.map((s) => s.spoken).join(' '),
        'Conocemos',
      );
      expect(find.byType(HighlightToolbar), findsNothing);
    });

    testWidgets('Extraer como nota la crea vinculada al elemento actual, con '
        'el lugar de donde salió', (tester) async {
      final newItem = KnowledgeItem(
        id: 'item-extracted',
        title: 'Conocemos',
        source: Source(
          id: 'src-extracted',
          kind: SourceKind.manualNote,
          capturedAt: DateTime(2026),
        ),
        processingState: ProcessingState.ready,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      when(
        () => captureUseCase.call(
          const CaptureRequest.text(rawInput: 'Conocemos'),
        ),
      ).thenAnswer((_) async => right(newItem));
      when(
        () => repository.createRelation(
          fromItemId: any(named: 'fromItemId'),
          toItemId: any(named: 'toItemId'),
          kind: any(named: 'kind'),
          sourceCharStart: any(named: 'sourceCharStart'),
          sourceCharEnd: any(named: 'sourceCharEnd'),
        ),
      ).thenAnswer((_) async => right(unit));
      await pumpText(tester);
      await select(tester, 0, 9);

      await tester.tap(find.byTooltip(en.detailExtractSelection));
      await tester.pumpAndSettle();

      // Guarda de dónde de la fuente salió el fragmento: "Conocemos" son los
      // primeros nueve caracteres.
      verify(
        () => repository.createRelation(
          fromItemId: 'item-extracted',
          toItemId: 'item-1',
          kind: RelationKind.extractedFrom,
          sourceCharStart: 0,
          sourceCharEnd: 9,
        ),
      ).called(1);
      expect(find.textContaining('Conocemos'), findsWidgets);
    });

    testWidgets('Hacer tarjeta pide la pregunta, con el fragmento como '
        'respuesta', (tester) async {
      await pumpText(tester);
      await select(tester, 0, 9);

      await tester.tap(find.byTooltip(en.flashcardsFromSelection));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Conocemos'), findsOneWidget);
    });

    testWidgets('lo de siempre sigue a mano detrás de «Más opciones»: '
        'compartir, seleccionar todo y buscar en la web', (tester) async {
      await pumpText(tester);
      await select(tester, 0, 9);

      await tester.tap(find.byTooltip(en.highlightMore));
      await tester.pumpAndSettle();

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      expect(find.text('Search Web'), findsOneWidget);
    });

    testWidgets('resaltar sobre una palabra en negrita guarda el fragmento '
        'crudo correcto', (tester) async {
      // "Antes **negrita** después" -> se ve "Antes negrita después".
      // "negrita" ocupa del 6 al 13 en el texto renderizado, y del 8 al 15
      // en el contenido crudo (después de "Antes **").
      await pumpText(tester, text: 'Antes **negrita** después');
      await select(tester, 6, 13);

      await tester.tap(color(HighlightColor.turquoise));
      await tester.pumpAndSettle();

      expect(created.single[#excerpt], 'negrita');
      expect(created.single[#startOffset], 8);
      expect(created.single[#endOffset], 15);
      expect(created.single[#color], HighlightColor.turquoise);
    });
  });

  group('la ficha de un resaltado', () {
    final amor = content.indexOf('amor');

    Highlight amorHighlight({
      HighlightColor? color,
      HighlightStyle style = HighlightStyle.fill,
      String? note,
    }) => Highlight(
      id: 'h1',
      renditionId: 'rendition-1',
      startOffset: amor,
      endOffset: amor + 4,
      excerpt: 'amor',
      createdAt: DateTime.utc(2026),
      color: color,
      style: style,
      note: note,
    );

    setUp(() {
      when(
        () => repository.updateHighlightLook(
          id: any(named: 'id'),
          color: any(named: 'color'),
          style: any(named: 'style'),
        ),
      ).thenAnswer((_) async => right(_highlight('h1')));
      when(
        () => repository.updateHighlightNote(
          id: any(named: 'id'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => right(_highlight('h1')));
      when(
        () => repository.deleteHighlight(any()),
      ).thenAnswer((_) async => right(unit));
    });

    testWidgets('tocar algo ya resaltado la abre', (tester) async {
      await pumpText(tester, highlights: [amorHighlight(note: 'clave')]);

      await tapAt(tester, amor + 2);

      expect(find.text(en.highlightCardTitle), findsOneWidget);
      expect(find.text('clave'), findsWidgets);
    });

    testWidgets('un toque justo al final del resaltado también la abre: la '
        'mitad de la última letra cae en su borde', (tester) async {
      await pumpText(tester, highlights: [amorHighlight()]);

      await tapAt(tester, amor + 4);

      expect(find.text(en.highlightCardTitle), findsOneWidget);
    });

    testWidgets('si dos se tocan, abre el que rodea el toque y no el que '
        'termina justo ahí', (tester) async {
      await pumpText(
        tester,
        highlights: [
          Highlight(
            id: 'izquierda',
            renditionId: 'rendition-1',
            startOffset: amor,
            endOffset: amor + 2,
            excerpt: 'am',
            createdAt: DateTime.utc(2026),
          ),
          Highlight(
            id: 'derecha',
            renditionId: 'rendition-1',
            startOffset: amor + 1,
            endOffset: amor + 4,
            excerpt: 'mor',
            createdAt: DateTime.utc(2026),
          ),
        ],
      );

      await tapAt(tester, amor + 2);
      await tester.tap(find.byKey(const Key('card-color-orange')));
      await tester.pumpAndSettle();

      verify(
        () => repository.updateHighlightLook(
          id: 'derecha',
          color: HighlightColor.orange,
          style: HighlightStyle.fill,
        ),
      ).called(1);
    });

    testWidgets('tocar lo que no está resaltado no abre nada', (tester) async {
      await pumpText(tester, highlights: [amorHighlight()]);

      await tapAt(tester, 3);

      expect(find.text(en.highlightCardTitle), findsNothing);
    });

    testWidgets('eligiendo palabras clave, un toque es para elegirlas: no abre '
        'la ficha', (tester) async {
      await pumpText(tester, highlights: [amorHighlight()]);
      ProviderScope.containerOf(
        tester.element(find.byType(HighlightableText)),
      ).read(studyViewProvider('rendition-1').notifier).state = const StudyView(
        picking: true,
      );

      await tapAt(tester, amor + 2);

      expect(find.text(en.highlightCardTitle), findsNothing);
    });

    testWidgets('cambiarle el color lo guarda, con el estilo que tenía', (
      tester,
    ) async {
      await pumpText(
        tester,
        highlights: [
          amorHighlight(
            color: HighlightColor.violet,
            style: HighlightStyle.underline,
          ),
        ],
      );
      await tapAt(tester, amor + 2);

      await tester.tap(find.byKey(const Key('card-color-turquoise')));
      await tester.pumpAndSettle();

      verify(
        () => repository.updateHighlightLook(
          id: 'h1',
          color: HighlightColor.turquoise,
          style: HighlightStyle.underline,
        ),
      ).called(1);
    });

    testWidgets('pasarlo a subrayado lo guarda, con el color que tenía', (
      tester,
    ) async {
      await pumpText(
        tester,
        highlights: [amorHighlight(color: HighlightColor.orange)],
      );
      await tapAt(tester, amor + 2);

      await tester.tap(find.text(en.highlightStyleUnderline));
      await tester.pumpAndSettle();

      verify(
        () => repository.updateHighlightLook(
          id: 'h1',
          color: HighlightColor.orange,
          style: HighlightStyle.underline,
        ),
      ).called(1);
    });

    testWidgets('escribirle la nota la guarda, sin tocar cómo se ve', (
      tester,
    ) async {
      await pumpText(tester, highlights: [amorHighlight()]);
      await tapAt(tester, amor + 2);

      await tester.enterText(find.byType(TextField), 'ojo con esto');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(
        () => repository.updateHighlightNote(id: 'h1', note: 'ojo con esto'),
      ).called(1);
      verifyNever(
        () => repository.updateHighlightLook(
          id: any(named: 'id'),
          color: any(named: 'color'),
          style: any(named: 'style'),
        ),
      );
    });

    testWidgets('quitarlo lo borra', (tester) async {
      await pumpText(tester, highlights: [amorHighlight()]);
      await tapAt(tester, amor + 2);

      await tester.tap(find.text(en.detailRemoveHighlight));
      await tester.pumpAndSettle();

      verify(() => repository.deleteHighlight('h1')).called(1);
      expect(find.text(en.highlightCardTitle), findsNothing);
    });
  });

  group('cómo se pinta', () {
    final amor = content.indexOf('amor');
    Highlight at(
      int start,
      int end, {
      HighlightColor? color,
      HighlightStyle style = HighlightStyle.fill,
    }) => Highlight(
      id: 'h$start',
      renditionId: 'rendition-1',
      startOffset: start,
      endOffset: end,
      excerpt: content.substring(start, end),
      createdAt: DateTime.utc(2026),
      color: color,
      style: style,
    );

    testWidgets('cada uno con su color; el de antes, sin color, con el de '
        'siempre', (tester) async {
      await pumpText(
        tester,
        highlights: [
          at(0, 9, color: HighlightColor.violet),
          at(amor, amor + 4),
        ],
      );
      final context = tester.element(find.byType(HighlightableText));

      expect(pieces(tester), [
        (
          'Conocemos',
          HighlightPalette.resolve(context, HighlightColor.violet),
          null,
        ),
        (' bien el ', null, null),
        ('amor', Theme.of(context).colorScheme.tertiaryContainer, null),
        (' y las reglas del juego.', null, null),
      ]);
    });

    testWidgets('un subrayado se pinta con una línea del color, sin fondo', (
      tester,
    ) async {
      await pumpText(
        tester,
        highlights: [
          at(
            amor,
            amor + 4,
            color: HighlightColor.orange,
            style: HighlightStyle.underline,
          ),
        ],
      );
      final context = tester.element(find.byType(HighlightableText));

      final underlined = pieces(tester).firstWhere((p) => p.$1 == 'amor');
      expect(underlined.$2, isNull);
      expect(
        underlined.$3,
        HighlightPalette.line(context, HighlightColor.orange),
      );
      final style = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .children!
          .cast<TextSpan>()
          .firstWhere((s) => s.text == 'amor')
          .style!;
      expect(style.decorationThickness, greaterThanOrEqualTo(2));
    });

    testWidgets('en el tema oscuro, los tonos del tema oscuro', (tester) async {
      await pumpText(
        tester,
        theme: ThemeData.dark(),
        highlights: [at(0, 9, color: HighlightColor.turquoise)],
      );

      expect(
        pieces(tester).first.$2,
        HighlightPalette.dark[HighlightColor.turquoise],
      );
    });

    testWidgets('las capas de lo estudiado (F36) se pintan con los '
        'subrayados: la oración debajo, la palabra clave encima', (
      tester,
    ) async {
      const green = Color(0xFFC8F2C2);
      const pink = Color(0xFFFFB3D9);
      await pumpText(
        tester,
        highlights: [at(amor, amor + 4, color: HighlightColor.orange)],
        paints: [
          const PaintedRange(0, content.length, background: green),
          PaintedRange(
            amor,
            amor + 2,
            background: pink,
            bold: true,
            aboveHighlights: true,
          ),
        ],
      );
      final context = tester.element(find.byType(HighlightableText));

      expect(pieces(tester).map((p) => (p.$1, p.$2)), [
        ('Conocemos bien el ', green),
        ('am', pink),
        ('or', HighlightPalette.resolve(context, HighlightColor.orange)),
        (' y las reglas del juego.', green),
      ]);
    });

    testWidgets('un subrayado se suma a la oración sin taparla', (
      tester,
    ) async {
      const green = Color(0xFFC8F2C2);
      await pumpText(
        tester,
        highlights: [
          at(
            amor,
            amor + 4,
            color: HighlightColor.violet,
            style: HighlightStyle.underline,
          ),
        ],
        paints: [const PaintedRange(0, content.length, background: green)],
      );
      final context = tester.element(find.byType(HighlightableText));

      expect(pieces(tester).firstWhere((p) => p.$1 == 'amor'), (
        'amor',
        green,
        HighlightPalette.line(context, HighlightColor.violet),
      ));
    });

    testWidgets('lo que se lee en voz alta va por encima de lo subrayado', (
      tester,
    ) async {
      await pumpText(
        tester,
        highlights: [at(0, content.length, color: HighlightColor.orange)],
        overrides: [
          readAloudHighlightProvider(
            'rendition-1',
          ).overrideWithValue((amor, amor + 4)),
        ],
      );
      final context = tester.element(find.byType(HighlightableText));

      expect(pieces(tester).map((p) => (p.$1, p.$2)), [
        (
          'Conocemos bien el ',
          HighlightPalette.resolve(context, HighlightColor.orange),
        ),
        ('amor', RenderedMarkdown.playingColor),
        (
          ' y las reglas del juego.',
          HighlightPalette.resolve(context, HighlightColor.orange),
        ),
      ]);
    });

    testWidgets('un resaltado cuyo rango ya no entra en el texto no se '
        'pinta', (tester) async {
      await pumpText(
        tester,
        highlights: [
          at(0, 9, color: HighlightColor.violet),
          _outOfRange(),
        ],
      );

      expect(pieces(tester).where((p) => p.$2 != null), hasLength(1));
    });

    testWidgets('la lista de abajo lleva el color y el estilo de cada uno', (
      tester,
    ) async {
      await pumpText(
        tester,
        highlights: [
          at(0, 9, color: HighlightColor.violet),
          at(amor, amor + 4, style: HighlightStyle.underline),
        ],
      );

      expect(find.byIcon(Icons.highlight), findsOneWidget);
      expect(find.byIcon(Icons.format_underlined), findsOneWidget);
    });
  });
}

Highlight _highlight(String id) => Highlight(
  id: id,
  renditionId: 'rendition-1',
  startOffset: 0,
  endOffset: 9,
  excerpt: 'Conocemos',
  createdAt: DateTime(2026),
);

Highlight _outOfRange() => Highlight(
  id: 'fuera',
  renditionId: 'rendition-1',
  startOffset: 10,
  endOffset: 900,
  excerpt: 'ya no existe',
  createdAt: DateTime(2026),
);
