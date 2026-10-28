import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Either;
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
import 'package:sinapsis/features/inbox/domain/entities/inbox_actions.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_step.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_history.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_intro_card.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_queue_sheet.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pending_excerpt.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pending_facts.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pending_text_status.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pick_living_note_dialog.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/suggested_property_chips.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/swipe_card.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/links/presentation/providers/link_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/presentation/retriage.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_triage_sheet.dart';
import 'package:sinapsis/features/reference/presentation/widgets/metadata_suggestion_banner.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/review_suggestions_action.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/suggestion_review_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La Bandeja de entrada como un mazo de tarjetas: todo lo nuevo de la
/// Biblioteca sobre lo que nadie decidió todavía qué hacer
/// (`InboxStatus.pending`), de a una fuente por vez.
///
/// **Entra apenas se guarda** (F41), tenga su texto o no. Lo que todavía no lo
/// tiene muestra qué le falta —«Transcribiendo…», «Leyendo la foto…»,
/// «Extrayendo el texto…», o un fallo con «Reintentar», ver
/// [PendingTextStatus]—: «Descartar» se puede de entrada, y lo que necesita
/// el texto queda apagado, con su motivo, hasta que llega; entonces se prende
/// solo, en vivo, sin tocar nada.
///
/// Cada tarjeta se resuelve con un gesto —izquierda descarta, derecha abre la
/// hoja «¿Qué va a Procesado?», arriba la abre directo en el original para
/// extraer notas— o con la tecla equivalente (flechas; Shift+→ pasa todo sin
/// modificar), o con su botón; los tres caminos hacen exactamente lo mismo, y
/// los tres respetan lo que el texto todavía no permite. Las propiedades que
/// el modelo sugirió son chips: tocar uno lo acepta, tocarlo de nuevo lo
/// deshace.
///
/// **Triar es elegir qué va a Procesado** (F41): la hoja arma el documento
/// procesado de la fuente con lo elegido —el texto, el resumen, la síntesis,
/// las notas, los fragmentos cortados a mano— y, con «Listo», la deja triada:
/// las dos cosas o ninguna (`TriageIntoProcessed`). «Pasar todo sin modificar»
/// hace lo mismo de un toque, con el texto original entero. «Deshacer»
/// deshace las dos.
///
/// Triar nunca suelta nada de la fuente (F41, decisión G): de la Biblioteca
/// nada se borra. La hoja de F30 que preguntaba «texto y libro, solo el texto,
/// solo el libro» y mandaba la otra mitad a la papelera ya no existe.
///
/// **«Volver a triar»** (F41, paso 4) está arriba siempre —también con la
/// Bandeja vacía— y con la R: elige cualquier fuente de la Biblioteca, triada
/// o no, y abre la misma hoja con lo que su documento ya tiene. Su aviso trae
/// su propio «Deshacer»; no entra al historial del mazo, que es de las
/// decisiones sobre las tarjetas.
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
  /// La fuente que se está viendo y lo que se puede hacer con ella, para que
  /// las teclas sepan sobre cuál actúan y no hagan lo que su texto todavía no
  /// permite.
  KnowledgeItem? _current;
  InboxActions _currentActions = InboxActions.none;

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pasa la fuente a [to], anota el paso en el historial y lo avisa con «Ver»
  /// y «Deshacer». Devuelve si salió bien.
  ///
  /// Deshacer la devuelve a la Bandeja, al estado de espera que le toque en
  /// ese momento: ver [InboxStep].
  Future<bool> _decide(
    KnowledgeItem item, {
    required InboxStepKind kind,
    required ItemState to,
    required String message,
    LinkedNote? linkedNote,
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
    _record(
      InboxStep(
        itemId: item.id,
        title: item.title,
        kind: kind,
        linkedNote: linkedNote,
      ),
      message,
    );
    return true;
  }

  /// Anota [step] en el historial y lo avisa con «Ver» y «Deshacer».
  void _record(InboxStep step, String message) {
    ref.read(inboxHistoryProvider.notifier).record(step);
    // La elegida de la cola ya se resolvió: el mazo vuelve a su orden.
    final focus = ref.read(inboxFocusedIdProvider.notifier);
    if (focus.state == step.itemId) focus.state = null;
    _announce(message, step);
  }

  /// Lo que dejó triar a Procesado: si salió, lo anota con su deshacer —el del
  /// documento procesado y el de la Bandeja— y lo avisa. Devuelve el fallo, o
  /// `null`.
  Failure? _processed(
    KnowledgeItem item,
    Either<Failure, ProcessOutcome> result, {
    required InboxStepKind kind,
    required String message,
  }) => result.match((failure) => failure, (outcome) {
    _record(
      InboxStep(
        itemId: item.id,
        title: item.title,
        kind: kind,
        processUndo: outcome.undo,
      ),
      message,
    );
    return null;
  });

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

  /// Tría la fuente: abre la hoja «¿Qué va a Procesado?» y, con «Listo»,
  /// arma su documento procesado con lo elegido y la deja triada. Cerrar la
  /// hoja la deja en la Bandeja, como estaba. Nunca suelta nada de la fuente
  /// —ni el archivo ni el texto—: queda entera en la Biblioteca (F41,
  /// decisión G).
  ///
  /// Con [cutting], la hoja abre directo «Cortar del original»: «Extraer
  /// nota», cuyas notas van al documento procesado (decisión C).
  ///
  /// Si la fuente ya tiene su documento procesado —se le extrajo una nota
  /// antes de triarla (decisión J)—, la hoja lo lee y no lo pisa: cada
  /// sección dice lo que ya tiene, agrega por defecto, y se puede elegir
  /// actualizar, reemplazar o quitar como al volver a triar.
  Future<void> _triage(KnowledgeItem item, {bool cutting = false}) async {
    final message = AppLocalizations.of(
      context,
    )!.inboxProcessedSnack(item.title);
    final triage = ref.read(triageIntoProcessedProvider);
    await showProcessedTriageSheet(
      context,
      sourceItemId: item.id,
      startCutting: cutting,
      changes: kRetriageChanges,
      onDone: (edits) async {
        final result = await triage(item.id, edits);
        if (!mounted) return result.getLeft().toNullable();
        return _processed(
          item,
          result,
          kind: InboxStepKind.triaged,
          message: message,
        );
      },
    );
  }

  /// Abre la fuente para sacarle notas: la hoja de triar, ya en «Cortar del
  /// original». Solo se ofrece con el texto del que se sacan —ver
  /// [InboxActions.extract]—.
  Future<void> _extract(KnowledgeItem item) => _triage(item, cutting: true);

  /// «Pasar todo sin modificar» (F41): de un toque, sin la hoja, el documento
  /// procesado guarda el texto original entero, con su enlace —nunca audio,
  /// video ni la ficha—, y la fuente queda triada. Con «Deshacer».
  Future<void> _passUnchanged(KnowledgeItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await ref
        .read(triageIntoProcessedProvider)
        .passUnchanged(item.id);
    if (!mounted) return;
    final failure = _processed(
      item,
      result,
      kind: InboxStepKind.passedUnchanged,
      message: l10n.inboxPassedUnchangedSnack(item.title),
    );
    if (failure != null) _showSnack(failure.localizedMessage(l10n));
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
          // «Volver a triar» (F41, paso 4), siempre: también con la Bandeja
          // vacía, que es cuando más se busca algo ya triado.
          IconButton(
            key: const Key('inbox-retriage'),
            icon: const Icon(Icons.replay_outlined),
            tooltip: l10n.inboxRetriageTooltip,
            onPressed: retriageAction(context, ref),
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
      // fuente que se está viendo, y lo mismo que ellos no hacen lo que su
      // texto todavía no permite. Ctrl+Z (o Cmd+Z) deshace lo último, y tiene
      // que andar también cuando eso dejó la Bandeja vacía.
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _withCurrent(_discard, allowed: (_) => true),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _withCurrent(_triage, allowed: (actions) => actions.triage),
          const SingleActivator(
            LogicalKeyboardKey.arrowRight,
            shift: true,
          ): () => _withCurrent(
            _passUnchanged,
            allowed: (actions) => actions.passUnchanged,
          ),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _withCurrent(_extract, allowed: (actions) => actions.extract),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyR): retriageAction(
            context,
            ref,
          ),
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
      _currentActions = InboxActions.none;
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
    // En qué está su texto (F41), en vivo: cuando llega, la misma tarjeta lo
    // muestra y prende lo que estaba apagado.
    final text = ref.watch(inboxPendingTextProvider(currentId)).valueOrNull;
    if (item == null || text == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final actions = InboxActions.of(item, text);
    _current = item;
    _currentActions = actions;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _PendingItemCard(
        // Una tarjeta por fuente: el estado de la anterior —lo arrastrado, los
        // chips aceptados— no se hereda.
        key: ValueKey(item.id),
        item: item,
        text: text,
        actions: actions,
        onDiscard: () => _discard(item),
        onTriage: () => _triage(item),
        onExtract: () => _extract(item),
        onPassUnchanged: () => _passUnchanged(item),
        onLink: () => _linkToLivingNote(item),
        onReviewSuggestions: (suggestions) =>
            _reviewSuggestions(item, suggestions),
      ),
    );
  }

  void _withCurrent(
    Future<void> Function(KnowledgeItem item) action, {
    required bool Function(InboxActions actions) allowed,
  }) {
    final item = _current;
    if (item != null && allowed(_currentActions)) unawaited(action(item));
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
    final outcome = await history.undoLast();
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
      },
    );
  }
}

class _PendingItemCard extends ConsumerWidget {
  const _PendingItemCard({
    required this.item,
    required this.text,
    required this.actions,
    required this.onDiscard,
    required this.onTriage,
    required this.onExtract,
    required this.onPassUnchanged,
    required this.onLink,
    required this.onReviewSuggestions,
    super.key,
  });

  final KnowledgeItem item;

  /// En qué está su texto (F41): con él, la tarjeta muestra su principio; sin
  /// él, qué le falta —ver [PendingTextStatus]—.
  final PendingText text;

  /// Lo que se puede hacer según ese texto: ver [InboxActions].
  final InboxActions actions;

  final VoidCallback onDiscard;
  final VoidCallback onTriage;
  final VoidCallback onExtract;
  final VoidCallback onPassUnchanged;
  final VoidCallback onLink;
  final ValueChanged<List<Suggestion>> onReviewSuggestions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Por qué está apagado lo que necesita el texto, mientras no llega.
    final needsText = text.neededReason(l10n);
    // «Pasar todo sin modificar» dice qué guarda, o por qué no se puede.
    final passReason = actions.passUnchanged
        ? l10n.inboxActionPassUnchangedTooltip
        : needsText ?? l10n.inboxActionPassUnchangedDisabledTooltip;
    final pending =
        ref.watch(pendingSuggestionsProvider(item.id)).valueOrNull ?? const [];
    // Un duplicado queda afuera del diálogo de revisión genérico (D4, F7):
    // fusionar borra un elemento, y eso pide su propia confirmación
    // explícita en la pantalla de "Posibles duplicados", no un casillero
    // más entre sugerencias reversibles con un toque. Una sugerencia de
    // referencia (F15) también: tiene su propia tarjeta, más abajo. Y una
    // corrección de «Revisar con otro modelo» (F33), que se decide con el
    // antes y el después en «Lo que hizo la IA».
    final suggestions = pending
        .where(
          (s) =>
              s is! DuplicateSuggestionEntry &&
              s is! MetadataSuggestion &&
              s is! CorrectionSuggestion,
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
            // Solo los sentidos que se pueden: hacia uno apagado no se
            // insinúa nada y la tarjeta vuelve a su lugar.
            hints: {
              SwipeDirection.left: (
                label: l10n.inboxActionDiscard,
                color: scheme.error,
              ),
              if (actions.triage)
                SwipeDirection.right: (
                  label: l10n.inboxActionTriage,
                  color: scheme.tertiary,
                ),
              if (actions.extract)
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
                    // El texto como se lee, no su Markdown ni un reproductor;
                    // mientras no llega, qué le falta (F41).
                    if (text.isReady)
                      PendingExcerpt(item: item)
                    else
                      PendingTextStatus(item: item, text: text),
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
                        _WhyOff(
                          reason: actions.triage ? null : needsText,
                          child: OutlinedButton.icon(
                            onPressed: actions.triage ? onTriage : null,
                            icon: const Icon(Icons.check),
                            label: Text(l10n.inboxActionTriage),
                          ),
                        ),
                        _WhyOff(
                          // Lo que se pasa entero es el texto del elemento,
                          // no el de un archivo de su «Contenido».
                          reason: passReason,
                          child: OutlinedButton.icon(
                            key: const Key('inbox-pass-unchanged'),
                            onPressed: actions.passUnchanged
                                ? onPassUnchanged
                                : null,
                            icon: const Icon(Icons.keyboard_double_arrow_right),
                            label: Text(l10n.inboxActionPassUnchanged),
                          ),
                        ),
                        _WhyOff(
                          // Con texto solo en su «Contenido»: las notas se
                          // cortan del texto del elemento.
                          reason: actions.extract
                              ? null
                              : needsText ??
                                    l10n.inboxActionExtractDisabledTooltip,
                          child: OutlinedButton.icon(
                            onPressed: actions.extract ? onExtract : null,
                            icon: const Icon(Icons.content_cut),
                            label: Text(l10n.inboxActionExtract),
                          ),
                        ),
                        _WhyOff(
                          reason: actions.link ? null : needsText,
                          child: FilledButton.icon(
                            onPressed: actions.link ? onLink : null,
                            icon: const Icon(Icons.link),
                            label: Text(l10n.inboxActionLink),
                          ),
                        ),
                        if (suggestions.isNotEmpty)
                          _WhyOff(
                            reason: actions.review ? null : needsText,
                            child: OutlinedButton.icon(
                              onPressed: actions.review
                                  ? () => onReviewSuggestions(suggestions)
                                  : null,
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: Text(l10n.inboxActionReviewSuggestions),
                            ),
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

/// Una acción apagada dice por qué —al pasar el puntero o al mantenerla
/// apretada—; prendida, no dice nada de más.
class _WhyOff extends StatelessWidget {
  const _WhyOff({required this.reason, required this.child});

  final String? reason;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (reason) {
    final reason? => Tooltip(message: reason, child: child),
    null => child,
  };
}
