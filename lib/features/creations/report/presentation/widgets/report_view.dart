import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_canonical_text.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/features/creations/report/presentation/providers/report_providers.dart';
import 'package:sinapsis/features/creations/report/presentation/report_labels.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_index_sheet.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_notes.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_section_card.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_text.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_follow.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/domain/services/text_note_placement.dart';
import 'package:sinapsis/features/text_notes/presentation/providers/text_note_providers.dart';
import 'package:sinapsis/features/text_notes/presentation/text_note_actions.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_note_margin.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_notes_list_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo más ancho que se lee un informe: una línea más larga cansa la vista.
const kReportMaxWidth = 720.0;

/// El visor de un informe (F43, punto 5 del plan), debajo de la barra común
/// del visor: arriba, la plantilla y el formato, el título, la bajada, y el
/// índice y las palabras clave; después, cada sección en su tarjeta, que se
/// pliega con «⌃»; en el interactivo, al final, el puntaje y «Volver a
/// intentar».
///
/// Lo que se pliega, lo respondido y a dónde saltar viven en
/// [reportReadingProvider], que comparte con el botón del índice de la barra.
class ReportView extends ConsumerStatefulWidget {
  const ReportView({required this.creation, super.key});

  final StudyCreation creation;

  @override
  ConsumerState<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends ConsumerState<ReportView> {
  final _sectionKeys = <int, GlobalKey>{};

  /// Las partes del informe que se ven ahora (F45, paso 8c).
  final _parts = ReportNoteParts();

  /// La nota a la que se fue desde «Notas (N)», marcada un momento.
  late final _flash = ReportNoteFlash(() {
    if (mounted) setState(() {});
  });

  /// El texto del informe que se muestra, armado una vez por contenido.
  (String?, ReportText)? _text;

  ReportText _textOf(String? content, Report report) {
    final cached = _text;
    if (cached != null && cached.$1 == content) return cached.$2;
    final text = ReportText.of(report);
    _text = (content, text);
    return text;
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  GlobalKey _keyOf(int section) =>
      _sectionKeys.putIfAbsent(section, GlobalKey.new);

  /// Lleva la sección [section] arriba, sin animar si la persona pidió «sin
  /// animaciones».
  void _jumpTo(int section) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _sectionKeys[section]?.currentContext;
      if (target == null || !target.mounted) return;
      final still = MediaQuery.disableAnimationsOf(context);
      Scrollable.ensureVisible(
        target,
        alignment: 0.02,
        duration: still ? Duration.zero : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Lleva la vista a `[start, end)` del texto del informe y lo marca un
  /// momento: lo que hace tocar una nota en «Notas (N)». Si su sección estaba
  /// plegada, la despliega. `false` si el informe no lo muestra —una pregunta
  /// en el formato de lectura—.
  bool _revealNote(ReportText text, int start, int end) {
    final part = text.firstPartOf(start, end);
    if (part == null) return false;
    final place = part.place;
    final interactive =
        ReportFormat.of(widget.creation.options) == ReportFormat.interactive;
    if (place.interactiveOnly && !interactive) return false;
    final id = widget.creation.id;
    if (place.section >= 0 &&
        ref.read(reportReadingProvider(id)).folded.contains(place.section)) {
      ref.read(reportReadingProvider(id).notifier).toggleFold(place.section);
    }
    _flash.show(start, end);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _parts.contextOf(place);
      if (target == null || !target.mounted || !mounted) return;
      unawaited(
        Scrollable.ensureVisible(target, alignment: ReadAloudBand.landing),
      );
    });
    return true;
  }

  /// El menú de lo elegido: sobre el texto del informe, «Nota» (F45, paso
  /// 8c), y lo de siempre.
  Widget _selectionMenu(
    BuildContext context,
    SelectableRegionState region,
    ReportText text,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final chosen = _parts.selected(text);
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: region.contextMenuAnchors,
      buttonItems: [
        // Primero: en un teléfono, lo que no entra va a «Más».
        if (chosen != null)
          ContextMenuButtonItem(
            label: l10n.highlightAddNote,
            onPressed: () {
              ContextMenuController.removeAny();
              region.clearSelection();
              unawaited(
                writeTextNote(
                  this.context,
                  ref,
                  target: TextNoteTarget.creation(widget.creation.id),
                  start: chosen.start,
                  end: chosen.end,
                  excerpt: text.content.substring(chosen.start, chosen.end),
                ),
              );
            },
          ),
        ...region.contextMenuButtonItems,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final creation = widget.creation;
    final id = creation.id;
    final report = ref.watch(reportOfContentProvider(creation.content));
    final reading = ref.watch(reportReadingProvider(id));
    final notifier = ref.read(reportReadingProvider(id).notifier);
    ref.listen(reportReadingProvider(id).select((s) => s.jumps), (_, _) {
      final target = ref.read(reportReadingProvider(id)).jumpTo;
      if (target != null) _jumpTo(target);
    });
    final t = ReportTypography.of(context);

    if (report.isEmpty) {
      return Center(
        key: const Key('report-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.f43ReportEmpty,
            textAlign: TextAlign.center,
            style: t.subtitle,
          ),
        ),
      );
    }

    final template = ReportTemplate.of(creation.options);
    final format = ReportFormat.of(creation.options);
    final interactive = format == ReportFormat.interactive;
    final sources = CreationSourceIds(creation.sourceIds);
    final keywords = ref.watch(
      reportKeywordsProvider(reportKeywordsKeyOf(creation)),
    );
    final byDefault = ref.watch(reportKeywordsShownByDefaultProvider(sources));
    final keywordsOn = reading.keywords ?? byDefault;
    final painted = keywordsOn ? keywords : ReportKeywords.empty;

    // Las notas (F45, paso 8c): sobre el texto del informe, cada una en su
    // lugar; las que tienen lugar llevan su punteado y su globito.
    final text = _textOf(creation.content, report);
    final target = TextNoteTarget.creation(id);
    final notes =
        ref
            .watch(
              placedTextNotesProvider((target: target, content: text.content)),
            )
            .valueOrNull ??
        const <PlacedTextNote>[];
    final placed = [
      for (final note in notes)
        if (note.placed) note,
    ];
    // El margen de los globitos aparece con la primera nota con lugar, a la
    // derecha: el informe se corre lo que mide y ni una letra queda tapada.
    final gutter = placed.isEmpty ? 0.0 : _gutter;

    final view = SingleChildScrollView(
      key: const Key('report-view'),
      padding: EdgeInsets.fromLTRB(16, 20, placed.isEmpty ? 16 : 4, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: kReportMaxWidth + gutter),
          child: TextNoteMargin(
            gutter: gutter,
            notes: placed,
            lineOf: (note) => _parts.lineOf(text, note.start!, note.end!),
            onOpen: _openNotes,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  report: report,
                  kicker: l10n.reportKicker(template, format),
                  interactive: interactive,
                  keywordsAvailable: !keywords.isEmpty,
                  keywordsOn: keywordsOn,
                  onKeywords: (on) => notifier.setKeywords(shown: on),
                  onIndex: () => showReportIndex(context, creation),
                  typography: t,
                ),
                const SizedBox(height: 20),
                for (final (i, section) in report.sections.indexed) ...[
                  if (i > 0) const SizedBox(height: 14),
                  ReportSectionCard(
                    key: _keyOf(i),
                    section: section,
                    index: i,
                    title: l10n.reportSectionTitle(report, i),
                    folded: reading.folded.contains(i),
                    onToggle: () => notifier.toggleFold(i),
                    keywords: painted,
                    interactive: interactive,
                    answers: {
                      for (final MapEntry(key: (s, q), :value)
                          in reading.answers.entries)
                        if (s == i) q: value,
                    },
                    onAnswer: (q, option) => notifier.answer(i, q, option),
                    typography: t,
                  ),
                ],
                if (interactive && report.questionCount > 0) ...[
                  const SizedBox(height: 20),
                  _Score(
                    report: report,
                    answers: reading.answers,
                    onReset: notifier.resetAnswers,
                    typography: t,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    // Las notas de lo creado (F45, pasos 8b y 8c): sobre lo que se elija del
    // informe —con «Nota» en el menú de lo elegido— o sobre el informe
    // entero, desde «Notas (N)» de ⋮, que lleva a cada una.
    return ReadingNotesOffer(
      sources: [
        TextNoteSource(
          target: target,
          content: text.content,
          reveal: (start, end) => _revealNote(text, start, end),
        ),
      ],
      child: ReportNotes(
        text: text,
        notes: placed,
        parts: _parts,
        flash: _flash.range,
        onOpen: _openNotes,
        child: SelectionArea(
          contextMenuBuilder: (context, region) =>
              _selectionMenu(context, region, text),
          child: view,
        ),
      ),
    );
  }

  void _openNotes(List<TextNote> notes) =>
      unawaited(openTextNotes(context, ref, notes));

  /// El margen de los globitos: lo que mide el de una columna de lectura
  /// angosta, más el aire de la tarjeta.
  static const _gutter = 28.0;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.report,
    required this.kicker,
    required this.interactive,
    required this.keywordsAvailable,
    required this.keywordsOn,
    required this.onKeywords,
    required this.onIndex,
    required this.typography,
  });

  final Report report;
  final String kicker;
  final bool interactive;
  final bool keywordsAvailable;
  final bool keywordsOn;
  final ValueChanged<bool> onKeywords;
  final VoidCallback onIndex;
  final ReportTypography typography;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = typography;
    final meta = [
      l10n.f43ReportSections(report.sections.length),
      if (interactive && report.questionCount > 0)
        l10n.f43ReportQuestions(report.questionCount),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kicker.toUpperCase(),
            key: const Key('report-kicker'),
            style: t.kicker,
          ),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: ReportPartText.plain(
              place: const ReportTextPlace.title(),
              text: report.title,
              style: t.title,
              typography: t,
              textKey: const Key('report-title'),
            ),
          ),
          if (report.subtitle.isNotEmpty) ...[
            const SizedBox(height: 10),
            ReportPartText.plain(
              place: const ReportTextPlace.subtitle(),
              text: report.subtitle,
              style: t.subtitle,
              typography: t,
            ),
          ],
          const SizedBox(height: 10),
          Text(meta, style: t.small),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                key: const Key('report-open-index'),
                avatar: const Icon(Icons.toc, size: 18),
                label: Text(l10n.f43ReportIndex),
                shape: const StadiumBorder(),
                onPressed: onIndex,
              ),
              if (keywordsAvailable)
                FilterChip(
                  key: const Key('report-keywords'),
                  avatar: keywordsOn
                      ? null
                      : Icon(Icons.circle, size: 12, color: t.keyword),
                  label: Text(l10n.f43ReportKeywords),
                  shape: const StadiumBorder(),
                  selected: keywordsOn,
                  onSelected: onKeywords,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// El puntaje del informe entero, al final del interactivo, con «Volver a
/// intentar».
class _Score extends StatelessWidget {
  const _Score({
    required this.report,
    required this.answers,
    required this.onReset,
    required this.typography,
  });

  final Report report;
  final Map<(int, int), int> answers;
  final VoidCallback onReset;
  final ReportTypography typography;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final t = typography;
    final total = report.questionCount;
    var correct = 0;
    for (final MapEntry(key: (s, q), :value) in answers.entries) {
      if (report.sections[s].questions[q].answer == value) correct++;
    }
    final done = answers.length == total;
    return Container(
      key: const Key('report-score'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: t.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  done
                      ? l10n.f43ReportTotalScore(correct, total)
                      : l10n.f43ReportAnswered(answers.length, total),
                  style: t.subheading,
                ),
              ),
            ],
          ),
          if (answers.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('report-try-again'),
              onPressed: onReset,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.f43ReportTryAgain),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onSurface,
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
