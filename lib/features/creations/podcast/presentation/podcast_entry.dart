/// Dónde se pide un podcast (F47, punto 5 del plan): la tarjeta «Podcast» de
/// la grilla de crear de Repasar y la ficha «Podcast» de la fila de IA del
/// marco de lectura. Las dos abren la misma hoja, sobre el recorte o el
/// documento de ese momento.
library;

import 'package:flutter/widgets.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_customize_sheet.dart';

/// Abre la hoja del podcast sobre [scope]: un documento procesado
/// (`CreationScope.document`), un cuaderno, un tema o todo lo procesado. Con
/// lo último que se eligió, como toda hoja de «Lo creado»; lo que se pide va a
/// la cola y queda en «Lo creado» de ese recorte.
///
/// **El punto de entrada del marco de lectura** (F47, paso 1): la ficha
/// «Podcast» de su fila de IA llama a esto con el documento procesado que se
/// está leyendo.
Future<void> startPodcast(BuildContext context, CreationScope scope) =>
    showCreationCustomizeSheet(
      context,
      kind: StudyCreationKind.podcast,
      scope: scope,
    );
