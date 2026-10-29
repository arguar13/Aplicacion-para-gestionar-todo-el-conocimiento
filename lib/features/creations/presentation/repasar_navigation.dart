/// Cómo se llega a Repasar y a lo creado desde cualquier pantalla (F43, M6):
/// «Crear en Repasar» desde un documento procesado o un cuaderno, abrir una
/// creación, y de una creación a sus fuentes.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';

/// Abre Repasar con [scope] ya elegido en el selector: lo que hace «Crear en
/// Repasar». El recorte se fija antes de navegar —así Repasar nunca se ve un
/// instante con el de antes— y queda entre los recientes; la dirección lo
/// lleva igual (`/review?scope=…`), para que un enlace directo haga lo mismo.
void openRepasarWith(BuildContext context, CreationScope scope) {
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(repasarScopeProvider.notifier).state = scope;
  container.read(recentCreationScopesProvider.notifier).remember(scope);
  // `go` y no `push`: Repasar es un destino de la barra, y apilarlo encima de
  // un documento —que se dibuja en la raíz— armaría un segundo shell.
  context.go(RoutePaths.reviewFor(scope.storageKey));
}

/// Abre el visor de [creation].
void openCreation(BuildContext context, StudyCreation creation) =>
    unawaited(context.push(RoutePaths.creation(creation.id)));

/// Abre el documento procesado [documentId] (una fuente de una creación).
void openProcessedSource(BuildContext context, String documentId) =>
    unawaited(context.push(RoutePaths.processedDocument(documentId)));

/// Abre la pantalla de lo que recorta [scope]: el cuaderno, el material del
/// tema en el Explorador —lo que abre el Atlas desde una rama— o el
/// documento. «Todo lo procesado» abre Procesado.
void openCreationScope(BuildContext context, CreationScope scope) {
  switch (scope) {
    case AllProcessed():
      context.go(RoutePaths.processed);
    case ProcessedDocumentScope(:final documentId):
      openProcessedSource(context, documentId);
    // El cuaderno es un destino de la barra (su rama): se va, no se apila.
    case NotebookScope(:final notebookId):
      context.go(RoutePaths.notebookDetail(notebookId));
    case TopicScope(:final valueId):
      unawaited(context.push(RoutePaths.explorerFor(valueId)));
    case SpaceScope(:final spaceId):
      unawaited(context.push(RoutePaths.explorerForSpace(spaceId)));
  }
}
