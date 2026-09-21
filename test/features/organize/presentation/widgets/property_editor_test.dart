import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show left, right, unit;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/property_editor.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

class MockOrganizeRepository extends Mock implements OrganizeRepository {}

/// Lo que el editor hace cuando el repositorio responde con un fallo. Con la
/// base real esos caminos no se pueden provocar; con un doble sí, y son los que
/// separan "no pasó nada" de "avisó que no pudo".
void main() {
  final es = AppLocalizationsEs();
  late MockOrganizeRepository organize;

  final now = DateTime(2026, 9, 11);
  final fecha = PropertyDefinition(
    id: 'def-fecha',
    name: kFechaDelHechoCategoryName,
    createdAt: now,
    type: PropertyValueType.date,
    isSystem: true,
  );
  final region = PropertyDefinition(
    id: 'def-region',
    name: 'Región',
    createdAt: now,
  );
  final item = KnowledgeItem(
    id: 'item-1',
    title: 'Un hecho',
    source: Source(id: 'src-1', kind: SourceKind.manualNote, capturedAt: now),
    processingState: ProcessingState.ready,
    createdAt: now,
    updatedAt: now,
  );

  setUpAll(() {
    registerFallbackValue(
      const HistoricalDate(year: 1, precision: DatePrecision.year),
    );
  });

  setUp(() {
    organize = MockOrganizeRepository();
    when(
      organize.watchAllPropertyDefinitions,
    ).thenAnswer((_) => Stream.value([fecha, region]));
    when(
      () => organize.watchPropertyValues(any()),
    ).thenAnswer((_) => Stream.value(const []));
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [organizeRepositoryProvider.overrideWithValue(organize)],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: PropertyEditor(item: item)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addDate(WidgetTester tester, String year) async {
    await tester.tap(find.text(es.detailAddProperty));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, es.detailPropertyCategoryHint),
      kFechaDelHechoCategoryName,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, es.datePickerYear),
      year,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, es.detailAddProperty));
    await tester.pumpAndSettle();
  }

  void stubDateValue() {
    when(
      () => organize.getOrCreateHistoricalPropertyValue(
        definitionId: any(named: 'definitionId'),
        date: any(named: 'date'),
      ),
    ).thenAnswer(
      (_) async => right(
        PropertyValue(
          id: 'value-476',
          definitionId: fecha.id,
          value: '476',
          createdAt: now,
        ),
      ),
    );
  }

  group('fecha', () {
    testWidgets('pide el valor con la fecha completa y lo asigna a la '
        'categoría', (tester) async {
      stubDateValue();
      when(
        () => organize.assignProperty(
          itemId: any(named: 'itemId'),
          definitionId: any(named: 'definitionId'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async => right(unit));
      await pumpEditor(tester);

      await addDate(tester, '476');

      verify(
        () => organize.getOrCreateHistoricalPropertyValue(
          definitionId: fecha.id,
          date: const HistoricalDate(year: 476, precision: DatePrecision.year),
        ),
      ).called(1);
      verify(
        () => organize.assignProperty(
          itemId: item.id,
          definitionId: fecha.id,
          value: '476',
        ),
      ).called(1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('no toca la categoría de texto ni crea un valor suelto', (
      tester,
    ) async {
      stubDateValue();
      when(
        () => organize.assignProperty(
          itemId: any(named: 'itemId'),
          definitionId: any(named: 'definitionId'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async => right(unit));
      await pumpEditor(tester);

      await addDate(tester, '476');

      verifyNever(() => organize.getOrCreatePropertyDefinition(any()));
    });

    testWidgets('si no se puede crear el valor de fecha, avisa', (
      tester,
    ) async {
      when(
        () => organize.getOrCreateHistoricalPropertyValue(
          definitionId: any(named: 'definitionId'),
          date: any(named: 'date'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.unexpected(message: 'sin base')),
      );
      await pumpEditor(tester);

      await addDate(tester, '476');

      expect(find.text(es.globalErrorUnexpected), findsOneWidget);
      verifyNever(
        () => organize.assignProperty(
          itemId: any(named: 'itemId'),
          definitionId: any(named: 'definitionId'),
          value: any(named: 'value'),
        ),
      );
    });

    testWidgets('si no se puede asignar la fecha al elemento, avisa', (
      tester,
    ) async {
      stubDateValue();
      when(
        () => organize.assignProperty(
          itemId: any(named: 'itemId'),
          definitionId: any(named: 'definitionId'),
          value: any(named: 'value'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.unexpected(message: 'sin base')),
      );
      await pumpEditor(tester);

      await addDate(tester, '476');

      expect(find.text(es.globalErrorUnexpected), findsOneWidget);
    });
  });

  group('texto', () {
    Future<void> addText(WidgetTester tester) async {
      await tester.tap(find.text(es.detailAddProperty));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, es.detailPropertyCategoryHint),
        'Época',
      );
      await tester.enterText(
        find.widgetWithText(TextField, es.detailPropertyValueHint),
        'Antigüedad',
      );
      await tester.tap(find.widgetWithText(TextButton, es.detailAddProperty));
      await tester.pumpAndSettle();
    }

    testWidgets('si no se puede crear la categoría, avisa', (tester) async {
      when(() => organize.getOrCreatePropertyDefinition(any())).thenAnswer(
        (_) async => left(const Failure.unexpected(message: 'sin base')),
      );
      await pumpEditor(tester);

      await addText(tester);

      expect(find.text(es.globalErrorUnexpected), findsOneWidget);
    });

    testWidgets('si no se puede asignar el valor, avisa', (tester) async {
      when(() => organize.getOrCreatePropertyDefinition(any())).thenAnswer(
        (_) async => right(
          PropertyDefinition(id: 'def-epoca', name: 'Época', createdAt: now),
        ),
      );
      when(
        () => organize.assignProperty(
          itemId: any(named: 'itemId'),
          definitionId: any(named: 'definitionId'),
          value: any(named: 'value'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.unexpected(message: 'sin base')),
      );
      await pumpEditor(tester);

      await addText(tester);

      expect(find.text(es.globalErrorUnexpected), findsOneWidget);
    });

    testWidgets(
      'no ofrece la categoría de las personas: se cargan en los datos '
      'bibliográficos de la fuente',
      (tester) async {
        final autor = PropertyDefinition(
          id: 'def-autor',
          name: 'Autor',
          createdAt: now,
          type: PropertyValueType.person,
          isSystem: true,
        );
        when(
          organize.watchAllPropertyDefinitions,
        ).thenAnswer((_) => Stream.value([autor, fecha, region]));
        await pumpEditor(tester);
        await tester.tap(find.text(es.detailAddProperty));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, es.detailPropertyCategoryHint),
          'Au',
        );
        await tester.pumpAndSettle();
        // Y con un texto que sí encuentra una, la ofrece: el control.
        expect(find.text('Autor'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextField, es.detailPropertyCategoryHint),
          'Reg',
        );
        await tester.pumpAndSettle();
        expect(find.text('Región'), findsWidgets);
      },
    );

    testWidgets('si sale bien, no hay ningún aviso', (tester) async {
      when(() => organize.getOrCreatePropertyDefinition(any())).thenAnswer(
        (_) async => right(
          PropertyDefinition(id: 'def-epoca', name: 'Época', createdAt: now),
        ),
      );
      when(
        () => organize.assignProperty(
          itemId: any(named: 'itemId'),
          definitionId: any(named: 'definitionId'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async => right(unit));
      await pumpEditor(tester);

      await addText(tester);

      expect(find.byType(SnackBar), findsNothing);
      verify(
        () => organize.assignProperty(
          itemId: item.id,
          definitionId: 'def-epoca',
          value: 'Antigüedad',
        ),
      ).called(1);
    });
  });
}
