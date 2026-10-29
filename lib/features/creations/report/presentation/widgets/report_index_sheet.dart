import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/features/creations/report/presentation/providers/report_providers.dart';
import 'package:sinapsis/features/creations/report/presentation/report_labels.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre el índice de [creation]: tocar una sección salta hasta ella —y la
/// despliega si estaba plegada—; arriba, plegar o desplegar todo.
Future<void> showReportIndex(BuildContext context, StudyCreation creation) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => ReportIndexSheet(creation: creation),
    );

/// El índice de un informe: sus secciones numeradas, con lo respondido de
/// cada una en el interactivo.
class ReportIndexSheet extends ConsumerWidget {
  const ReportIndexSheet({required this.creation, super.key});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final t = ReportTypography.of(context);
    final report = ref.watch(reportOfContentProvider(creation.content));
    final reading = ref.watch(reportReadingProvider(creation.id));
    final notifier = ref.read(reportReadingProvider(creation.id).notifier);
    final interactive =
        ReportFormat.of(creation.options) == ReportFormat.interactive;
    final count = report.sections.length;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        key: const Key('report-index'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.f43ReportIndex,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                CreationCloseButton(tooltip: l10n.f43StudioClose),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  key: const Key('report-fold-all'),
                  avatar: const Icon(Icons.unfold_less, size: 18),
                  label: Text(l10n.f43ReportFoldAll),
                  shape: const StadiumBorder(),
                  onPressed: () => notifier.foldAll(count),
                ),
                ActionChip(
                  key: const Key('report-unfold-all'),
                  avatar: const Icon(Icons.unfold_more, size: 18),
                  label: Text(l10n.f43ReportUnfoldAll),
                  shape: const StadiumBorder(),
                  onPressed: notifier.unfoldAll,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: count,
              itemBuilder: (context, i) {
                final section = report.sections[i];
                final questions = interactive
                    ? section.questions
                    : const <ReportQuestion>[];
                final answered = [
                  for (var q = 0; q < questions.length; q++)
                    if (reading.answers[(i, q)] case final picked?)
                      picked == section.questions[q].answer,
                ];
                return ListTile(
                  key: ValueKey('report-index-$i'),
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: t.accent.withValues(alpha: 0.16),
                    child: Text(
                      '${i + 1}',
                      style: t.small.copyWith(
                        color: t.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(l10n.reportSectionTitle(report, i)),
                  trailing:
                      questions.isNotEmpty &&
                          answered.length == questions.length
                      ? Text(
                          '${answered.where((ok) => ok).length}/'
                          '${questions.length}',
                          style: t.small.copyWith(
                            color: t.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : reading.folded.contains(i)
                      ? Icon(Icons.keyboard_arrow_down_rounded, color: t.muted)
                      : null,
                  onTap: () {
                    notifier.jump(i);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
