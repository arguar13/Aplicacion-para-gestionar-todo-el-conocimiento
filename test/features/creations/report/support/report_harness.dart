import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/repositories/study_creation_repository.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_generators.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_json.dart';
import 'package:sinapsis/features/creations/report/presentation/providers/report_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';
import '../../presentation/repasar_harness.dart' show fakeEstimate;

/// Lo de una prueba de los informes (F43, paso 10): la app entera con su
/// router de verdad sobre una base en memoria, con los informes registrados
/// como en la app —el visor, la hoja, el generador—, la cola de crear DE
/// VERDAD con quien escribe de mentira ([writer]) y la estimación fija.
class ReportHarness {
  ReportHarness._(this.library);

  final LibraryHarness library;

  ProviderContainer get container => library.container;

  StudyCreationRepository get creations =>
      container.read(studyCreationRepositoryProvider);

  CreationQueue get queue => container.read(creationQueueProvider);

  /// Quien escribe en esta prueba; se puede cambiar antes de generar.
  static StructuredWriter? writer;

  /// Con [keywords], las palabras clave de las fuentes son esas, sin leer
  /// las marcas de estudiar.
  static Future<ReportHarness> create({List<String>? keywords}) async {
    final library = await LibraryHarness.create(
      extraOverrides: [
        creationQueueProvider.overrideWith((ref) {
          final queue = CreationQueue(
            repository: () => ref.read(studyCreationRepositoryProvider),
            scopes: () => ref.read(creationScopeResolverProvider),
            material: () => ref.read(creationMaterialBuilderProvider),
            generators: () => ref.read(creationGeneratorRegistryProvider),
            personWriter: () => writer!,
            backgroundWriter: () => writer!,
            readiness: () =>
                ({bool background = false}) async =>
                    const LanguageModelReady(provider: AiProvider.gemini),
            modelName: () => 'Gemini de prueba',
          );
          ref.onDispose(queue.dispose);
          return queue;
        }),
        creationSheetMaterialProvider.overrideWith(
          (ref, request) async => CreationMaterial(
            mode: CreationMaterialMode.fullText,
            text: 'x' * 9000,
            sources: [
              for (final id in request.sourceIds.ids)
                CreationMaterialSource(documentId: id, title: id, chars: 9000),
            ],
          ),
        ),
        creationEstimateProvider.overrideWith(
          (ref, request) => fakeEstimate(request),
        ),
        creationSuggestedTopicsProvider.overrideWith(
          (ref, scope) async => const <String>[],
        ),
        if (keywords != null)
          reportSourceKeywordsProvider.overrideWith(
            (ref, sources) async => keywords,
          ),
      ],
    );
    return ReportHarness._(library);
  }

  /// Un documento procesado [id] titulado [title], con [text] como su
  /// texto.
  Future<void> processed(
    String id,
    String title, {
    String text = 'Moisés guía al pueblo fuera de Egipto. Llegan al Sinaí.',
  }) => insertProcessedRows(
    library.database,
    id: id,
    title: title,
    parts: {
      ProcessedSection.text: [text],
    },
  );

  /// Un informe ya listo con [report], sobre [sources], con [options].
  Future<StudyCreation> ready(
    Report report, {
    List<String> sources = const ['p-1'],
    Map<String, Object?> options = const {},
  }) async {
    final created = (await creations.create(
      CreationRequest(
        kind: StudyCreationKind.report,
        scope: const CreationScope.allProcessed(),
        sourceIds: sources,
        options: options,
        runNow: false,
      ),
    )).getOrElse((f) => throw StateError('$f'));
    await creations.complete(
      created.id,
      title: report.title,
      content: ReportJson.encodeString(report),
    );
    return (await creations.find(
      created.id,
    )).getOrElse((f) => throw StateError('$f'))!;
  }

  /// La app entera con su router, en [theme], con la letra por [textScale] y
  /// sin animaciones.
  Widget app({
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) {
    container.read(vaultSessionControllerProvider.notifier).markUnlocked();
    return UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: theme.theme,
          darkTheme: theme.darkTheme,
          themeMode: theme.mode,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: ref.watch(goRouterProvider),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
    );
  }

  /// Abre [location] en un teléfono de [size].
  Future<void> open(
    WidgetTester tester,
    String location, {
    Size size = const Size(420, 1600),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(theme: theme, textScale: textScale));
    await tester.pumpAndSettle();
    library.goTo(location);
    await tester.pumpAndSettle();
  }
}
