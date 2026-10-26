import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';

/// Lo que dice una tarea de la IA de cuánto va (F39, paso 6).
void main() {
  final started = DateTime(2026, 10, 24, 10);

  AiTask task({
    List<AiTaskStepKind> steps = const [],
    Set<AiTaskStepKind> doneSteps = const {},
    AiTaskStepKind? currentStep,
    AiTaskProgress? batch,
    AiTaskProgress? part,
  }) => AiTask(
    id: 't',
    kind: AiTaskKind.studyAnalysis,
    title: 'Historia',
    startedAt: started,
    steps: steps,
    doneSteps: doneSteps,
    currentStep: currentStep,
    batchProgress: batch,
    partProgress: part,
  );

  AiTaskProgress parts(int done, int total) =>
      AiTaskProgress(done: done, total: total, unit: AiTaskUnit.part);

  group('el avance', () {
    test('por partes: las terminadas sobre el total de ahora', () {
      expect(task(part: parts(3, 12)).percent, 25);
      expect(task(part: parts(0, 12)).percent, 0);
      expect(task(part: parts(12, 12)).percent, 100);
    });

    test('la parte que va es la siguiente a la última terminada, sin pasarse '
        'del total', () {
      expect(parts(0, 12).current, 1);
      expect(parts(2, 12).current, 3);
      expect(parts(12, 12).current, 12);
      expect(parts(0, 0).current, 0);
    });

    test('sin saber cuántas son, cero por ciento y no una división por '
        'cero', () {
      expect(parts(0, 0).percent, 0);
      expect(task(part: parts(0, 0)).percent, 0);
    });

    test('por pasos: los terminados sobre los que tiene', () {
      final steps = [
        AiTaskStepKind.organizeProperties,
        AiTaskStepKind.organizeRelations,
        AiTaskStepKind.organizeFlashcards,
        AiTaskStepKind.organizeAtlas,
      ];

      expect(task(steps: steps).percent, 0);
      expect(
        task(
          steps: steps,
          currentStep: AiTaskStepKind.organizeFlashcards,
        ).percent,
        50,
      );
      expect(
        task(
          steps: steps,
          currentStep: AiTaskStepKind.organizeAtlas,
        ).progress?.unit,
        AiTaskUnit.step,
      );
    });

    test('sin partes ni pasos no se sabe cuánto va', () {
      expect(task().percent, isNull);
      expect(task().progress, isNull);
    });

    test('un pedido de varios elementos suma lo que va del elemento de ahora: '
        'el primero de cuatro, a la mitad, está en 12 y no en 0', () {
      const batch = AiTaskProgress(done: 0, total: 4, unit: AiTaskUnit.item);

      expect(task(batch: batch).percent, 0);
      expect(task(batch: batch, part: parts(1, 2)).percent, 12);
      expect(
        task(
          batch: const AiTaskProgress(done: 2, total: 4, unit: AiTaskUnit.item),
          steps: [AiTaskStepKind.reviewFlashcards, AiTaskStepKind.reviewThings],
          doneSteps: {AiTaskStepKind.reviewFlashcards},
        ).percent,
        62,
      );
    });

    test('el avance que se muestra es el del pedido entero antes que el de '
        'las partes', () {
      final both = task(
        batch: const AiTaskProgress(done: 1, total: 3, unit: AiTaskUnit.item),
        part: parts(5, 10),
      );

      expect(both.progress?.unit, AiTaskUnit.item);
      expect(both.progress?.current, 2);
    });
  });

  group('lo gastado', () {
    test('los tokens son los leídos más los escritos', () {
      final spent = task().copyWith(inputTokens: 900, outputTokens: 100);

      expect(spent.tokens, 1000);
    });

    test('lo que cuesta una tarea sin nada contado está vacío', () {
      expect(AiTaskUsage.none.isEmpty, isTrue);
      expect(const AiTaskUsage(inputTokens: 1).isEmpty, isFalse);
      expect(const AiTaskUsage(elapsed: Duration(seconds: 1)).isEmpty, isFalse);
      expect(const AiTaskUsage(inputTokens: 3, outputTokens: 4).tokens, 7);
    });

    test('el tiempo que lleva nunca es negativo', () {
      expect(
        task().elapsed(started.subtract(const Duration(seconds: 5))),
        Duration.zero,
      );
    });
  });

  test('dos tareas con lo mismo son iguales, y con otra cosa no', () {
    final a = task(steps: [AiTaskStepKind.studySplit], part: parts(1, 2));
    final b = task(steps: [AiTaskStepKind.studySplit], part: parts(1, 2));

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(a.copyWith(inputTokens: 1)));
    expect(a, isNot(a.copyWith(partProgress: () => parts(2, 2))));
    expect(a, isNot(a.copyWith(currentStep: () => AiTaskStepKind.studySplit)));
  });
}
