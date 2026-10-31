/// Lo que ofrece tocar una idea del mapa mental (F43, punto 5 del plan):
/// «Preguntarle al chat sobre esto» y «Ver en el documento».
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map.dart';
import 'package:sinapsis/features/creations/presentation/creation_passage_navigation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La pregunta para el chat sobre [node], como la arma NotebookLM: la idea y,
/// si no es la central, la de arriba como contexto. Con [documentTitle] —un
/// mapa de un solo documento—, la pregunta lo nombra: así la búsqueda en la
/// bóveda va a él.
String mindMapQuestion(
  AppLocalizations l10n,
  MindMap map,
  MindMapNode node, {
  String? documentTitle,
}) {
  final path = map.pathTo(node.id);
  final parent = path.length >= 2 ? path[path.length - 2].label : null;
  final document = documentTitle?.trim();
  if (document != null && document.isNotEmpty) {
    return parent == null
        ? l10n.f43MindAskDoc(document, node.label)
        : l10n.f43MindAskDocIn(document, node.label, parent);
  }
  return parent == null
      ? l10n.f43MindAsk(node.label)
      : l10n.f43MindAskIn(node.label, parent);
}

/// El documento del que sale [node]: el que dijo la IA o, si el mapa se hizo
/// de un solo documento, ese.
String? mindMapNodeDocument(StudyCreation creation, MindMapNode node) =>
    node.source?.documentId ??
    (creation.sourceIds.length == 1 ? creation.sourceIds.single : null);

/// «Preguntarle al chat sobre esto»: abre el chat con la pregunta de
/// [mindMapQuestion] y el recorte de la creación como contexto —acotado al
/// cuaderno si se creó sobre uno— y la manda.
void askMindMapNodeInChat(
  BuildContext context,
  StudyCreation creation,
  MindMap map,
  MindMapNode node, {
  String? documentTitle,
}) {
  final l10n = AppLocalizations.of(context)!;
  final scope = creation.scope;
  askInChat(
    context,
    ChatHandoff(
      question: mindMapQuestion(
        l10n,
        map,
        node,
        documentTitle: scope is ProcessedDocumentScope ? documentTitle : null,
      ),
      notebookId: scope is NotebookScope ? scope.notebookId : null,
    ),
  );
}

/// «Ver en el documento»: la lectura de la fuente parada en el pasaje de
/// [node], con el tramo marcado (`openCreationPassage`). Si la idea no trae
/// pasaje, o no aparece en el texto, abre el documento procesado; si no se
/// sabe de qué documento sale, la lista de fuentes de la creación.
Future<void> openMindMapNodeInDocument(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
  MindMapNode node,
) => openCreationPassage(
  context,
  ref,
  creation,
  documentId: mindMapNodeDocument(creation, node),
  quote: node.source?.quote,
);
