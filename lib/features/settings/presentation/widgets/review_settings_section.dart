import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder_controller.dart';
import 'package:sinapsis/features/study_reminder/presentation/providers/study_reminder_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Opciones de «tarjetas nuevas por día»: de a poco a mucho, y sin tope.
const kNewPerDayChoices = [5, 10, 20, 30, 50, 100, StudyLimits.maxPerDay];

/// Opciones de «repasos por día».
const kReviewsPerDayChoices = [
  50,
  100,
  200,
  300,
  500,
  1000,
  StudyLimits.maxPerDay,
];

/// La sección «Repasar» de Ajustes (F31, decisión 73): el aviso diario, los
/// límites por día y el camino a Anki, hacia adentro y hacia afuera.
class ReviewSettingsSection extends ConsumerStatefulWidget {
  const ReviewSettingsSection({super.key});

  @override
  ConsumerState<ReviewSettingsSection> createState() =>
      _ReviewSettingsSectionState();
}

class _ReviewSettingsSectionState extends ConsumerState<ReviewSettingsSection>
    with WidgetsBindingObserver {
  /// La persona intentó prender el aviso y el sistema no le dio permiso.
  var _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes del sistema, donde se pudo conceder o quitar el
  /// permiso, se vuelve a leer cómo está.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(studyReminderStateProvider.notifier).refresh();
    }
  }

  Future<void> _toggleReminder({required bool on}) async {
    final notifier = ref.read(studyReminderStateProvider.notifier);
    if (!on) {
      setState(() => _permissionDenied = false);
      await notifier.disable();
      return;
    }
    final result = await notifier.enable(
      studyCount: ref.read(studyDueTodayCountProvider).valueOrNull,
    );
    if (!mounted) return;
    setState(
      () => _permissionDenied =
          result == StudyReminderEnableResult.permissionDenied,
    );
  }

  Future<void> _pickTime(ReminderTime current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !mounted) return;
    await ref
        .read(studyReminderStateProvider.notifier)
        .changeTime(ReminderTime(picked.hour, picked.minute));
  }

  Future<void> _pickLimit({
    required String title,
    required List<int> choices,
    required int current,
    required Future<void> Function(int) onPicked,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final options = {...choices, current}.toList()..sort();
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<int>(
            groupValue: current,
            onChanged: (value) => Navigator.of(context).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in options)
                  RadioListTile<int>(
                    key: Key('review-limit-choice-$value'),
                    title: Text(_limitLabel(l10n, value)),
                    value: value,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await onPicked(picked);
  }

  String _limitLabel(AppLocalizations l10n, int value) =>
      value >= StudyLimits.maxPerDay
      ? l10n.reviewSettingsNoLimit
      : l10n.reviewSettingsLimitValue(value);

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context)!;
    final scope = await showDialog<({bool exportAll, AnkiExportFormat format})>(
      context: context,
      builder: (context) => const _ExportDialog(),
    );
    if (scope == null || !mounted) return;

    final result = await ref.read(exportFlashcardsToAnkiUseCaseProvider)(
      ExportFlashcardsToAnkiParams(
        exportAll: scope.exportAll,
        format: scope.format,
      ),
    );
    if (!mounted) return;
    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final limits = ref.watch(studyLimitsProvider);
    final reminder = ref.watch(studyReminderStateProvider).valueOrNull;
    final limitsNotifier = ref.read(studyLimitsProvider.notifier);

    final tiles = <Widget>[
      if (reminder != null && reminder.supported) ...[
        SwitchListTile(
          key: const Key('review-settings-reminder-switch'),
          secondary: const Icon(Icons.notifications_active_outlined),
          title: Text(l10n.reviewSettingsReminderTitle),
          subtitle: Text(l10n.reviewSettingsReminderSubtitle),
          value: reminder.enabled,
          onChanged: (on) => _toggleReminder(on: on),
        ),
        if (reminder.enabled)
          ListTile(
            key: const Key('review-settings-reminder-time'),
            leading: const Icon(Icons.schedule_outlined),
            title: Text(l10n.reviewSettingsReminderTime),
            subtitle: Text(
              MaterialLocalizations.of(context).formatTimeOfDay(
                TimeOfDay(
                  hour: reminder.time.hour,
                  minute: reminder.time.minute,
                ),
              ),
            ),
            onTap: () => _pickTime(reminder.time),
          ),
        if (reminder.enabled || _permissionDenied) ...[
          if (!reminder.permissionGranted)
            ListTile(
              key: const Key('review-settings-permission'),
              leading: Icon(
                Icons.notifications_off_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                l10n.reviewSettingsPermissionMissing,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const Key('review-settings-open-system-settings'),
                    onPressed: () => ref
                        .read(studyReminderStateProvider.notifier)
                        .openNotificationSettings(),
                    child: Text(l10n.reviewSettingsOpenSystemSettings),
                  ),
                ),
              ),
            )
          else
            ListTile(
              key: const Key('review-settings-permission'),
              leading: const Icon(Icons.check_circle_outline),
              title: Text(l10n.reviewSettingsPermissionOk),
            ),
        ],
        if (reminder.enabled)
          ListTile(
            key: const Key('review-settings-battery'),
            leading: const Icon(Icons.battery_alert_outlined),
            title: Text(
              l10n.reviewSettingsReminderBattery,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
      ListTile(
        key: const Key('review-settings-new-limit'),
        leading: const Icon(Icons.fiber_new_outlined),
        title: Text(l10n.reviewSettingsNewLimit),
        subtitle: Text(_limitLabel(l10n, limits.newPerDay)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _pickLimit(
          title: l10n.reviewSettingsNewLimit,
          choices: kNewPerDayChoices,
          current: limits.newPerDay,
          onPicked: limitsNotifier.setNewPerDay,
        ),
      ),
      ListTile(
        key: const Key('review-settings-review-limit'),
        leading: const Icon(Icons.repeat_outlined),
        title: Text(l10n.reviewSettingsReviewLimit),
        subtitle: Text(
          '${_limitLabel(l10n, limits.reviewsPerDay)}\n'
          '${l10n.reviewSettingsLimitsHint}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _pickLimit(
          title: l10n.reviewSettingsReviewLimit,
          choices: kReviewsPerDayChoices,
          current: limits.reviewsPerDay,
          onPicked: limitsNotifier.setReviewsPerDay,
        ),
      ),
      // Traer un `.apkg` necesita SQLite nativo: no existe en la web.
      if (!kIsWeb)
        ListTile(
          key: const Key('review-settings-import-anki'),
          leading: const Icon(Icons.file_download_outlined),
          title: Text(l10n.reviewSettingsImportAnki),
          subtitle: Text(l10n.reviewSettingsImportAnkiSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(kRouteAnkiImport),
        ),
      ListTile(
        key: const Key('review-settings-export-anki'),
        leading: const Icon(Icons.file_upload_outlined),
        title: Text(l10n.reviewSettingsExportAnki),
        subtitle: Text(l10n.reviewSettingsExportAnkiSubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: _export,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            l10n.reviewSettingsTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                tiles[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Qué exportar a Anki y en qué formato.
class _ExportDialog extends StatefulWidget {
  const _ExportDialog();

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  var _exportAll = false;
  var _format = AnkiExportFormat.apkg;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.reviewExportToAnkiTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('review-settings-export-all'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.reviewExportToAnkiExportAll),
            value: _exportAll,
            onChanged: (value) => setState(() => _exportAll = value),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.reviewExportToAnkiFormatTitle,
            style: theme.textTheme.labelLarge,
          ),
          RadioGroup<AnkiExportFormat>(
            groupValue: _format,
            onChanged: (value) => setState(() => _format = value!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final format in AnkiExportFormat.values)
                  RadioListTile<AnkiExportFormat>(
                    key: Key('review-settings-export-format-${format.name}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(switch (format) {
                      AnkiExportFormat.apkg =>
                        l10n.reviewExportToAnkiFormatApkg,
                      AnkiExportFormat.tsv => l10n.reviewExportToAnkiFormatTsv,
                      AnkiExportFormat.csv => l10n.reviewExportToAnkiFormatCsv,
                    }),
                    value: format,
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('review-settings-export-confirm'),
          onPressed: () => Navigator.of(
            context,
          ).pop((exportAll: _exportAll, format: _format)),
          child: Text(l10n.reviewExportToAnkiConfirm),
        ),
      ],
    );
  }
}
