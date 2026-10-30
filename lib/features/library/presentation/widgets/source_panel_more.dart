import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/core/util/transcript_timestamps.dart';
import 'package:sinapsis/features/content_trash/presentation/content_trash_actions.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/reextract_text.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se usa de vez en cuando con un elemento, en la hoja "Más" (F26,
/// decisión A): a la vista solo lo de todos los días —leer, resumir, copiar—,
/// y esto a un toque más.
///
/// La hoja de una nota propia se abre desde el panel de la fuente. La de una
/// fuente, desde su documento procesado, en «El texto de la fuente» (F45, paso
/// 3): la Biblioteca muestra solo su original, y lo que trabaja su texto queda
/// en Procesado, sin perder nada.
///
/// Lo que crea algo —que la IA organice una nota o le busque las fechas— ya
/// no está acá: va en «Crear», el ✨ de su barra (F45, paso 7b, mejora 14).
enum SourceMoreAction {
  /// Volver a extraer el texto, con el idioma (F22).
  reextract,

  /// Quitar las marcas de tiempo de una transcripción (F22).
  removeTimestamps,

  /// Borrar el texto de un libro o un documento y quedarse con el archivo: el
  /// texto va a la papelera de la app por 30 días y no se vuelve a extraer
  /// solo (F30, decisión 68).
  deleteText,
}

/// Las opciones de "Más" que aplican a [item], en el orden de la hoja: solo
/// las que se pueden hacer ahora. Mientras algo se procesa, o si falló sin
/// texto, no hay nada que ofrecer.
///
/// Una fuente queda de consulta (F41, decisión K, `isConsultationSource`): su
/// archivo no se suelta para quedarse con el texto —de la Biblioteca nada se
/// borra—. Le queda lo que trabaja su original: volver a extraer el texto,
/// quitar las marcas de tiempo y soltar el texto de un libro.
/// Verlo a pantalla completa ya no está acá (F45, paso 3): es el botón del
/// centro de su vista previa —«Leer como libro», «Ver la página», «Ampliar»—.
List<SourceMoreAction> sourceMoreActionsFor(KnowledgeItem item) {
  final hasText = item.renditions.whereType<TextRendition>().isNotEmpty;
  return [
    // También en «solo el libro» (F30, decisión 68): sin texto a propósito,
    // la persona sí puede pedir que se vuelva a extraer.
    if ((hasText || item.source.onlyFile) && canReextractText(item))
      SourceMoreAction.reextract,
    // Mientras se vuelve a extraer, el texto no se ve y va a ser
    // reemplazado: ni quitarle las marcas ni soltar el archivo que se está
    // leyendo de nuevo.
    if (!item.isBeingProcessed && _timestamped(item).isNotEmpty)
      SourceMoreAction.removeTimestamps,
    if (!item.isBeingProcessed && canKeepOnlyFile(item))
      SourceMoreAction.deleteText,
  ];
}

/// Las formas de texto de una transcripción que todavía tienen marcas de
/// tiempo —`[mm:ss]` al principio de cada línea, las pone
/// `formatTranscript`—. Solo en una transcripción: un PDF con una línea que
/// empieza con "[12:30]" no tiene marcas que quitar (F22).
List<TextRendition> _timestamped(KnowledgeItem item) {
  if (!isTranscriptSource(item.source)) return const [];
  return [
    for (final rendition in item.renditions.whereType<TextRendition>())
      if (rendition.kind != RenditionKind.blocks &&
          hasTimestamps(rendition.content))
        rendition,
  ];
}

/// Si tiene sentido ofrecer "borrar el texto, quedarme con el libro" (F30,
/// decisión 68): un libro o un documento con su archivo y con un texto que
/// soltar. Solo ahí: el texto de un audio o de una página no se puede volver
/// a sacar de nada que la persona quiera conservar como «el libro».
bool canKeepOnlyFile(KnowledgeItem item) =>
    item.source.kind == SourceKind.document &&
    item.source.originalFilePath != null &&
    _hasOwnText(item);

/// Si el elemento tiene un texto propio con algo escrito: el mismo que se
/// lee y del que se sacan notas, no el de un archivo de su «Contenido».
bool _hasOwnText(KnowledgeItem item) =>
    extractableRendition(item)?.content.trim().isNotEmpty ?? false;

/// Abre la hoja "Más" con [actions] y hace la que se elija.
///
/// La hoja se cierra antes de hacerla: volver a extraer y borrar el archivo
/// abren su propio diálogo, que no tiene que quedar encima de la hoja.
///
/// [title] la nombra —sin él, «Más acciones»— y [note] cuenta algo arriba de
/// las opciones, o en su lugar si no hay ninguna: desde Procesado, que lo que
/// cambie es el texto de la fuente (F45, paso 3).
///
/// [follow] es quien lleva el texto nuevo de la fuente a otro lado (F45, paso
/// 4): desde Procesado, a su documento. Se le avisa antes de que el texto
/// cambie —al volver a extraerlo o al quitarle las marcas de tiempo— y, si
/// cambia acá mismo, después.
Future<void> showSourceMoreSheet(
  BuildContext context,
  WidgetRef ref,
  KnowledgeItem item,
  List<SourceMoreAction> actions, {
  String? title,
  String? note,
  SourceTextFollow? follow,
}) async {
  final chosen = await _openSheet(context, actions, title: title, note: note);
  if (chosen == null || !context.mounted) return;

  switch (chosen) {
    case SourceMoreAction.reextract:
      await reextractText(
        context,
        ref,
        item,
        beforeQueue: follow == null ? null : () => follow.before(item),
        startedMessage: follow?.reextractStarted,
      );
    case SourceMoreAction.removeTimestamps:
      await _removeTimestamps(context, ref, item, follow: follow);
    case SourceMoreAction.deleteText:
      await trashExtractedText(context, ref, item);
  }
}

/// La misma hoja, sin opciones: solo [note], con [title]. Para decir por qué
/// no hay nada que hacer cuando el elemento no se pudo leer.
Future<void> showSourceMoreNotice(
  BuildContext context, {
  required String title,
  required String note,
}) => _openSheet(context, const [], title: title, note: note);

Future<SourceMoreAction?> _openSheet(
  BuildContext context,
  List<SourceMoreAction> actions, {
  String? title,
  String? note,
}) => showModalBottomSheet<SourceMoreAction>(
  context: context,
  showDragHandle: true,
  builder: (context) =>
      _SourceMoreSheet(actions: actions, title: title, note: note),
);

class _SourceMoreSheet extends StatelessWidget {
  const _SourceMoreSheet({required this.actions, this.title, this.note});

  final List<SourceMoreAction> actions;
  final String? title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title ?? l10n.sourcePanelMoreTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // Con la IA, volver a extraer y soltar el archivo y el texto son
            // seis filas: en una pantalla baja la hoja no entra entera, y se
            // desplaza en vez de cortarse. La nota va adentro: con la letra
            // al doble son varios renglones.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (note case final note?)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Text(
                        note,
                        key: const Key('source-more-note'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final action in actions)
                    ListTile(
                      key: Key('source-more-${action.name}'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      leading: SourcePanelIconCircle(
                        icon: action.icon,
                        tone: action.tone,
                      ),
                      title: Text(action.title(l10n)),
                      subtitle: Text(action.hint(l10n)),
                      onTap: () => Navigator.of(context).pop(action),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on SourceMoreAction {
  /// Lo que suelta algo del elemento se ve como lo que es.
  SourcePanelTone get tone => this == SourceMoreAction.deleteText
      ? SourcePanelTone.error
      : SourcePanelTone.neutral;

  IconData get icon => switch (this) {
    SourceMoreAction.reextract => Icons.refresh,
    SourceMoreAction.removeTimestamps => Icons.timer_off_outlined,
    SourceMoreAction.deleteText => Icons.notes_outlined,
  };

  String title(AppLocalizations l10n) => switch (this) {
    SourceMoreAction.reextract => l10n.detailReextract,
    SourceMoreAction.removeTimestamps => l10n.detailRemoveTimestamps,
    SourceMoreAction.deleteText => l10n.detailDeleteText,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    SourceMoreAction.reextract => l10n.sourcePanelReextractHint,
    SourceMoreAction.removeTimestamps => l10n.sourcePanelRemoveTimestampsHint,
    SourceMoreAction.deleteText => l10n.sourcePanelDeleteTextHint,
  };
}

/// Quien lleva el texto nuevo de una fuente a otro lado (F45, paso 4): ver
/// [showSourceMoreSheet].
typedef SourceTextFollow = ({
  /// Antes de que el texto de la fuente cambie.
  Future<void> Function(KnowledgeItem source) before,

  /// Con el texto ya cambiado, cuando cambia en el momento —quitar las marcas
  /// de tiempo—; lo que se vuelve a extraer avisa al terminar la cola.
  Future<void> Function(KnowledgeItem source) after,

  /// Si no cambió: el cambio falló, y lo anotado antes ya no espera nada.
  Future<void> Function(KnowledgeItem source) cancel,

  /// El aviso de que se empezó a volver a extraer.
  String reextractStarted,
});

/// Lo que el usuario pide es no ver los minutos, no que se toque lo dicho:
/// ver `stripTimestamps`. Con [follow], el texto sin las marcas también va
/// adonde lo lleva.
Future<void> _removeTimestamps(
  BuildContext context,
  WidgetRef ref,
  KnowledgeItem item, {
  SourceTextFollow? follow,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final timestamped = {for (final r in _timestamped(item)) r.id};

  final updated = item.copyWith(
    renditions: [
      for (final r in item.renditions)
        if (r is TextRendition && timestamped.contains(r.id))
          r.copyWith(content: stripTimestamps(r.content))
        else
          r,
    ],
  );

  await follow?.before(item);
  final result = await ref.read(libraryRepositoryProvider).save(updated);
  if (result.getRight().toNullable() case final saved?) {
    await follow?.after(saved);
  } else {
    await follow?.cancel(item);
  }
  if (!context.mounted) return;

  result.match(
    (failure) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
    (_) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.detailTimestampsRemoved))),
  );
}
