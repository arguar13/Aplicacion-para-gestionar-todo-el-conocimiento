import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/repositories/study_creation_repository.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/flashcards_kind.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/quiz/presentation/quiz_kind.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';
import '../../presentation/repasar_harness.dart';

/// Lo de una prueba de los visores del mazo y del cuestionario (F43, paso
/// 8): la app con su router de verdad sobre una base en memoria, los dos
/// tipos registrados como en la app y la cola de mentira de Repasar.
class StudyViewerHarness {
  StudyViewerHarness._(this.library);

  final LibraryHarness library;

  ProviderContainer get container => library.container;

  StudyCreationRepository get creations =>
      container.read(studyCreationRepositoryProvider);

  static Future<StudyViewerHarness> create({
    List<Override> overrides = const [],
  }) async {
    final library = await LibraryHarness.create(
      extraOverrides: [
        creationQueueProvider.overrideWith(
          (ref) => FakeCreationQueue(ref.read(studyCreationRepositoryProvider)),
        ),
        creationKindSpecsProvider.overrideWith(
          (ref) => [
            ref.watch(flashcardsKindSpecProvider),
            ref.watch(quizKindSpecProvider),
          ],
        ),
        ...overrides,
      ],
    );
    return StudyViewerHarness._(library);
  }

  /// Un documento procesado [id] titulado [title].
  Future<void> processed(String id, String title) =>
      insertProcessedRows(library.database, id: id, title: title);

  /// Una creación de [kind] lista, con [content] y [options], sobre
  /// [sources].
  Future<StudyCreation> ready(
    StudyCreationKind kind,
    String content, {
    List<String> sources = const ['doc'],
    Map<String, Object?> options = const {},
    String title = 'Éxodo',
  }) async {
    final created = (await creations.create(
      CreationRequest(
        kind: kind,
        scope: CreationScope.document(sources.first),
        sourceIds: sources,
        options: options,
      ),
    )).getOrElse((f) => throw StateError('$f'));
    await creations.complete(created.id, title: title, content: content);
    return (await creations.find(
      created.id,
    )).getOrElse((f) => throw StateError('$f'))!;
  }

  /// La app entera, en [theme], con la letra por [textScale] y sin
  /// animaciones —como pide la persona en el sistema—.
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

  /// Abre el visor de [creation] en un teléfono de [size].
  Future<void> open(
    WidgetTester tester,
    StudyCreation creation, {
    Size size = const Size(420, 900),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(theme: theme, textScale: textScale));
    await tester.pumpAndSettle();
    library.goTo(RoutePaths.creation(creation.id));
    await tester.pumpAndSettle();
  }
}
