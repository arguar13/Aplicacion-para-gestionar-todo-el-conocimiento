import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/study/domain/services/study_eta.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_progress_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Lo que dice la franja mientras analiza (F39): el porcentaje, cuánto falta,
/// el reintento y la clase de falla.
void main() {
  final es = AppLocalizationsEs();

  group('StudyProgress.percent', () {
    test('las partes hechas sobre el total', () {
      expect(const StudyProgress(partsDone: 0, partsTotal: 4).percent, 0);
      expect(const StudyProgress(partsDone: 1, partsTotal: 4).percent, 25);
      expect(const StudyProgress(partsDone: 3, partsTotal: 12).percent, 25);
      expect(const StudyProgress(partsDone: 4, partsTotal: 4).percent, 100);
    });

    test('sin saber cuántas son, cero; y nunca pasa de cien', () {
      expect(const StudyProgress(partsDone: 0, partsTotal: 0).percent, 0);
      expect(const StudyProgress(partsDone: 5, partsTotal: 4).percent, 100);
    });
  });

  group('StudyEta', () {
    late DateTime now;
    late StudyEta eta;

    setUp(() {
      now = DateTime(2026, 10, 23, 10);
      eta = StudyEta(clock: () => now);
    });

    test('sin partes hechas no inventa nada', () {
      eta.start();
      now = now.add(const Duration(minutes: 5));
      expect(
        eta.remaining(const StudyProgress(partsDone: 0, partsTotal: 10)),
        isNull,
      );
    });

    test('sin empezar tampoco', () {
      expect(
        eta.remaining(const StudyProgress(partsDone: 2, partsTotal: 10)),
        isNull,
      );
    });

    test('el ritmo de las hechas por las que faltan', () {
      eta.start();
      now = now.add(const Duration(seconds: 90));
      // 3 partes en 90 s: 30 s cada una; faltan 7.
      expect(
        eta.remaining(const StudyProgress(partsDone: 3, partsTotal: 10)),
        const Duration(seconds: 210),
      );
    });

    test(
      'si el total crece porque una parte no entró, la estimación crece',
      () {
        eta.start();
        now = now.add(const Duration(seconds: 60));
        expect(
          eta.remaining(const StudyProgress(partsDone: 2, partsTotal: 4)),
          const Duration(seconds: 60),
        );
        expect(
          eta.remaining(const StudyProgress(partsDone: 2, partsTotal: 6)),
          const Duration(seconds: 120),
        );
      },
    );

    test('al terminar, no falta nada', () {
      eta.start();
      now = now.add(const Duration(seconds: 60));
      expect(
        eta.remaining(const StudyProgress(partsDone: 4, partsTotal: 4)),
        isNull,
      );
    });

    test('volver a empezar descarta el ritmo anterior', () {
      eta.start();
      now = now.add(const Duration(minutes: 10));
      eta.start();
      now = now.add(const Duration(seconds: 10));
      expect(
        eta.remaining(const StudyProgress(partsDone: 1, partsTotal: 3)),
        const Duration(seconds: 20),
      );
    });
  });

  group('studyEtaText', () {
    test('menos de un minuto', () {
      expect(
        studyEtaText(es, const Duration(seconds: 40)),
        es.studyEtaLessThanMinute,
      );
    });

    test('en minutos, para arriba', () {
      expect(
        studyEtaText(es, const Duration(seconds: 61)),
        es.studyEtaMinutes(2),
      );
      expect(
        studyEtaText(es, const Duration(minutes: 3)),
        es.studyEtaMinutes(3),
      );
    });

    test('en horas y minutos', () {
      expect(
        studyEtaText(es, const Duration(minutes: 80)),
        es.studyEtaHours(1, 20),
      );
    });
  });

  group('studyRunningMessage', () {
    test('preparando, mientras no hay partes', () {
      expect(
        studyRunningMessage(es, const StudyAnalysisRunning(null)),
        es.studyPreparing,
      );
      expect(
        studyRunningMessage(
          es,
          const StudyAnalysisRunning(
            StudyProgress(partsDone: 0, partsTotal: 0),
          ),
        ),
        es.studyPreparing,
      );
    });

    test('la parte que va y el porcentaje, sin tiempo antes de la primera', () {
      expect(
        studyRunningMessage(
          es,
          const StudyAnalysisRunning(
            StudyProgress(partsDone: 0, partsTotal: 4),
          ),
        ),
        es.studyAnalyzingPercent(1, 4, 0),
      );
    });

    test('con el ritmo, suma cuánto falta', () {
      expect(
        studyRunningMessage(
          es,
          const StudyAnalysisRunning(
            StudyProgress(partsDone: 1, partsTotal: 4),
            remaining: Duration(minutes: 3),
          ),
        ),
        es.studyAnalyzingEta(2, 4, 25, es.studyEtaMinutes(3)),
      );
    });

    test('un reintento manda sobre el avance', () {
      final text = studyRunningMessage(
        es,
        const StudyAnalysisRunning(
          StudyProgress(partsDone: 1, partsTotal: 4),
          remaining: Duration(minutes: 3),
          retry: StudyRetry(
            attempt: 2,
            maxAttempts: 4,
            failure: CloudModelFailure.network,
          ),
        ),
      );
      expect(text, startsWith('Reintentando (2 de 4)'));
    });
  });

  group('studyFailedMessage', () {
    test('una falla de la nube dice qué pasó y qué hacer', () {
      for (final failure in CloudModelFailure.values) {
        final text = studyFailedMessage(
          es,
          StudyAnalysisFailed(CloudModelException(failure)),
        );
        expect(text, contains('Lo analizado quedó guardado'));
        expect(text, isNot(equals(es.studyFailed)));
      }
      expect(
        studyFailedMessage(
          es,
          const StudyAnalysisFailed(
            CloudModelException(CloudModelFailure.quotaExhausted),
          ),
        ),
        contains('cuota'),
      );
    });

    test('otra cosa, el aviso de siempre', () {
      expect(
        studyFailedMessage(es, StudyAnalysisFailed(StateError('sin memoria'))),
        es.studyFailed,
      );
    });
  });
}
