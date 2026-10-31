import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_generators.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

class _Generator extends CreationGenerator {
  const _Generator(this.kind);

  @override
  final StudyCreationKind kind;

  @override
  int maxOutputTokens(CreationJob job) => 100;

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) => throw UnimplementedError();
}

/// Lo que se guarda de «Lo creado» (F43) tiene que leerse igual en la próxima
/// versión: las claves de los tipos, de los recortes y de los estados no
/// cambian.
void main() {
  group('los tipos', () {
    test('sus claves son estables y se leen de vuelta', () {
      expect(
        {for (final k in StudyCreationKind.values) k: k.storageKey},
        {
          StudyCreationKind.fullText: 'full_text',
          StudyCreationKind.summary: 'summary',
          StudyCreationKind.synthesis: 'synthesis',
          StudyCreationKind.presentation: 'presentation',
          StudyCreationKind.mindMap: 'mind_map',
          StudyCreationKind.report: 'report',
          StudyCreationKind.flashcards: 'flashcards',
          StudyCreationKind.quiz: 'quiz',
          StudyCreationKind.infographic: 'infographic',
          StudyCreationKind.dataTable: 'data_table',
          StudyCreationKind.podcast: 'podcast',
        },
      );
      for (final kind in StudyCreationKind.values) {
        expect(StudyCreationKind.fromStorageKey(kind.storageKey), kind);
      }
      expect(StudyCreationKind.fromStorageKey('holograma'), isNull);
    });

    test('las tres de extraer son vistas vivas; las demás, de la IA', () {
      expect(
        {
          for (final k in StudyCreationKind.values)
            if (k.isLiveView) k,
        },
        {
          StudyCreationKind.fullText,
          StudyCreationKind.summary,
          StudyCreationKind.synthesis,
        },
      );
      for (final kind in StudyCreationKind.values) {
        expect(kind.usesAi, !kind.isLiveView);
      }
    });

    test('los estados, los motivos y los pasos, con sus claves', () {
      for (final status in CreationStatus.values) {
        expect(CreationStatus.fromStorageKey(status.storageKey), status);
      }
      expect(
        [for (final s in CreationStatus.values) s.storageKey],
        ['queued', 'generating', 'ready', 'failed'],
      );
      expect(CreationStatus.queued.isPending, isTrue);
      expect(CreationStatus.generating.isPending, isTrue);
      expect(CreationStatus.ready.isPending, isFalse);
      for (final failure in CreationFailure.values) {
        expect(CreationFailure.fromStorageKey(failure.storageKey), failure);
      }
      expect(CreationFailure.fromStorageKey('raro'), CreationFailure.error);
      for (final step in CreationStep.values) {
        expect(CreationStep.fromStorageKey(step.storageKey), step);
      }
      expect(CreationStep.fromStorageKey(null), isNull);
    });
  });

  group('los recortes', () {
    const all = [
      (CreationScope.allProcessed(), 'all'),
      (CreationScope.document('d1'), 'document:d1'),
      (CreationScope.notebook('n1'), 'notebook:n1'),
      (CreationScope.topic('v1'), 'topic:v1'),
      (CreationScope.space('s1'), 'space:s1'),
    ];

    test('cada uno con su clave, que se lee de vuelta', () {
      for (final (scope, key) in all) {
        expect(scope.storageKey, key);
        expect(CreationScope.parse(key), scope);
        expect(CreationScope.fromParts(scope.kindKey, scope.id), scope);
      }
    });

    test('un id con dos puntos se conserva entero', () {
      expect(
        CreationScope.parse('document:urn:x:1'),
        const CreationScope.document('urn:x:1'),
      );
    });

    test('lo que no se entiende no inventa un recorte', () {
      for (final key in [
        '',
        'raro:1',
        'document:',
        ':x',
        'notebook',
        'all:x',
      ]) {
        expect(CreationScope.parse(key), isNull, reason: key);
      }
      expect(CreationScope.fromParts('all', 'x'), isNull);
      expect(CreationScope.fromParts('document', null), isNull);
      expect(CreationScope.fromParts('document', ''), isNull);
    });

    test('«Para hoy»: todo es todo; lo demás, un recorte de Procesado', () {
      expect(
        const CreationScope.allProcessed().studyScope,
        const StudyScope.all(),
      );
      expect(
        const CreationScope.notebook('n1').studyScope,
        const StudyScope.processed('notebook:n1'),
      );
      expect(
        const CreationScope.document('d1').studyScope.kind,
        StudyScopeKind.processed,
      );
    });

    test('iguales por su clave', () {
      expect(
        const CreationScope.document('a'),
        isNot(const CreationScope.notebook('a')),
      );
      expect(
        const CreationScope.topic('a').hashCode,
        const CreationScope.topic('a').hashCode,
      );
    });
  });

  group('cuánto entra en la ventana', () {
    test('con Gemma: lo que queda de 2048, en partes que entran', () {
      const budget = CreationBudget(
        contextTokens: 2048,
        reservedOutputTokens: 768,
      );
      expect(budget.inputTokens, 2048 - 768 - kCreationInstructionTokens);
      expect(budget.inputChars, budget.inputTokens * kCreationCharsPerToken);
      expect(budget.partChars, budget.inputChars);
    });

    test(
      'con un modelo grande: con su tope de una vez y partes de capítulo',
      () {
        const budget = CreationBudget(
          contextTokens: 1000000,
          reservedOutputTokens: 8192,
        );
        expect(budget.inputChars, kMaxCreationInputChars);
        expect(budget.partChars, kMaxPartChars);
      },
    );

    test(
      'una ventana que no deja nada da cero de una vez y partes mínimas',
      () {
        const budget = CreationBudget(
          contextTokens: 1000,
          reservedOutputTokens: 2000,
        );
        expect(budget.inputTokens, 0);
        expect(budget.inputChars, 0);
        expect(budget.partChars, 500);
      },
    );
  });

  group('los generadores', () {
    test('se registran por tipo', () {
      final container = ProviderContainer(
        overrides: [
          creationGeneratorsProvider.overrideWithValue(const [
            _Generator(StudyCreationKind.mindMap),
            _Generator(StudyCreationKind.quiz),
          ]),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(creationGeneratorRegistryProvider).keys.toSet(), {
        StudyCreationKind.mindMap,
        StudyCreationKind.quiz,
      });
    });

    test('dos para el mismo tipo, o uno para uno de extraer, es un error', () {
      for (final generators in [
        const [
          _Generator(StudyCreationKind.quiz),
          _Generator(StudyCreationKind.quiz),
        ],
        const [_Generator(StudyCreationKind.summary)],
      ]) {
        final container = ProviderContainer(
          overrides: [creationGeneratorsProvider.overrideWithValue(generators)],
        );
        addTearDown(container.dispose);
        expect(
          () => container.read(creationGeneratorRegistryProvider),
          throwsA(anything),
        );
      }
    });
  });

  group('cómo se dice', () {
    final es = AppLocalizationsEs();
    final en = AppLocalizationsEn();

    test('cada tipo, motivo y paso tiene sus palabras, distintas entre sí', () {
      for (final l10n in [es, en]) {
        final kinds = {
          for (final k in StudyCreationKind.values)
            studyCreationKindLabel(l10n, k),
        };
        expect(kinds, hasLength(StudyCreationKind.values.length));
        final failures = {
          for (final f in CreationFailure.values)
            creationFailureMessage(l10n, f),
        };
        expect(failures, hasLength(CreationFailure.values.length));
        final steps = {
          for (final s in CreationStep.values) creationStepLabel(l10n, s),
        };
        expect(steps, hasLength(CreationStep.values.length));
      }
      expect({
        for (final k in StudyCreationKind.values) studyCreationKindIcon(k),
      }, hasLength(StudyCreationKind.values.length));
    });

    test('sin título, el nombre del tipo', () {
      StudyCreation creation(String? title) => StudyCreation(
        id: 'c',
        kind: StudyCreationKind.mindMap,
        title: title,
        scope: const CreationScope.allProcessed(),
        languageCode: 'es',
        status: CreationStatus.ready,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(studyCreationTitle(es, creation(null)), 'Mapa mental');
      expect(studyCreationTitle(es, creation('  ')), 'Mapa mental');
      expect(studyCreationTitle(es, creation('Éxodo')), 'Éxodo');
    });
  });
}
