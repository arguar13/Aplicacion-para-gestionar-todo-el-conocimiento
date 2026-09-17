import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

class _MockOrganizeRepository extends Mock implements OrganizeRepository {}

class _MockCaptureItemUseCase extends Mock implements CaptureItemUseCase {}

/// Verifica que resaltar funcione de punta a punta desde el menú de
/// selección, no un botón aparte.
///
/// Esto reemplaza un diseño anterior —un botón que aparecía debajo de todo
/// el texto seleccionable— encontrado roto validando la app de punta a
/// punta: en cualquier contenido más largo que una pantalla, ese botón
/// quedaba a miles de píxeles de la selección real, invisible en la
/// práctica. `contextMenuBuilder` lo agrega al propio menú de
/// Copiar/Compartir, que Flutter ya posiciona junto a la selección.
void main() {
  setUpAll(() {
    registerFallbackValue(RelationKind.relatedTo);
  });

  late _MockOrganizeRepository repository;
  late _MockCaptureItemUseCase captureUseCase;

  setUp(() {
    repository = _MockOrganizeRepository();
    captureUseCase = _MockCaptureItemUseCase();
    when(
      () => repository.watchHighlightsForRendition(any()),
    ).thenAnswer((_) => Stream.value(const []));
  });

  Future<void> pumpHighlightableText(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          organizeRepositoryProvider.overrideWithValue(repository),
          captureItemUseCaseProvider.overrideWithValue(captureUseCase),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: HighlightableText(
              itemId: 'item-1',
              renditionId: 'rendition-1',
              content: 'Conocemos bien el amor y las reglas del juego.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'seleccionar texto y elegir Resaltar del menú crea el resaltado',
    (tester) async {
      when(
        () => repository.createHighlight(
          renditionId: any(named: 'renditionId'),
          startOffset: any(named: 'startOffset'),
          endOffset: any(named: 'endOffset'),
          excerpt: any(named: 'excerpt'),
          note: any(named: 'note'),
        ),
      ).thenAnswer(
        (_) async => right(
          Highlight(
            id: 'h1',
            renditionId: 'rendition-1',
            startOffset: 0,
            endOffset: 9,
            excerpt: 'Conocemos',
            createdAt: DateTime(2026),
          ),
        ),
      );

      await pumpHighlightableText(tester);

      // Selecciona la primera palabra ("Conocemos") y pide el menú de
      // selección, igual que hace Flutter internamente tras una
      // pulsación larga — es el mismo camino que usan las pruebas del
      // propio framework para ejercitar un `contextMenuBuilder` sin
      // depender de la geometría exacta de un gesto real.
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      state.userUpdateTextEditingValue(
        state.textEditingValue.copyWith(
          selection: const TextSelection(baseOffset: 0, extentOffset: 9),
        ),
        SelectionChangedCause.tap,
      );
      state.showToolbar();
      await tester.pumpAndSettle();

      // El menú de selección agrega "Highlight" junto a Copy/Share (en
      // inglés porque el `MaterialApp` de la prueba no fija un locale y el
      // entorno de test usa "en" por defecto).
      expect(find.text('Highlight'), findsOneWidget);

      await tester.tap(find.text('Highlight'));
      await tester.pumpAndSettle();

      // Confirma la nota vacía en el diálogo.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(
        () => repository.createHighlight(
          renditionId: 'rendition-1',
          startOffset: any(named: 'startOffset'),
          endOffset: any(named: 'endOffset'),
          excerpt: any(named: 'excerpt'),
        ),
      ).called(1);
    },
  );

  testWidgets('sin selección activa, el menú no ofrece Highlight', (
    tester,
  ) async {
    await pumpHighlightableText(tester);

    expect(find.text('Highlight'), findsNothing);
  });

  testWidgets('seleccionar texto y elegir Extract as note la crea vinculada al '
      'elemento actual', (tester) async {
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
      () =>
          captureUseCase.call(const CaptureRequest.text(rawInput: 'Conocemos')),
    ).thenAnswer((_) async => right(newItem));
    when(
      () => repository.createRelation(
        fromItemId: any(named: 'fromItemId'),
        toItemId: any(named: 'toItemId'),
        kind: any(named: 'kind'),
      ),
    ).thenAnswer((_) async => right(unit));

    await pumpHighlightableText(tester);

    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 9),
      ),
      SelectionChangedCause.tap,
    );
    state.showToolbar();
    await tester.pumpAndSettle();

    // En inglés, ídem "Highlight" más arriba — el entorno de test no fija
    // un locale.
    await tester.tap(find.text('Extract as note'));
    await tester.pumpAndSettle();

    verify(
      () => repository.createRelation(
        fromItemId: 'item-extracted',
        toItemId: 'item-1',
        kind: RelationKind.extractedFrom,
      ),
    ).called(1);
    expect(find.textContaining('Conocemos'), findsWidgets);
  });

  group('formato de Markdown', () {
    Future<void> pumpWithMarkdown(WidgetTester tester, String content) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            organizeRepositoryProvider.overrideWithValue(repository),
            captureItemUseCaseProvider.overrideWithValue(captureUseCase),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: HighlightableText(
                itemId: 'item-1',
                renditionId: 'rendition-1',
                content: content,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('se ve sin los símbolos de marcado', (tester) async {
      await pumpWithMarkdown(
        tester,
        '# Un título\n\nUn párrafo con **negrita** y una lista:\n- uno\n- dos',
      );

      expect(find.textContaining('#'), findsNothing);
      expect(find.textContaining('**'), findsNothing);
      expect(find.textContaining('Un título'), findsOneWidget);
      expect(find.textContaining('negrita'), findsOneWidget);
      expect(find.textContaining('• uno'), findsOneWidget);
    });

    testWidgets(
      'resaltar sobre una palabra en negrita guarda el fragmento crudo '
      'correcto',
      (tester) async {
        Map<Symbol, dynamic>? captured;
        when(
          () => repository.createHighlight(
            renditionId: any(named: 'renditionId'),
            startOffset: any(named: 'startOffset'),
            endOffset: any(named: 'endOffset'),
            excerpt: any(named: 'excerpt'),
            note: any(named: 'note'),
          ),
        ).thenAnswer((invocation) async {
          captured = invocation.namedArguments;
          return right(
            Highlight(
              id: 'h1',
              renditionId: 'rendition-1',
              startOffset: 0,
              endOffset: 0,
              excerpt: '',
              createdAt: DateTime(2026),
            ),
          );
        });

        // "Antes **negrita** después" -> se ve "Antes negrita después".
        // "negrita" ocupa del 5 al 12 en el texto renderizado, y del 8 al
        // 15 en el contenido crudo (después de "Antes **").
        await pumpWithMarkdown(tester, 'Antes **negrita** después');

        final state = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        state.userUpdateTextEditingValue(
          state.textEditingValue.copyWith(
            selection: const TextSelection(baseOffset: 6, extentOffset: 13),
          ),
          SelectionChangedCause.tap,
        );
        state.showToolbar();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Highlight'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured![#excerpt], 'negrita');
        expect(captured![#startOffset], 8);
        expect(captured![#endOffset], 15);
      },
    );
  });
}
