import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_item_reviewer.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';

/// Un revisor que contesta [report] y anota con qué lo llamaron.
class _Reviewer implements AiItemReviewer {
  _Reviewer(this.report, {this.onReview});

  final AiStepReport report;

  /// Qué mira la prueba mientras revisa.
  final void Function()? onReview;
  final calls =
      <({String item, String runId, String? model, String? except})>[];

  @override
  Future<AiStepReport> review(
    KnowledgeItem item, {
    required String runId,
    String? model,
    String? exceptMadeBy,
  }) async {
    onReview?.call();
    calls.add((
      item: item.id,
      runId: runId,
      model: model,
      except: exceptMadeBy,
    ));
    return report;
  }
}

void main() {
  final item = KnowledgeItem(
    id: 'a',
    title: 'Rayuela',
    source: Source(
      id: 'src-a',
      kind: SourceKind.webPage,
      capturedAt: DateTime(2026, 10, 17),
    ),
    processingState: ProcessingState.ready,
    createdAt: DateTime(2026, 10, 17),
    updatedAt: DateTime(2026, 10, 17),
  );

  test('las tarjetas y lo demás, uno detrás del otro, con lo mismo; lo que '
      'proponen se suma', () async {
    final cards = _Reviewer(const AiStepReport(forReview: 2));
    final things = _Reviewer(const AiStepReport(applied: 1, forReview: 3));

    final report = await AiItemReviewers([
      cards,
      things,
    ]).review(item, runId: 'run', model: 'gemini', exceptMadeBy: 'Gemma');

    expect(report, const AiStepReport(applied: 1, forReview: 5));
    for (final reviewer in [cards, things]) {
      expect(reviewer.calls, [
        (item: 'a', runId: 'run', model: 'gemini', except: 'Gemma'),
      ]);
    }
  });

  test('con sus pasos, le dice a la tarea en curso cuál de los dos va y cuál '
      'terminó (F39)', () async {
    final tracker = AiTaskTracker(clock: () => DateTime(2026, 10, 24));
    addTearDown(tracker.dispose);
    final task = tracker.begin(
      kind: AiTaskKind.review,
      title: 'Rayuela',
      steps: const [
        AiTaskStepKind.reviewFlashcards,
        AiTaskStepKind.reviewThings,
      ],
    );
    final seen = <AiTaskStepKind?>[];
    void look() => seen.add(tracker.tasks.value.single.currentStep);
    final reviewers = AiItemReviewers(
      [
        _Reviewer(AiStepReport.nothing, onReview: look),
        _Reviewer(AiStepReport.nothing, onReview: look),
      ],
      steps: const [
        AiTaskStepKind.reviewFlashcards,
        AiTaskStepKind.reviewThings,
      ],
    );

    await task.run(() => reviewers.review(item, runId: 'run'));

    expect(seen, [
      AiTaskStepKind.reviewFlashcards,
      AiTaskStepKind.reviewThings,
    ]);
    final after = tracker.tasks.value.single;
    expect(
      after.stateOf(AiTaskStepKind.reviewFlashcards),
      AiTaskStepState.done,
    );
    expect(after.stateOf(AiTaskStepKind.reviewThings), AiTaskStepState.done);
    expect(after.percent, 100);
  });

  test('sin tarea en curso, los pasos no hacen nada ni fallan', () async {
    final reviewers = AiItemReviewers(
      [_Reviewer(const AiStepReport(forReview: 1))],
      steps: const [AiTaskStepKind.reviewFlashcards],
    );

    expect(
      await reviewers.review(item, runId: 'run'),
      const AiStepReport(forReview: 1),
    );
  });

  test('sin revisores, nada', () async {
    expect(
      await const AiItemReviewers([]).review(item, runId: 'run'),
      AiStepReport.nothing,
    );
  });
}
