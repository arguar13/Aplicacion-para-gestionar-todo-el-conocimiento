import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/content_trash/presentation/providers/content_trash_providers.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_step.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_history.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_intro_card.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_keep_sheet.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_queue_sheet.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pending_excerpt.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pending_facts.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pick_living_note_dialog.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/suggested_property_chips.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/swipe_card.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/links/presentation/providers/link_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/features/reference/presentation/widgets/metadata_suggestion_banner.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/review_suggestions_action.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/suggestion_review_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La Bandeja de entrada como un mazo de tarjetas: lo que el pipeline técnico
/// ya terminó y nadie decidió todavía qué hacer con eso
/// —`ItemState.processed`—, de a una fuente por vez.
///
/// Cada tarjeta se resuelve con un gesto —izquierda descarta, derecha la deja
/// triada, arriba la abre para extraer notas— o con la tecla equivalente
/// (flechas), o con su botón; los tres caminos hacen exactamente lo mismo. Las
/// propiedades que el modelo sugirió son chips: tocar uno lo acepta, tocarlo de
/// nuevo lo deshace.
///
/// Nada se pierde (F28): cada decisión deja un aviso con «Ver» y «Deshacer»;
/// se deshace de a un paso con el botón, con Ctrl+Z o desde el aviso, y el
/// historial sobrevive a salir de la pantalla —ver [InboxHistory]—. Vincular
/// a una nota viva y revisar sugerencias trían solo si se completaron: cerrar
/// el diálogo deja la fuente donde estaba. «N pendientes» abre la cola
/// entera, y la primera vez una tarjeta explica qué es triar.
///
/// Solo fuentes (`D3` en el plan de F3): una nota no se tría, su progreso se
/// mide con su madurez, no con este flujo.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  /// La fuente que se está viendo, para que las teclas sepan sobre cuál
  /// actúan.
  KnowledgeItem? _current;

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pasa la fuente a [to], anota el paso en el historial y lo avisa con «Ver»
  /// y «Deshacer». Devuelve si salió bien.
  ///
  /// Lo que está en el mazo está, por definición, en `processed`: es el estado
  /// al que vuelve al deshacer.
  Future<bool> _decide(
    KnowledgeItem item, {
    required InboxStepKind kind,
    required ItemState to,
    required String message,
    LinkedNote? linkedNote,
    List<String> trashedContentIds = const [],
  }) async {
    final result = await ref
        .read(inboxRepositoryProvider)
        .transitionState(itemId: item.id, to: to);
    if (!mounted) return false;

    final failure = result.getLeft().toNullable();
    if (failure != null) {
      _showSnack(failure.localizedMessage(AppLocalizations.of(context)!));
      return false;
    }

    final step = InboxStep(
      itemId: item.id,
      title: item.title,
      kind: kind,
      previousState: ItemState.processed,
      linkedNote: linkedNote,
      trashedContentIds: trashedContentIds,
    );
    ref.read(inboxHistoryProvider.notifier).record(step);
    // La elegida de la cola ya se resolvió: el mazo vuelve a su orden.
    final focus = ref.read(inboxFocusedIdProvider.notifier);
    if (focus.state == item.id) focus.state = null;
    _announce(message, step);
    return true;
  }

  /// El aviso de lo que se hizo: «Triado: El Imperio romano · Ver ·
  /// Deshacer».
  ///
  /// Lo que usan sus botones se resuelve ahora, con la pantalla viva: el aviso
  /// puede tocarse después de haber salido de la Bandeja —por ejemplo, desde
  /// la lectura que abrió «Extraer»—.
  void _announce(String message, InboxStep step) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // Del proveedor y no del contexto: el router de la app es uno solo, y
    // así «Ver» anda aunque la Bandeja ya no esté montada.
    final router = ref.read(goRouterProvider);
    final undo = _undoer();
    final theme = Theme.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Expanded(child: Text(message)),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor:
                      theme.snackBarTheme.actionTextColor ??
                      theme.colorScheme.inversePrimary,
                ),
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  unawaited(router.push(RoutePaths.itemDetail(step.itemId)));
                },
                child: Text(l10n.inboxView),
              ),
            ],
          ),
          action: SnackBarAction(
            label: l10n.inboxUndo,
            onPressed: () => unawaited(undo(only: step)),
          ),
        ),
      );
  }

  /// Quien deshace, con lo que necesita ya resuelto: ver [_announce].
  _InboxUndo _undoer() => _InboxUndo(
    history: ref.read(inboxHistoryProvider.notifier),
    focus: ref.read(inboxFocusedIdProvider.notifier),
    messenger: ScaffoldMessenger.of(context),
    l10n: AppLocalizations.of(context)!,
  );

  Future<void> _undo() => _undoer()();

  Future<void> _discard(KnowledgeItem item) => _decide(
    item,
    kind: InboxStepKind.discarded,
    to: ItemState.discarded,
    message: AppLocalizations.of(context)!.inboxDiscardedSnack(item.title),
  );

  /// Tría la fuente. En un libro o un documento, antes pregunta qué pasa a la
  /// siguiente fase (F30, decisión 68): el texto y el libro, solo el texto
  /// —el archivo va a la papelera de la app, y libera su lugar— o solo el
  /// libro —el texto va a la papelera y no se vuelve a extraer solo—. Cerrar
  /// la hoja sin elegir deja la fuente en la Bandeja.
  Future<void> _triage(KnowledgeItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final keep = await _askWhatToKeep(item);
    if (keep == null || !mounted) return;

    final trashing = ref.read(contentTrashRepositoryProvider);
    final dropped = switch (keep) {
      InboxKeep.both => right<Failure, List<TrashedContent>>(const []),
      InboxKeep.onlyText => await trashing.keepOnlyText(item.id),
      InboxKeep.onlyFile => await trashing.keepOnlyFile(item.id),
    };
    if (!mounted) return;
    if (dropped.getLeft().toNullable() case final failure?) {
      _showSnack(failure.localizedMessage(l10n));
      return;
    }
    final trashedIds = [
      for (final content in dropped.getRight().getOrElse(() => const []))
        content.id,
    ];

    final decided = await _decide(
      item,
      kind: InboxStepKind.triaged,
      to: ItemState.triaged,
      message: switch (keep) {
        InboxKeep.both => l10n.inboxTriagedSnack(item.title),
        InboxKeep.onlyText => l10n.inboxTriagedOnlyTextSnack(item.title),
        InboxKeep.onlyFile => l10n.inboxTriagedOnlyFileSnack(item.title),
      },
      trashedContentIds: trashedIds,
    );
    // Si no se pudo triar, lo soltado vuelve: la fuente queda como estaba.
    if (!decided) {
      for (final id in trashedIds) {
        await trashing.restore(id);
      }
    }
  }

  /// Qué pasa a la siguiente fase: [InboxKeep.both] sin preguntar si la
  /// fuente no es un libro o un documento con su archivo y su texto —no hay
  /// una mitad que soltar—, o lo elegido en la hoja; `null` si se la cerró.
  Future<InboxKeep?> _askWhatToKeep(KnowledgeItem item) async {
    final path = item.source.originalFilePath;
    if (item.source.kind != SourceKind.document ||
        path == null ||
        !(extractableRendition(item)?.content.trim().isNotEmpty ?? false)) {
      return InboxKeep.both;
    }
    final size = await ref.read(fileStoreProvider).sizeOf(path);
    if (!mounted) return null;
    return showInboxKeepSheet(context, fileBytes: size);
  }

  /// Abre la fuente para sacarle notas: la deja triada y, si tiene texto,
  /// abre la vista de lectura para destilar; si no, su detalle.
  Future<void> _extract(KnowledgeItem item) async {
    final decided = await _decide(
      item,
      kind: InboxStepKind.extracted,
      to: ItemState.triaged,
      message: AppLocalizations.of(context)!.inboxTriagedSnack(item.title),
    );
    if (!decided || !mounted) return;

    if (extractableRendition(item) == null) {
      await context.push(RoutePaths.itemDetail(item.id));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReadingScreen(itemId: item.id)),
    );
  }

  /// Revisa las sugerencias y, solo si se confirmó, tría la fuente: cerrar
  /// el diálogo la deja en la Bandeja, como estaba (F28).
  Future<void> _reviewSuggestions(
    KnowledgeItem item,
    List<Suggestion> suggestions,
  ) async {
    final reviewed = await showSuggestionReviewDialog(
      context,
      repository: ref.read(suggestionRepositoryProvider),
      suggestions: suggestions,
    );
    if (reviewed == null || !mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final failure = reviewed.getLeft().toNullable();
    if (failure != null) {
      _showSnack(failure.localizedMessage(l10n));
      return;
    }
    await _decide(
      item,
      kind: InboxStepKind.reviewed,
      to: ItemState.triaged,
      message: l10n.inboxReviewedSnack(item.title),
    );
  }

  /// Vincula la fuente a una nota viva —una que existe, o una nueva creada
  /// desde el selector— y, solo si quedó vinculada, la tría (F28). Cancelar
  /// el selector, o un vínculo que no se pudo crear, la dejan en la Bandeja.
  Future<void> _linkToLivingNote(KnowledgeItem item) async {
    final choice = await showDialog<LivingNoteChoice>(
      context: context,
      builder: (_) => PickLivingNoteDialog(excludeItemId: item.id),
    );
    if (choice == null || !mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final LinkedNote note;
    switch (choice) {
      case ExistingLivingNote(note: final existing):
        note = LinkedNote(
          id: existing.id,
          title: existing.title,
          created: false,
        );
      case NewLivingNote(:final title):
        final found = await ref
            .read(linkRepositoryProvider)
            .findOrCreateNote(title: title);
        if (!mounted) return;
        if (found.getLeft().toNullable() case final failure?) {
          _showSnack(failure.localizedMessage(l10n));
          return;
        }
        final (item: named, :created) = found.getRight().toNullable()!;
        // Con ese nombre ya había algo: si es una nota, se vincula a esa; si
        // es una fuente —la misma que se vincula, quizá—, no hay nota a la
        // que vincular, y otro elemento con ese título haría ambiguo cada
        // `[[Título]]`.
        if (named.source.kind != SourceKind.manualNote) {
          _showSnack(l10n.inboxLinkNameTaken(named.title));
          return;
        }
        note = LinkedNote(id: named.id, title: named.title, created: created);
    }

    final linked = await ref
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: note.id,
          toItemId: item.id,
          kind: kInboxLinkKind,
        );
    if (!mounted) return;
    if (linked.getLeft().toNullable() case final failure?) {
      // Una nota creada para este vínculo no queda suelta si el vínculo no
      // se pudo hacer.
      if (note.created) {
        await ref.read(libraryRepositoryProvider).delete(note.id);
        if (!mounted) return;
      }
      _showSnack(failure.localizedMessage(l10n));
      return;
    }

    await _decide(
      item,
      kind: InboxStepKind.linked,
      to: ItemState.triaged,
      message: l10n.inboxLinkedSnack(note.title, item.title),
      linkedNote: note,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pendingIds = ref.watch(inboxPendingIdsProvider).valueOrNull;
    final last = ref.watch(inboxHistoryProvider).lastOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inboxTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: last == null
                ? l10n.inboxUndo
                : '${l10n.inboxUndo}: ${last.title}',
            onPressed: last == null ? null : _undo,
          ),
          const ReviewSuggestionsAction(),
          // «N pendientes» abre la cola entera (F28): antes era un texto sin
          // acción, y la Bandeja no dejaba ver qué quedaba.
          if (pendingIds != null && pendingIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: l10n.inboxQueueTooltip,
                child: TextButton(
                  onPressed: () =>
                      showInboxQueueSheet(context, showingId: _current?.id),
                  child: Text(l10n.inboxPendingCount(pendingIds.length)),
                ),
              ),
            ),
        ],
      ),
      // Las teclas hacen lo mismo que los gestos y los botones, sobre la
      // fuente que se está viendo. Ctrl+Z (o Cmd+Z) deshace lo último, y tiene
      // que andar también cuando eso dejó la Bandeja vacía.
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _withCurrent(_discard),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _withCurrent(_triage),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _withCurrent(_extract),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              const InboxIntroCard(),
              Expanded(child: _buildBody(l10n, pendingIds)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, List<String>? pendingIds) {
    if (pendingIds == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (pendingIds.isEmpty) {
      _current = null;
      return EmptyStateView(
        icon: Icons.inbox_outlined,
        title: l10n.inboxEmptyTitle,
        message: l10n.inboxEmptyBody,
      );
    }

    // La elegida de la cola —o la que se acaba de deshacer— va arriba
    // mientras siga pendiente; si no, la que lleva más tiempo esperando.
    final focused = ref.watch(inboxFocusedIdProvider);
    final currentId = focused != null && pendingIds.contains(focused)
        ? focused
        : pendingIds.first;
    final item = ref.watch(libraryItemProvider(currentId)).valueOrNull;
    if (item == null) {
      return const Center(child: CircularProgressIndicator());
    }
    _current = item;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _PendingItemCard(
        // Una tarjeta por fuente: el estado de la anterior —lo arrastrado, los
        // chips aceptados— no se hereda.
        key: ValueKey(item.id),
        item: item,
        onDiscard: () => _discard(item),
        onTriage: () => _triage(item),
        onExtract: () => _extract(item),
        onLink: () => _linkToLivingNote(item),
        onReviewSuggestions: (suggestions) =>
            _reviewSuggestions(item, suggestions),
      ),
    );
  }

  void _withCurrent(Future<void> Function(KnowledgeItem item) action) {
    final item = _current;
    if (item != null) unawaited(action(item));
  }
}

/// Deshace el último paso del historial de la Bandeja y lo cuenta.
///
/// Recibe todo ya resuelto —no un `WidgetRef`— porque el aviso que lo llama
/// puede tocarse cuando la Bandeja ya no está en pantalla.
class _InboxUndo {
  const _InboxUndo({
    required this.history,
    required this.focus,
    required this.messenger,
    required this.l10n,
  });

  final InboxHistory history;
  final StateController<String?> focus;
  final ScaffoldMessengerState messenger;
  final AppLocalizations l10n;

  /// Con [only], deshace solo si ese sigue siendo el último paso: el
  /// «Deshacer» de un aviso es el de SU acción, no el de otra que vino
  /// después.
  Future<void> call({InboxStep? only}) async {
    if (only != null && history.last != only) return;
    final notRestored = <ContentRestoreOutcome>[];
    final outcome = await history.undoLast(onNotRestored: notRestored.add);
    if (outcome == null) return;

    messenger.hideCurrentSnackBar();
    outcome.match(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      ),
      (step) {
        // Lo que vuelve, arriba del mazo: se ve qué se deshizo.
        focus.state = step.itemId;
        if (step.linkedNote case LinkedNote(created: true, :final title)) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.inboxUndoneNoteTrashed(title))),
          );
        }
        // Lo que ya no se pudo devolver de lo soltado al triar (F30).
        for (final outcome in notRestored) {
          final message = switch (outcome) {
            ContentRestoreOutcome.fileMissing => l10n.contentTrashFileMissing,
            ContentRestoreOutcome.alreadyHasFile =>
              l10n.contentTrashAlreadyHasFile,
            ContentRestoreOutcome.restored ||
            ContentRestoreOutcome.gone => null,
          };
          if (message != null) {
            messenger.showSnackBar(SnackBar(content: Text(message)));
          }
        }
      },
    );
  }
}

class _PendingItemCard extends ConsumerWidget {
  const _PendingItemCard({
    required this.item,
    required this.onDiscard,
    required this.onTriage,
    required this.onExtract,
    required this.onLink,
    required this.onReviewSuggestions,
    super.key,
  });

  final KnowledgeItem item;
  final VoidCallback onDiscard;
  final VoidCallback onTriage;
  final VoidCallback onExtract;
  final VoidCallback onLink;
  final ValueChanged<List<Suggestion>> onReviewSuggestions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rendition = extractableRendition(item);
    final pending =
        ref.watch(pendingSuggestionsProvider(item.id)).valueOrNull ?? const [];
    // Un duplicado queda afuera del diálogo de revisión genérico (D4, F7):
    // fusionar borra un elemento, y eso pide su propia confirmación
    // explícita en la pantalla de "Posibles duplicados", no un casillero
    // más entre sugerencias reversibles con un toque. Una sugerencia de
    // referencia (F15) también: tiene su propia tarjeta, más abajo.
    final suggestions = pending
        .where(
          (s) => s is! DuplicateSuggestionEntry && s is! MetadataSuggestion,
        )
        .toList();
    final metadataSuggestion = pending
        .whereType<MetadataSuggestion>()
        .firstOrNull;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SwipeCard(
            onSwipe: (direction) => switch (direction) {
              SwipeDirection.left => onDiscard(),
              SwipeDirection.right => onTriage(),
              SwipeDirection.up => onExtract(),
            },
            hints: {
              SwipeDirection.left: (
                label: l10n.inboxActionDiscard,
                color: scheme.error,
              ),
              SwipeDirection.right: (
                label: l10n.inboxActionTriage,
                color: scheme.tertiary,
              ),
              SwipeDirection.up: (
                label: l10n.inboxActionExtract,
                color: scheme.primary,
              ),
            },
            // Una fuente y una nota no se ven igual: acá siempre es una fuente.
            child: Card(
              margin: EdgeInsets.zero,
              color: item.source.kind.role.surface(scheme),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  item.source.kind.role.radius,
                ),
                side: BorderSide(color: item.source.kind.role.outline(scheme)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(item.source.kind.icon, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.source.kind.label(l10n),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(item.title, style: theme.textTheme.headlineSmall),
                    if (item.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    // Autor, fecha, sitio, páginas o duración e idioma (F30,
                    // decisión 68): lo que se sabe de lo que se va a triar.
                    PendingFactsLine(item: item),
                    const SizedBox(height: 12),
                    // El texto como se lee, no su Markdown ni un reproductor:
                    // la Bandeja trabaja con texto.
                    PendingExcerpt(item: item),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            context.push(RoutePaths.itemDetail(item.id)),
                        icon: const Icon(Icons.open_in_full),
                        label: Text(l10n.inboxViewFull),
                      ),
                    ),
                    SuggestedPropertyChips(itemId: item.id),
                    if (metadataSuggestion != null) ...[
                      const SizedBox(height: 12),
                      MetadataSuggestionBanner(suggestion: metadataSuggestion),
                    ],
                    const Divider(height: 32),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onDiscard,
                          icon: const Icon(Icons.archive_outlined),
                          label: Text(l10n.inboxActionDiscard),
                        ),
                        OutlinedButton.icon(
                          onPressed: onTriage,
                          icon: const Icon(Icons.check),
                          label: Text(l10n.inboxActionTriage),
                        ),
                        Tooltip(
                          message: rendition == null
                              ? l10n.inboxActionExtractDisabledTooltip
                              : '',
                          child: OutlinedButton.icon(
                            onPressed: rendition == null ? null : onExtract,
                            icon: const Icon(Icons.content_cut),
                            label: Text(l10n.inboxActionExtract),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: onLink,
                          icon: const Icon(Icons.link),
                          label: Text(l10n.inboxActionLink),
                        ),
                        if (suggestions.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => onReviewSuggestions(suggestions),
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: Text(l10n.inboxActionReviewSuggestions),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.inboxShortcutsHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
