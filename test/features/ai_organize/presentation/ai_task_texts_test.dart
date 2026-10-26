import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/presentation/ai_task_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Cómo se dice lo que hace la IA ahora y lo que costó cada pasada (F39,
/// paso 6), sin dibujar nada.
void main() {
  final es = AppLocalizationsEs();
  final en = AppLocalizationsEn();
  final started = DateTime(2026, 10, 24, 10);

  group('una duración', () {
    test('en segundos hasta el minuto, con minutos y segundos hasta la hora, '
        'y con horas y minutos después', () {
      String text(Duration d) => aiDurationText(es, d);

      expect(text(Duration.zero), '0 s');
      expect(text(const Duration(seconds: 45)), '45 s');
      expect(text(const Duration(seconds: 59, milliseconds: 900)), '59 s');
      expect(text(const Duration(minutes: 1)), '1 min 0 s');
      expect(text(const Duration(minutes: 2, seconds: 14)), '2 min 14 s');
      expect(text(const Duration(minutes: 59, seconds: 59)), '59 min 59 s');
      expect(
        text(const Duration(hours: 1, minutes: 5, seconds: 40)),
        '1 h 5 min',
      );
      expect(text(const Duration(hours: 1)), '1 h 0 min');
      expect(text(const Duration(hours: 3)), '3 h 0 min');
    });

    test('nunca negativa', () {
      expect(aiDurationText(es, const Duration(seconds: -4)), '0 s');
    });
  });

  test('los tokens con el separador de miles de cada idioma', () {
    expect(aiTokenCount('es', 12340), '12.340');
    expect(aiTokenCount('es', 987), '987');
    expect(aiTokenCount('en', 12340), '12,340');
    expect(aiTokenCount('es', 0), '0');
  });

  group('qué hace la tarea', () {
    AiTask task(AiTaskKind kind, {String title = 'Historia'}) =>
        AiTask(id: 't', kind: kind, title: title, startedAt: started);

    test('cada clase dice lo suyo con el título', () {
      expect(
        aiTaskHeadline(es, task(AiTaskKind.studyAnalysis)),
        'Analizando «Historia» para estudiar',
      );
      expect(
        aiTaskHeadline(es, task(AiTaskKind.organize)),
        'Organizando «Historia»',
      );
      expect(
        aiTaskHeadline(es, task(AiTaskKind.flashcards)),
        'Creando tarjetas de «Historia»',
      );
      expect(
        aiTaskHeadline(es, task(AiTaskKind.review)),
        'Revisando «Historia» con otro modelo',
      );
      expect(
        aiTaskHeadline(en, task(AiTaskKind.studyAnalysis)),
        'Analyzing “Historia” to study',
      );
    });

    test(
      'un análisis sin título del documento no deja unas comillas vacías',
      () {
        expect(
          aiTaskHeadline(es, task(AiTaskKind.studyAnalysis, title: '  ')),
          'Analizando un texto para estudiar',
        );
      },
    );
  });

  test('cuánto va, en lo que se cuenta', () {
    String text(AiTaskUnit unit) =>
        aiProgressText(es, AiTaskProgress(done: 2, total: 12, unit: unit));

    expect(text(AiTaskUnit.part), 'Parte 3 de 12');
    expect(text(AiTaskUnit.step), 'Paso 3 de 12');
    expect(text(AiTaskUnit.item), 'Elemento 3 de 12');
  });

  test('todos los pasos tienen su nombre, distinto en cada uno', () {
    final labels = {
      for (final step in AiTaskStepKind.values) aiStepLabel(es, step),
    };

    expect(labels, hasLength(AiTaskStepKind.values.length));
    expect(labels, everyElement(isNotEmpty));
    expect(
      aiStepLabel(es, AiTaskStepKind.studySplit),
      'Partir el texto en partes',
    );
  });

  group('lo que costó una pasada', () {
    AiRun run({
      String? model = 'gemini-3.8-flash',
      Duration workTime = Duration.zero,
      int input = 0,
      int output = 0,
    }) => AiRun(
      id: 'r',
      itemId: 'a',
      itemTitle: 'Roma',
      startedAt: started,
      model: model,
      workTime: workTime,
      inputTokens: input,
      outputTokens: output,
    );

    test('con el modelo, el tiempo y los tokens', () {
      expect(
        aiRunCostText(
          es,
          'es',
          run(
            workTime: const Duration(minutes: 2, seconds: 14),
            input: 12000,
            output: 340,
          ),
        ),
        'Gemini 3.8 Flash · 2 min 14 s · 12.340 tokens',
      );
    });

    test('solo con lo que se sabe: el tiempo, o los tokens', () {
      expect(
        aiRunCostText(es, 'es', run(workTime: const Duration(seconds: 8))),
        'Gemini 3.8 Flash · 8 s',
      );
      expect(
        aiRunCostText(es, 'es', run(output: 1500, model: null)),
        '1.500 tokens',
      );
      expect(
        aiRunCostText(es, 'es', run(output: 1500, model: '  ')),
        '1.500 tokens',
      );
    });

    test('una pasada que no guardó nada no dice nada, ni un cero', () {
      expect(aiRunCostText(es, 'es', run()), isNull);
      expect(aiRunCostText(es, 'es', run(model: null)), isNull);
    });
  });
}
