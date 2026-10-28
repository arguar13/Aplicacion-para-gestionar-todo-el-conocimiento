import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_triage.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/triage_offer.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_cut_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/triage_image_grid.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/triage_section_texts.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que hace «Listo»: guardar [edits] y, si se pidió, lo de la copia del
/// original ([original], decisión H; `null` si no se toca). Devuelve el fallo,
/// o `null` si salió bien —entonces la hoja se cierra; si no, queda abierta con
/// lo elegido y dice por qué—.
typedef ProcessedTriageDone =
    Future<Failure?> Function(
      Map<ProcessedSection, SectionEdit> edits,
      OriginalEdit? original,
    );

/// Abre la hoja «¿Qué va a Procesado?» (F41) sobre la fuente
/// [sourceItemId]. Devuelve si se terminó con «Listo».
///
/// **El contrato, para triar y para «Volver a triar» (paso 4):**
///
/// - [existing]: cuántas partes tiene ya cada sección del documento
///   procesado; vacío si todavía no existe. Sin darlo (`null`), la hoja lo lee
///   del documento al abrirse (`processedDocumentForSourceProvider`): es lo
///   que hacen la Bandeja —una fuente puede tener documento antes de triarse,
///   por una nota extraída (decisión J)— y «Volver a triar».
/// - [initial]: lo que la hoja trae pedido al abrirse, como lo recibe
///   `ProcessSourceUseCase`.
/// - [changes]: qué se puede pedir por sección. Triar algo nuevo ofrece solo
///   [ProcessedChange.add], y la hoja muestra interruptores; con más, cada
///   sección que el documento ya tiene ofrece además elegir entre agregar,
///   actualizar, reemplazar o quitar.
/// - [originalExists] e [initialOriginal]: si el documento ya tiene la copia
///   del original —sin decirlo, lo lee del documento, como [existing]— y qué
///   se le pide al abrir (decisión H). La copia va aparte de las secciones:
///   es un archivo, no partes.
/// - [onDone]: lo que hace «Listo» con el `Map<ProcessedSection,
///   SectionEdit>` armado y lo pedido para la copia —en la Bandeja, procesar
///   y triar; al volver a triar, solo procesar—. La hoja no guarda nada por
///   su cuenta.
/// - [startCutting]: abre enseguida «Cortar del original», encima: lo que
///   hace «Extraer nota» de la tarjeta.
Future<bool> showProcessedTriageSheet(
  BuildContext context, {
  required String sourceItemId,
  required ProcessedTriageDone onDone,
  Map<ProcessedSection, int>? existing,
  Map<ProcessedSection, SectionEdit> initial = const {},
  Set<ProcessedChange> changes = const {ProcessedChange.add},
  bool? originalExists,
  OriginalEdit? initialOriginal,
  bool startCutting = false,
}) async {
  final still = MediaQuery.disableAnimationsOf(context);
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      builder: (context, scroll) => ProcessedTriageSheet(
        sourceItemId: sourceItemId,
        onDone: onDone,
        existing: existing,
        initial: initial,
        changes: changes,
        originalExists: originalExists,
        initialOriginal: initialOriginal,
        startCutting: startCutting,
        scrollController: scroll,
      ),
    ),
  );
  return done ?? false;
}

/// La hoja «¿Qué va a Procesado?» (F41): triar es elegir qué información pura
/// de la fuente va a su documento procesado. Ver [showProcessedTriageSheet].
///
/// - **De la fuente**: el texto extraído, el resumen y la síntesis, cada uno
///   con su interruptor, en cualquier combinación, y —si la fuente lo
///   ofrece— la copia de su original, con lo que ocupa. Si todavía no hay
///   resumen o síntesis, ofrece armarlo con la IA o a mano, como la tarjeta de
///   estudiar —el mismo [StudySuggestion] y sus mismos caminos—, y mientras
///   la IA lo arma, la misma franja con «Parar».
/// - **Las imágenes** (decisión L), si la fuente trae: una grilla con
///   «Todas», «Ninguna» y la elección de cada una tocándola, con lo que va a
///   ocupar su copia.
/// - **Lo tuyo**: las notas —escritas, o extraídas del original— y los
///   fragmentos cortados a mano, cada uno en su lista, con «Quitar».
/// - **La vista previa en vivo**: cuántas partes y palabras va a tener cada
///   sección (`ProcessSourceUseCase.preview`), sin guardar nada.
/// - **«Listo»** pasa lo elegido a [onDone].
///
/// Las secciones salen de lo que la fuente ofrece ([triageSectionsOffered]) y
/// de su forma ([triageShapeOf]): una sección nueva aparece sola, con su
/// interruptor o su lista.
///
/// Con el teclado: los números prenden cada sección de la fuente, C abre
/// «Cortar del original», N escribe una nota y Ctrl+Enter es «Listo».
class ProcessedTriageSheet extends ConsumerStatefulWidget {
  const ProcessedTriageSheet({
    required this.sourceItemId,
    required this.onDone,
    this.existing,
    this.initial = const {},
    this.changes = const {ProcessedChange.add},
    this.originalExists,
    this.initialOriginal,
    this.startCutting = false,
    this.scrollController,
    super.key,
  });

  final String sourceItemId;
  final ProcessedTriageDone onDone;

  /// Lo que el documento ya tiene, o `null` para leerlo de él.
  final Map<ProcessedSection, int>? existing;
  final Map<ProcessedSection, SectionEdit> initial;
  final Set<ProcessedChange> changes;

  /// Si el documento ya tiene la copia del original; sin decirlo, lo sabe del
  /// documento mismo, como [existing].
  final bool? originalExists;

  /// Lo que la hoja trae pedido para la copia al abrirse.
  final OriginalEdit? initialOriginal;
  final bool startCutting;
  final ScrollController? scrollController;

  @override
  ConsumerState<ProcessedTriageSheet> createState() =>
      _ProcessedTriageSheetState();
}

class _ProcessedTriageSheetState extends ConsumerState<ProcessedTriageSheet> {
  /// Si la hoja ya arrancó con lo pedido: hasta el primer cuadro no se puede
  /// cambiar lo que miran los demás.
  var _started = false;
  var _busy = false;
  String? _error;

  ProcessedTriageController get _controller =>
      ref.read(processedTriageProvider(widget.sourceItemId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.existing case final existing?) {
        _start(existing, originalExists: widget.originalExists ?? false);
        return;
      }
      // Lo que el documento ya tiene, del documento mismo —vivo o en la
      // papelera, de donde procesar lo saca con lo que tenía—: sus cuentas
      // por sección, las de su fila de «Procesado», nunca su texto. Hasta que
      // llegan, la hoja espera con la ruedita, como mientras lee la fuente.
      // Si la lectura falla, la hoja sigue como si no hubiera nada: agregar
      // no repite lo que ya está, así que no se pisa nada.
      ref.listenManual(
        processedDocumentForSourceProvider(widget.sourceItemId),
        (_, document) {
          if (_started || document.isLoading) return;
          final summary = document.valueOrNull?.summary;
          _start(
            summary?.partCounts ?? const {},
            originalExists:
                widget.originalExists ?? summary?.hasOriginal ?? false,
          );
        },
        fireImmediately: true,
      );
    });
  }

  void _start(
    Map<ProcessedSection, int> existing, {
    required bool originalExists,
  }) {
    _controller.triage = ProcessedTriage.from(
      widget.sourceItemId,
      existing: existing,
      edits: widget.initial,
      originalExists: originalExists,
      original: widget.initialOriginal,
    );
    setState(() => _started = true);
    unawaited(_readMissingExcerpts());
    if (widget.startCutting) _cut();
  }

  /// Los pasajes que trae [ProcessedTriageSheet.initial] sin su texto: se
  /// leen de la fuente, una sola vez.
  Future<void> _readMissingExcerpts() async {
    final missing = [
      for (final choice
          in ref
              .read(processedTriageProvider(widget.sourceItemId))
              .choices
              .values)
        for (final clip in choice.clips)
          if (clip.excerpt.isEmpty && clip.anchor != null) clip.anchor!,
    ];
    if (missing.isEmpty) return;
    final repository = ref.read(processedRepositoryProvider);
    final excerpts = {
      for (final anchor in missing)
        if ((await repository.sourceText(
              widget.sourceItemId,
              renditionId: anchor.renditionId,
            )).toNullable()
            case final text? when anchor.end <= text.text.length)
          anchor: text.text.substring(anchor.start, anchor.end),
    };
    if (!mounted) return;
    _controller.triage = ref
        .read(processedTriageProvider(widget.sourceItemId))
        .withExcerpts(excerpts);
  }

  void _cut() =>
      unawaited(openProcessedCutScreen(context, widget.sourceItemId));

  Future<void> _writeNote() async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _WriteNoteDialog(),
    );
    if (note == null || !mounted) return;
    _controller.writeNote(note);
  }

  Future<void> _done() async {
    final triage = ref.read(processedTriageProvider(widget.sourceItemId));
    if (triage.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onDone(triage.edits, triage.originalEdit);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = failure.localizedMessage(AppLocalizations.of(context)!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final id = widget.sourceItemId;
    final triage = ref.watch(processedTriageProvider(id));
    final material = ref.watch(processedSourceMaterialProvider(id));
    final item = ref.watch(libraryItemProvider(id)).valueOrNull;
    final text = item == null ? null : studyTextOf(item);
    final study = text == null
        ? null
        : ref.watch(documentStudyProvider(text.renditionId)).valueOrNull;
    // Qué se ve y qué se elige a mano de lo estudiado vive mientras alguien lo
    // mira: «Elegir a mano» lo prende acá y se usa en «Cortar del original».
    if (text != null) ref.watch(studyViewProvider(text.renditionId));

    final loaded = material.valueOrNull?.toNullable();
    final failure = material.valueOrNull?.getLeft().toNullable();
    if (!_started || (loaded == null && failure == null)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (failure != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(failure.localizedMessage(l10n)),
        ),
      );
    }

    final offered = triageSectionsOffered(loaded!);
    final whole = [
      for (final section in offered)
        if (triageShapeOf(section) == TriageSectionShape.whole) section,
    ];
    final clips = [
      for (final section in offered)
        if (triageShapeOf(section) == TriageSectionShape.clips) section,
    ];
    // La copia del original (decisión H): si la fuente la ofrece, o si el
    // documento ya tiene una —para actualizarla, reemplazarla o quitarla—.
    final offersOriginal = loaded.original != null || triage.originalExists;
    final galleries = [
      for (final section in offered)
        if (triageShapeOf(section) == TriageSectionShape.gallery) section,
    ];
    final sheet = _SheetContext(
      triage: triage,
      material: loaded,
      text: text,
      study: study,
      transcript: item != null && isTranscriptSource(item.source),
      changes: widget.changes,
    );

    final bindings = <ShortcutActivator, VoidCallback>{
      for (final (index, section) in whole.take(9).indexed)
        SingleActivator(_digits[index]): () {
          if (sheet.canToggle(section)) {
            _controller.setSection(section, on: !triage.includes(section));
          }
        },
      if (offersOriginal && whole.length < 9)
        SingleActivator(_digits[whole.length]): () => _controller.setOriginal(
          on: triage.original == null,
          change: sheet.originalChanges.first,
        ),
      if (offered.contains(ProcessedSection.fragments))
        const SingleActivator(LogicalKeyboardKey.keyC): _cut,
      if (offered.contains(ProcessedSection.notes))
        const SingleActivator(LogicalKeyboardKey.keyN): () =>
            unawaited(_writeNote()),
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
          unawaited(_done()),
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
          unawaited(_done()),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Column(
          key: const Key('processed-triage-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  Text(
                    l10n.processedTriageTitle,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loaded.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.processedTriageIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (whole.isNotEmpty ||
                      offersOriginal ||
                      galleries.isNotEmpty) ...[
                    _GroupTitle(l10n.processedTriageFromSource),
                    for (final section in whole)
                      _WholeSection(
                        section: section,
                        sheet: sheet,
                        onChanged: (on) =>
                            _controller.setSection(section, on: on),
                        onChange: (change) => _controller.setSection(
                          section,
                          on: true,
                          change: change,
                        ),
                        onManual: _cut,
                      ),
                    if (offersOriginal)
                      _OriginalSection(
                        sheet: sheet,
                        // Con la copia ya hecha, prenderlo es actualizarla:
                        // agregar no haría nada.
                        onChanged: (on) => _controller.setOriginal(
                          on: on,
                          change: sheet.originalChanges.first,
                        ),
                        onChange: (change) =>
                            _controller.setOriginal(on: true, change: change),
                      ),
                    for (final section in galleries)
                      _GallerySection(
                        section: section,
                        sheet: sheet,
                        onChange: (change) => _controller.setSection(
                          section,
                          on: true,
                          change: change,
                        ),
                      ),
                  ],
                  if (clips.isNotEmpty) ...[
                    _GroupTitle(l10n.processedTriageYours),
                    for (final section in clips)
                      _ClipsSection(
                        section: section,
                        sheet: sheet,
                        onWrite: () => unawaited(_writeNote()),
                        onCut: _cut,
                        onRemove: _controller.remove,
                        onChange: (change) => _controller.setSection(
                          section,
                          on: true,
                          change: change,
                        ),
                      ),
                  ],
                  _PreviewCard(
                    sheet: sheet,
                    keys: (whole.length + (offersOriginal ? 1 : 0)).clamp(1, 9),
                  ),
                ],
              ),
            ),
            _Actions(
              sheet: sheet,
              busy: _busy,
              error: _error,
              onCancel: () => Navigator.of(context).maybePop(),
              onDone: () => unawaited(_done()),
            ),
          ],
        ),
      ),
    );
  }

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
}

/// Lo que todas las partes de la hoja necesitan saber, armado una vez por
/// cuadro.
class _SheetContext {
  const _SheetContext({
    required this.triage,
    required this.material,
    required this.text,
    required this.study,
    required this.transcript,
    required this.changes,
  });

  final ProcessedTriage triage;
  final ProcessedSourceMaterial material;

  /// El texto que se estudia de la fuente: el de «Resumir» y «Elegir a mano».
  final StudyText? text;

  /// Lo estudiado de ese texto, en vivo.
  final DocumentStudy? study;
  final bool transcript;
  final Set<ProcessedChange> changes;

  /// Las oraciones que trae hoy la fuente para [section], si lo arma
  /// estudiar; `null` si no.
  int? sentencesOf(ProcessedSection section) {
    final kind = triageStudyKindOf(section);
    if (kind == null) return null;
    return study?.of(kind).length ?? 0;
  }

  /// Si [section] tiene algo en la fuente que llevar: sin resumen todavía,
  /// su interruptor espera a que lo haya.
  bool canToggle(ProcessedSection section) => switch (sentencesOf(section)) {
    null => true,
    final count => count > 0 || triage.includes(section),
  };

  /// Qué cambios se le pueden pedir a [section]: al triar algo nuevo, solo
  /// agregar; al volver a triar, lo que la sección admite, si ya tiene algo.
  List<ProcessedChange> changesFor(ProcessedSection section) {
    if ((triage.existing[section] ?? 0) == 0) {
      return const [ProcessedChange.add];
    }
    return [
      for (final change in ProcessedChange.values)
        if (changes.contains(change) &&
            (change != ProcessedChange.update || section.canUpdate))
          change,
    ];
  }

  /// Qué se le puede pedir a la copia del original: sin copia todavía, solo
  /// agregarla; con una, actualizarla, reemplazarla o quitarla —agregar no
  /// haría nada—.
  List<ProcessedChange> get originalChanges {
    if (!triage.originalExists) return const [ProcessedChange.add];
    return [
      for (final change in ProcessedChange.values)
        if (change != ProcessedChange.add && changes.contains(change)) change,
    ];
  }

  /// La clave de la vista previa de [section], si va.
  TriagePreviewKey? previewKeyOf(ProcessedSection section) {
    final edit = triage.edits[section];
    if (edit == null) return null;
    final kind = triageStudyKindOf(section);
    return (
      sourceItemId: triage.sourceItemId,
      section: section,
      edit: edit,
      // Mientras la IA arma el resumen —o se eligen sus oraciones a mano—, la
      // vista previa se rehace con cada oración que llega.
      revision: kind == null || study == null
          ? 0
          : Object.hashAll([for (final mark in study!.of(kind)) mark.id]),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Una sección que se copia entera de la fuente: su interruptor, cuánto va a
/// tener y, si todavía no hay nada que copiar, cómo armarlo.
class _WholeSection extends ConsumerWidget {
  const _WholeSection({
    required this.section,
    required this.sheet,
    required this.onChanged,
    required this.onChange,
    required this.onManual,
  });

  final ProcessedSection section;
  final _SheetContext sheet;
  final ValueChanged<bool> onChanged;
  final ValueChanged<ProcessedChange> onChange;

  /// «Elegir a mano»: abre el texto donde se tocan las oraciones.
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final on = sheet.triage.includes(section);
    final enabled = sheet.canToggle(section);
    final kind = triageStudyKindOf(section);
    final text = sheet.text;
    final running =
        text != null &&
        kind != null &&
        ref.watch(studyAnalysisProvider(text.renditionId))
            is StudyAnalysisRunning;
    final empty = sheet.sentencesOf(section) == 0;
    final label = triageSectionLabel(
      l10n,
      section,
      transcript: sheet.transcript,
    );

    return Column(
      key: Key('triage-section-${section.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: Key('triage-switch-${section.name}'),
          contentPadding: EdgeInsets.zero,
          secondary: Icon(triageSectionIcon(section)),
          title: Text(label),
          subtitle: on
              ? _PreviewText(sheet: sheet, section: section)
              : Text(_offText(l10n)),
          value: on,
          onChanged: enabled ? onChanged : null,
        ),
        if (on)
          _ChangeChoice(section: section, sheet: sheet, onChange: onChange),
        if (text != null && kind != null && running)
          StudyProgressStrip(text: text),
        // Sin nada todavía y sin nadie armándolo: los dos caminos de la
        // tarjeta de estudiar. Elegir uno prende la sección.
        if (text != null && kind != null && empty && !running)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 8),
            child: StudySuggestion(
              text: text,
              kind: kind,
              onChosen: (choice) {
                onChanged(true);
                unawaited(
                  applyStudySuggestion(
                    ref,
                    context,
                    text,
                    kind,
                    choice,
                    onManual: onManual,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Lo que trae la fuente, con la sección apagada.
  String _offText(AppLocalizations l10n) {
    final existing = sheet.triage.existing[section] ?? 0;
    final offer = switch (sheet.sentencesOf(section)) {
      null =>
        sheet.material.textWords > 0
            ? l10n.processedTriageWordCount(sheet.material.textWords)
            : '',
      0 => l10n.processedTriageNothingYet,
      final count => triageStudiedCountText(l10n, section, count),
    };
    return [
      if (existing > 0) l10n.processedTriageExisting(existing),
      if (offer.isNotEmpty) offer,
    ].join(' · ');
  }
}

/// La copia del original (decisión H): su interruptor y cuánto ocupa. Al
/// volver a triar un documento que ya la tiene, actualizarla, reemplazarla o
/// quitarla, como las demás secciones.
class _OriginalSection extends StatelessWidget {
  const _OriginalSection({
    required this.sheet,
    required this.onChanged,
    required this.onChange,
  });

  final _SheetContext sheet;
  final ValueChanged<bool> onChanged;
  final ValueChanged<ProcessedChange> onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final offer = sheet.material.original;
    final current = sheet.triage.original;
    final changes = sheet.originalChanges;
    final subtitle = [
      if (sheet.triage.originalExists) l10n.processedTriageOriginalExisting,
      if (offer != null)
        l10n.processedTriageOriginalOffer(
          formatFileSize(offer.sizeBytes, l10n.localeName),
        )
      else
        l10n.processedTriageOriginalGone,
    ].join(' · ');

    return Column(
      key: const Key('triage-section-original'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('triage-switch-original'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.file_copy_outlined),
          title: Text(l10n.processedTriageSectionOriginal),
          subtitle: Text(subtitle),
          value: current != null,
          onChanged: onChanged,
        ),
        if (current != null && changes.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 8),
            child: SegmentedButton<ProcessedChange>(
              key: const Key('triage-change-original'),
              showSelectedIcon: false,
              segments: [
                for (final change in changes)
                  ButtonSegment(
                    value: change,
                    label: Text(triageChangeLabel(l10n, change)),
                  ),
              ],
              selected: {current},
              onSelectionChanged: (selected) => onChange(selected.single),
            ),
          ),
      ],
    );
  }
}

/// Al volver a triar una sección que ya tiene algo (paso 4): agregar,
/// actualizar, reemplazar o quitar. Con un solo cambio posible —triar algo
/// nuevo—, no se muestra nada.
///
/// Una sección entera la muestra solo prendida: se elige al prenderla. Una
/// lista —las notas, los fragmentos— no tiene interruptor, así que la
/// muestra siempre que ya tenga partes, en «Agregar» mientras no se pida otra
/// cosa: se puede quitar o empezar de nuevo sin sumarle nada antes.
class _ChangeChoice extends StatelessWidget {
  const _ChangeChoice({
    required this.section,
    required this.sheet,
    required this.onChange,
  });

  final ProcessedSection section;
  final _SheetContext sheet;
  final ValueChanged<ProcessedChange> onChange;

  @override
  Widget build(BuildContext context) {
    final changes = sheet.changesFor(section);
    final current =
        sheet.triage.choices[section]?.change ?? ProcessedChange.add;
    if (changes.length < 2) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(left: 40, bottom: 8),
      child: SegmentedButton<ProcessedChange>(
        key: Key('triage-change-${section.name}'),
        showSelectedIcon: false,
        segments: [
          for (final change in changes)
            ButtonSegment(
              value: change,
              label: Text(triageChangeLabel(l10n, change)),
            ),
        ],
        selected: {current},
        onSelectionChanged: (selected) => onChange(selected.single),
      ),
    );
  }
}

/// Una lista que arma la persona —las notas, los fragmentos—: cuánto lleva,
/// cómo sumarle y cada pasaje con «Quitar».
class _ClipsSection extends StatelessWidget {
  const _ClipsSection({
    required this.section,
    required this.sheet,
    required this.onWrite,
    required this.onCut,
    required this.onRemove,
    required this.onChange,
  });

  final ProcessedSection section;
  final _SheetContext sheet;
  final VoidCallback onWrite;
  final VoidCallback onCut;
  final ValueChanged<String> onRemove;
  final ValueChanged<ProcessedChange> onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clips = sheet.triage.clipsOf(section);
    final existing = sheet.triage.existing[section] ?? 0;
    final hasText = sheet.material.hasText;
    final actions = switch (section) {
      ProcessedSection.notes => [
        OutlinedButton.icon(
          key: const Key('triage-write-note'),
          onPressed: onWrite,
          icon: const Icon(Icons.edit_note, size: 18),
          label: Text(l10n.processedTriageWriteNote),
        ),
        if (hasText)
          OutlinedButton.icon(
            key: const Key('triage-extract-note'),
            onPressed: onCut,
            icon: const Icon(Icons.content_cut, size: 18),
            label: Text(l10n.processedTriageExtractNote),
          ),
      ],
      ProcessedSection.fragments => [
        FilledButton.tonalIcon(
          key: const Key('triage-cut'),
          onPressed: onCut,
          icon: const Icon(Icons.content_cut, size: 18),
          label: Text(l10n.processedCutTitle),
        ),
      ],
      _ => const <Widget>[],
    };

    return Column(
      key: Key('triage-section-${section.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(triageSectionIcon(section)),
          title: Text(triageSectionLabel(l10n, section)),
          // Con algo pedido —pasajes, o quitarla entera—, cómo va a quedar.
          subtitle: sheet.triage.edits.containsKey(section)
              ? _PreviewText(sheet: sheet, section: section)
              : Text(
                  existing > 0
                      ? l10n.processedTriageExisting(existing)
                      : l10n.processedTriageNothingYet,
                ),
        ),
        _ChangeChoice(section: section, sheet: sheet, onChange: onChange),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Wrap(spacing: 8, runSpacing: 8, children: actions),
        ),
        for (final clip in clips)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: TriageClipTile(
              clip: clip,
              section: section,
              onRemove: () => onRemove(clip.id),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Lo que la fuente ofrece para elegir de a una —sus imágenes, decisión L—:
/// cuántas trae y cuánto pesan, lo que va a ocupar lo elegido y la grilla.
class _GallerySection extends ConsumerWidget {
  const _GallerySection({
    required this.section,
    required this.sheet,
    required this.onChange,
  });

  final ProcessedSection section;
  final _SheetContext sheet;
  final ValueChanged<ProcessedChange> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final offer = sheet.material.images;
    final existing = sheet.triage.existing[section] ?? 0;
    final controller = ref.read(
      processedTriageProvider(sheet.triage.sourceItemId).notifier,
    );
    final offerText = l10n.processedTriageImagesOffer(
      offer.count,
      formatFileSize(offer.sizeBytes, l10n.localeName),
    );
    final removing =
        sheet.triage.choices[section]?.change == ProcessedChange.remove;

    return Column(
      key: Key('triage-section-${section.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(triageSectionIcon(section)),
          title: Text(triageSectionLabel(l10n, section)),
          subtitle: sheet.triage.edits.containsKey(section)
              ? _PreviewText(sheet: sheet, section: section)
              : Text(
                  [
                    if (existing > 0) l10n.processedTriageExisting(existing),
                    offerText,
                  ].join(' · '),
                ),
        ),
        _ChangeChoice(section: section, sheet: sheet, onChange: onChange),
        // Quitar la sección entera no elige nada: la grilla no hace falta.
        if (!removing)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 8),
            child: TriageImageGrid(
              sourceItemId: sheet.triage.sourceItemId,
              count: offer.count,
              choice: sheet.triage.images,
              onToggle: controller.toggleImage,
              onAll: controller.chooseAllImages,
              onNone: controller.chooseNoImages,
            ),
          ),
      ],
    );
  }
}

/// Cuánto va a tener [section]: «12 páginas · 3.400 palabras», en vivo.
class _PreviewText extends ConsumerWidget {
  const _PreviewText({required this.sheet, required this.section});

  final _SheetContext sheet;
  final ProcessedSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final key = sheet.previewKeyOf(section);
    if (key == null) return Text(l10n.processedTriageNothingYet);
    final preview = ref.watch(processedTriagePreviewProvider(key));
    return Text(
      key: Key('triage-preview-${section.name}'),
      switch (preview.valueOrNull) {
        null => l10n.processedTriageCounting,
        final result => result.match(
          (_) => l10n.processedTriageNothingYet,
          (preview) => previewText(
            l10n,
            section,
            preview,
            existing: sheet.triage.existing[section] ?? 0,
          ),
        ),
      },
    );
  }
}

/// «12 páginas · 3.400 palabras»: lo que va a tener una sección.
///
/// Al volver a triar una sección que ya tiene [existing] partes, dice además
/// cuánto cambia —«suma 2 · saca 1», o «sin cambios»—, y si se queda sin
/// nada, que queda vacía.
///
/// En las imágenes, en vez de las palabras, lo que va a ocupar la copia de lo
/// que se suma: «8 imágenes · ocupa 4,3 MB».
String previewText(
  AppLocalizations l10n,
  ProcessedSection section,
  SectionPreview preview, {
  int existing = 0,
}) {
  final parts = triagePartsText(l10n, section, preview.parts);
  final size = preview.parts == 0
      ? (existing > 0
            ? l10n.processedTriageEmptied
            : l10n.processedTriageNothingYet)
      : section.holdsFiles
      ? l10n.processedTriageImagesSize(
          parts,
          formatFileSize(preview.addedBytes, l10n.localeName),
        )
      : '$parts · ${l10n.processedTriageWordCount(preview.words)}';
  if (existing == 0) return size;
  final tally = preview.tally;
  final changes = [
    if (tally.added > 0) l10n.processedTriageTallyAdds(tally.added),
    if (tally.removed > 0) l10n.processedTriageTallyRemoves(tally.removed),
  ];
  final change = changes.isEmpty
      ? l10n.processedTriageTallyNone
      : changes.join(' · ');
  return '$size · $change';
}

/// La vista previa de cada sección que va, de las que ya se sabe: para la
/// tarjeta «Va a quedar» y el total de abajo. Las mismas claves que las de
/// cada sección, así que no se calcula nada dos veces.
Map<ProcessedSection, SectionPreview> _watchPreviews(
  WidgetRef ref,
  _SheetContext sheet,
) => {
  for (final section in ProcessedSection.values)
    if (sheet.previewKeyOf(section) case final key?)
      if (ref.watch(processedTriagePreviewProvider(key)).valueOrNull
          case final result?)
        if (result.toNullable() case final preview?) section: preview,
};

/// «Va a quedar»: lo que va a tener el documento procesado, sección por
/// sección, en chips, y las teclas de la hoja. Al final de la lista, para que
/// con la letra grande no le quite lugar a lo que se elige.
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.sheet, required this.keys});

  final _SheetContext sheet;

  /// Cuántas secciones se prenden con un número.
  final int keys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final edits = sheet.triage.edits;
    final original = sheet.triage.original;
    final offer = sheet.material.original;
    final previews = _watchPreviews(ref, sheet);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              key: const Key('triage-preview'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.processedTriagePreviewTitle,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (sheet.triage.isEmpty)
                  Text(
                    l10n.processedTriagePreviewEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final section in ProcessedSection.values)
                        if (edits[section] case final edit?)
                          Chip(
                            key: Key('triage-preview-chip-${section.name}'),
                            avatar: Icon(triageSectionIcon(section), size: 16),
                            label: Text(
                              _chipText(l10n, section, edit, previews[section]),
                            ),
                          ),
                      if (original != null)
                        Chip(
                          key: const Key('triage-preview-chip-original'),
                          avatar: const Icon(
                            Icons.file_copy_outlined,
                            size: 16,
                          ),
                          label: Text(
                            offer == null || original == ProcessedChange.remove
                                ? l10n.processedTriageSectionOriginal
                                : l10n.processedTriageOriginalChip(
                                    formatFileSize(
                                      offer.sizeBytes,
                                      l10n.localeName,
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  l10n.processedTriageKeysHint(keys),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// «Resumen · 14 oraciones»: el nombre de la sección y, si va a tener
  /// algo, cuánto.
  String _chipText(
    AppLocalizations l10n,
    ProcessedSection section,
    SectionEdit edit,
    SectionPreview? preview,
  ) {
    final label = triageSectionLabel(
      l10n,
      section,
      transcript: sheet.transcript,
    );
    if (preview == null || edit.change == ProcessedChange.remove) return label;
    return '$label · ${triagePartsText(l10n, section, preview.parts)}';
  }
}

/// Abajo, fijo y bajo: cuántas palabras van en total, el fallo de «Listo» si
/// lo hubo, y «Cancelar» y «Listo».
class _Actions extends ConsumerWidget {
  const _Actions({
    required this.sheet,
    required this.busy,
    required this.error,
    required this.onCancel,
    required this.onDone,
  });

  final _SheetContext sheet;
  final bool busy;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty = sheet.triage.isEmpty;
    final previews = _watchPreviews(ref, sheet).values;
    final words = previews.fold<int>(0, (sum, p) => sum + p.words);
    final bytes = previews.fold<int>(0, (sum, p) => sum + p.addedBytes);

    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error,
                  key: const Key('triage-error'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    empty
                        ? l10n.processedTriageNothingChosen
                        : [
                            l10n.processedTriageTotalWords(words),
                            if (bytes > 0)
                              l10n.processedTriageTotalImages(
                                formatFileSize(bytes, l10n.localeName),
                              ),
                          ].join(' · '),
                    key: const Key('triage-total'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : onCancel,
                  child: Text(l10n.commonCancel),
                ),
                FilledButton.icon(
                  key: const Key('triage-done'),
                  onPressed: empty || busy ? null : onDone,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(l10n.processedCutDone),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Escribir una nota para el documento procesado: un campo de varias líneas
/// y «Agregar». Cancelar no suma nada; en blanco, tampoco.
class _WriteNoteDialog extends StatefulWidget {
  const _WriteNoteDialog();

  @override
  State<_WriteNoteDialog> createState() => _WriteNoteDialogState();
}

class _WriteNoteDialogState extends State<_WriteNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    Navigator.of(context).pop(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.processedTriageNoteDialogTitle),
      content: TextField(
        key: const Key('triage-note-field'),
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: l10n.processedTriageNoteDialogHint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            key: const Key('triage-note-add'),
            onPressed: _controller.text.trim().isEmpty ? null : _add,
            child: Text(l10n.processedTriageNoteDialogAdd),
          ),
        ),
      ],
    );
  }
}
