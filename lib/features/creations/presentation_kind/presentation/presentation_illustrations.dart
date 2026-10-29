import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_kind/data/deck_illustrator.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/providers/presentation_providers.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Dibuja desde el visor las ilustraciones [slides] de la presentación
/// [creationId] —«Volver a dibujar» una, o «Completar ilustraciones»— con la
/// cuenta [accountId] (o la elegida al crearla) y en el estilo que se eligió,
/// para la plantilla [template] que se ve ahora. Lo que salió se guarda en
/// el contenido (`StudyCreationRepository.amend`), y la ilustración que se
/// reemplazó se borra del almacén.
///
/// Lo que no sale queda con su porqué en el contenido, como al generarla:
/// nunca se pierde lo que ya había.
Future<DeckIllustrationRun> drawPresentationIllustrations(
  WidgetRef ref, {
  required String creationId,
  required List<int> slides,
  required DeckTemplateId template,
  String? accountId,
  CancellationSignal? cancellation,
  void Function(int done, int total)? onProgress,
}) async {
  // Lo que se pide a Riverpod va antes de esperar nada: la hoja que lo
  // pidió se puede cerrar a mitad (y eso lo cancela).
  final repository = ref.read(studyCreationRepositoryProvider);
  final files = ref.read(creationIllustrationFilesProvider);
  final illustrator = ref.read(deckIllustratorProvider);
  final found = await repository.find(creationId);
  final creation = found.getRight().toNullable();
  if (creation == null) throw StateError('La presentación ya no está.');
  final options = PresentationOptions.of(creation.options);
  final run = await illustrator.illustrate(
    creationId: creationId,
    content: PresentationContent.decode(creation.content),
    slides: slides,
    styleHint: options.illustrationStyle.hintFor(template),
    accountId: accountId ?? options.imageAccountId,
    cancellation: cancellation,
    onProgress: onProgress,
  );
  final saved = await repository.amend(
    creationId,
    content: run.content.encode(),
  );
  if (saved.isLeft()) {
    for (final path in run.saved) {
      unawaited(files.delete(creationId, path));
    }
    throw StateError('No se pudo guardar la ilustración.');
  }
  for (final path in run.replaced) {
    unawaited(files.delete(creationId, path));
  }
  return run;
}
