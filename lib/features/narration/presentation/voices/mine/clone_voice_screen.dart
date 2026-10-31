import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/narration/data/voices/my_voices_service.dart';
import 'package:sinapsis/features/narration/domain/services/voice_recorder.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/on_device_cloning.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_scripts.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/create_voice_screen.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/my_voice_widgets.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/voice_cloud_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/features/settings/presentation/providers/owner_name.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «Clonación de voz» (F47, paso 4) a pantalla completa, encima de todo.
Future<void> showCloneVoice(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const CloneVoiceScreen(),
      ),
    );

enum _Step { intro, consent, sample, clone }

/// De quién es la voz, en la pantalla: las dos que se pueden clonar y la que
/// no.
enum _Owner { own, permission, notAllowed }

/// Clonar una voz (F47, paso 4, captura 14), en cuatro pasos:
///
/// 1. **Qué es**: la presentación, y dónde se clona —en el teléfono todavía
///    no (ver [OnDeviceCloning]); en ElevenLabs, si la nube está prendida—.
/// 2. **De quién es la voz**: la tuya, o la de alguien que te dio permiso,
///    con su nombre; se confirma antes de grabar. La de un famoso o la de
///    alguien sin permiso no se clona: la app lo dice y propone crear una
///    voz describiendo el estilo.
/// 3. **La muestra**: grabar 1 o 2 minutos leyendo el texto propuesto, o
///    subir un audio; se mide el ruido y la duración, y se avisa si conviene
///    repetir.
/// 4. **Clonar**: el nombre y la cara, el costo, lo que sale del teléfono y
///    «Clonar en ElevenLabs».
class CloneVoiceScreen extends ConsumerStatefulWidget {
  const CloneVoiceScreen({super.key});

  @override
  ConsumerState<CloneVoiceScreen> createState() => _CloneVoiceScreenState();
}

class _CloneVoiceScreenState extends ConsumerState<CloneVoiceScreen> {
  var _step = _Step.intro;
  _Owner? _owner;
  final _person = TextEditingController();
  final _name = TextEditingController();
  var _confirmed = false;

  /// En qué idioma va a leer la voz: de entrada, el de la app.
  late String _locale = Localizations.localeOf(context).languageCode == 'en'
      ? 'en-US'
      : 'es-AR';

  // La muestra.
  File? _sample;
  var _uploaded = false;
  RecordingReport? _report;
  var _recording = false;
  var _analyzing = false;
  RecordingProgress? _progress;
  StreamSubscription<RecordingProgress>? _recordingEvents;
  String? _sampleError;

  // Clonar.
  var _faceSeed = 0;
  var _cloning = false;
  String? _cloneError;

  @override
  void initState() {
    super.initState();
    _person.addListener(() => setState(() {}));
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    unawaited(_recordingEvents?.cancel());
    if (_recording) unawaited(ref.read(voiceRecorderProvider).stop());
    _person.dispose();
    _name.dispose();
    super.dispose();
  }

  // --- Grabar y subir ------

  Future<void> _record() async {
    final recorder = ref.read(voiceRecorderProvider);
    setState(() {
      _sampleError = null;
      _report = null;
    });
    if (!await recorder.requestPermission()) {
      if (mounted) setState(() => _sampleError = 'permission');
      return;
    }
    final file = await ref.read(voiceSampleToolsProvider).newRecording();
    if (!mounted) return;
    setState(() {
      _recording = true;
      _progress = null;
      _sample = file;
      _uploaded = false;
    });
    _recordingEvents = recorder
        .record(outputPath: file.path, limit: RecordingReport.recordingLimit)
        .listen(
          (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _recording = false;
              _sampleError = error is VoiceRecorderException
                  ? error.code
                  : 'audio';
            });
          },
          onDone: () => unawaited(_recorded(file)),
        );
  }

  Future<void> _recorded(File file) async {
    if (!mounted || !_recording) return;
    setState(() {
      _recording = false;
      _analyzing = true;
    });
    await _measure(() => ref.read(voiceSampleToolsProvider).analyze(file));
  }

  Future<void> _stop() => ref.read(voiceRecorderProvider).stop();

  Future<void> _upload() async {
    setState(() {
      _sampleError = null;
      _report = null;
    });
    final picked = await ref.read(fileChooserProvider).pickOne();
    if (picked == null || !mounted) return;
    setState(() => _analyzing = true);
    await _measure(() async {
      final (file, report) = await ref
          .read(voiceSampleToolsProvider)
          .importUpload(picked);
      _sample = file;
      _uploaded = true;
      return report;
    });
  }

  Future<void> _measure(Future<RecordingReport> Function() measure) async {
    try {
      final report = await measure();
      if (mounted) setState(() => _report = report);
    } on Object {
      if (mounted) setState(() => _sampleError = 'unreadable');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  // --- Clonar ------

  Future<void> _clone() async {
    final sample = _sample;
    final report = _report;
    if (sample == null || report == null) return;
    setState(() {
      _cloning = true;
      _cloneError = null;
    });
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final voice = await ref
          .read(myVoicesServiceProvider)
          .cloneInCloud(
            name: _name.text,
            locale: _locale,
            consent: VoiceConsent(
              kind: _owner == _Owner.own
                  ? VoiceConsentKind.own
                  : VoiceConsentKind.permission,
              personName: _person.text.trim(),
              grantedAt: ref.read(clockProvider)().toUtc(),
            ),
            sample: sample,
            report: report,
            uploaded: _uploaded,
            faceSeed: _faceSeed,
          );
      messenger.showAppSnackBar(
        AppSnackBar(content: Text(l10n.f47P4Saved(voice.name))),
      );
      navigator.pop();
    } on VoiceCloudException catch (error) {
      if (mounted) {
        setState(
          () => _cloneError = voiceCloudFailureText(error.failure, l10n),
        );
      }
    } on Object {
      if (mounted) setState(() => _cloneError = l10n.f47P4FailUnknown);
    } finally {
      if (mounted) setState(() => _cloning = false);
    }
  }

  // --- La pantalla ------

  void _go(_Step step) => setState(() => _step = step);

  bool get _consentReady =>
      _owner != null &&
      _owner != _Owner.notAllowed &&
      _person.text.trim().isNotEmpty &&
      _confirmed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_recording && !_cloning,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.f47P4CloneTitle),
          leading: _step == _Step.intro
              ? const CloseButton()
              : BackButton(
                  onPressed: _recording || _cloning
                      ? null
                      : () => _go(_Step.values[_step.index - 1]),
                ),
        ),
        body: SafeArea(
          // Una columna entera y no una lista perezosa: cada paso es corto, y
          // así el lector de pantalla recorre todo, también lo de abajo.
          child: SingleChildScrollView(
            key: Key('clone-voice-${_step.name}'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: switch (_step) {
                _Step.intro => _intro(l10n),
                _Step.consent => _consent(l10n),
                _Step.sample => _sampleStep(l10n),
                _Step.clone => _cloneStep(l10n),
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _intro(AppLocalizations l10n) {
    final cloud = ref.watch(voiceCloudSettingsProvider);
    final available = ref.watch(myVoicesAvailableProvider);
    return [
      IntroSection(
        icon: Icons.record_voice_over_outlined,
        title: l10n.f47P4WhatTitle,
        text: l10n.f47P4CloneWhat,
      ),
      IntroSection(
        icon: Icons.mic_none_rounded,
        title: l10n.f47P4HowTitle,
        text: l10n.f47P4CloneHow,
      ),
      IntroSection(
        icon: Icons.delete_outline_rounded,
        title: l10n.f47P4DeleteTitle,
        text: l10n.f47P4CloneDelete,
      ),
      const SizedBox(height: 8),
      Semantics(
        header: true,
        child: Text(
          l10n.f47P4WhereTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      ListTile(
        key: const Key('clone-where-phone'),
        contentPadding: EdgeInsets.zero,
        enabled: OnDeviceCloning.available,
        leading: const Icon(Icons.smartphone_outlined),
        title: Text(l10n.f47P4WherePhone),
        subtitle: Text(l10n.f47P4ClonePhoneUnavailable),
      ),
      ListTile(
        key: const Key('clone-where-cloud'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_outlined),
        title: Text(l10n.f47P4WhereCloud),
        subtitle: Text(
          cloud.ready ? l10n.f47P4CloudReadyHint : l10n.f47P4CloudNeeded,
        ),
      ),
      // Debajo y no al costado: con la letra al doble, al costado no entra.
      if (!cloud.ready)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const Key('clone-open-cloud'),
            onPressed: () => unawaited(showVoiceCloudSheet(context)),
            child: Text(l10n.f47P4CloudOpen),
          ),
        ),
      if (!available) NoticeCard(text: l10n.f47P4OnlyAndroid),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('clone-start'),
        onPressed: cloud.ready && available ? () => _go(_Step.consent) : null,
        child: Text(l10n.f47P4Start),
      ),
    ];
  }

  List<Widget> _consent(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final owner = _owner;
    final person = _person.text.trim();
    return [
      Semantics(
        header: true,
        child: Text(l10n.f47P4WhoseTitle, style: theme.textTheme.titleMedium),
      ),
      RadioGroup<_Owner>(
        groupValue: owner,
        onChanged: (value) => setState(() {
          _owner = value;
          _confirmed = false;
          if (value == _Owner.own && _person.text.trim().isEmpty) {
            _person.text = ref.read(ownerNameProvider) ?? '';
          }
        }),
        child: Column(
          children: [
            RadioListTile<_Owner>(
              key: const Key('clone-owner-own'),
              contentPadding: EdgeInsets.zero,
              value: _Owner.own,
              title: Text(l10n.f47P4OwnerOwn),
            ),
            RadioListTile<_Owner>(
              key: const Key('clone-owner-permission'),
              contentPadding: EdgeInsets.zero,
              value: _Owner.permission,
              title: Text(l10n.f47P4OwnerPermission),
            ),
            RadioListTile<_Owner>(
              key: const Key('clone-owner-not-allowed'),
              contentPadding: EdgeInsets.zero,
              value: _Owner.notAllowed,
              title: Text(l10n.f47P4OwnerNotAllowed),
            ),
          ],
        ),
      ),
      if (owner == _Owner.notAllowed)
        NoticeCard(
          key: const Key('clone-not-allowed'),
          error: true,
          text: l10n.f47P4CloneNotAllowed,
          action: FilledButton.tonal(
            key: const Key('clone-go-create'),
            onPressed: () => unawaited(
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const CreateVoiceScreen(),
                ),
              ),
            ),
            child: Text(l10n.f47P4CreateInstead),
          ),
        )
      else if (owner != null) ...[
        const SizedBox(height: 8),
        TextField(
          key: const Key('clone-person'),
          controller: _person,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: owner == _Owner.own
                ? l10n.f47P4PersonOwn
                : l10n.f47P4PersonOther,
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('clone-confirm'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _confirmed,
          onChanged: person.isEmpty
              ? null
              : (value) => setState(() => _confirmed = value ?? false),
          title: Text(
            owner == _Owner.own
                ? l10n.f47P4ConsentOwn
                : l10n.f47P4ConsentOther(person.isEmpty ? '…' : person),
          ),
        ),
        Text(l10n.f47P4ConsentKept, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            l10n.f47P4LanguageTitle,
            style: theme.textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 8),
        LocaleChips(
          locales: cloudVoiceLocales,
          selected: _locale,
          onSelected: (locale) => setState(() => _locale = locale),
        ),
      ],
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('clone-consent-next'),
        onPressed: _consentReady
            ? () {
                if (_name.text.trim().isEmpty) _name.text = person;
                _go(_Step.sample);
              }
            : null,
        child: Text(l10n.f47P4Next),
      ),
    ];
  }

  List<Widget> _sampleStep(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final script = recordingScript(accentLanguage(_locale));
    final report = _report;
    final progress = _progress;
    final busy = _recording || _analyzing;
    return [
      Text(l10n.f47P4RecordHint),
      const SizedBox(height: 12),
      Card.outlined(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.f47P4ScriptTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                script ??
                    l10n.f47P4ScriptOther(
                      languageNameIn(accentLanguage(_locale), l10n),
                    ),
                key: const Key('clone-script'),
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (_recording) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.f47P4Recording(_clock(progress?.elapsed ?? Duration.zero)),
            key: const Key('clone-recording-time'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress?.level ?? 0,
          semanticsLabel: l10n.f47P4Level,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('clone-stop'),
          icon: const Icon(Icons.stop_rounded),
          label: Text(l10n.f47P4Stop),
          onPressed: () => unawaited(_stop()),
        ),
      ] else
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('clone-record'),
              icon: const Icon(Icons.mic_rounded),
              label: Text(report == null ? l10n.f47P4Record : l10n.f47P4Repeat),
              onPressed: busy ? null : () => unawaited(_record()),
            ),
            OutlinedButton.icon(
              key: const Key('clone-upload'),
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(l10n.f47P4Upload),
              onPressed: busy ? null : () => unawaited(_upload()),
            ),
          ],
        ),
      if (_analyzing) ...[
        const SizedBox(height: 16),
        Semantics(liveRegion: true, child: Text(l10n.f47P4Measuring)),
        const LinearProgressIndicator(),
      ],
      if (_sampleError case final error?)
        NoticeCard(
          key: const Key('clone-sample-error'),
          error: true,
          text: switch (error) {
            'permission' => l10n.f47P4MicPermission,
            'busy' => l10n.f47P4MicBusy,
            'unreadable' => l10n.f47P4Unreadable,
            _ => l10n.f47P4MicFailed,
          },
        ),
      if (report != null && !busy) ...[
        const SizedBox(height: 16),
        RecordingReportView(report: report),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('clone-use-sample'),
          onPressed: report.usable ? () => _go(_Step.clone) : null,
          child: Text(
            report.worthRepeating ? l10n.f47P4UseAnyway : l10n.f47P4UseSample,
          ),
        ),
      ],
    ];
  }

  List<Widget> _cloneStep(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern(l10n.localeName);
    final account = ref.watch(voiceCloudAccountProvider);
    final sampleCredits = readingCredits(
      MyVoicesService.sampleCharacters(accentLanguage(_locale)),
    );
    final blocked = switch (account) {
      AsyncData(:final value) => !value.canClone || value.hasVoiceSlot == false,
      _ => false,
    };
    return [
      TextField(
        key: const Key('clone-name'),
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: l10n.f47P4VoiceName),
      ),
      const SizedBox(height: 16),
      FacePicker(
        faceKey: _faceSeed == 0 ? 'nueva' : 'nueva#$_faceSeed',
        name: _name.text,
        onNext: () => setState(() => _faceSeed++),
      ),
      const SizedBox(height: 16),
      Semantics(
        header: true,
        child: Text(l10n.f47P4CostTitle, style: theme.textTheme.titleSmall),
      ),
      const SizedBox(height: 4),
      Text(
        l10n.f47P4CloneCost(
          ElevenLabsFacts.cloningPlan,
          ElevenLabsFacts.cloningPlanUsdPerMonth,
          number.format(sampleCredits),
        ),
        key: const Key('clone-cost'),
      ),
      const SizedBox(height: 8),
      Text(l10n.f47P4CloneLeaves, key: const Key('clone-leaves')),
      const SizedBox(height: 8),
      switch (account) {
        AsyncData(:final value) => Text(
          !value.canClone
              ? l10n.f47P4CloudCannotClone
              : value.hasVoiceSlot == false
              ? l10n.f47P4NoVoiceSlot
              : l10n.f47P4CreditsLeft(number.format(value.creditsLeft)),
          key: const Key('clone-account'),
          style: blocked ? TextStyle(color: theme.colorScheme.error) : null,
        ),
        AsyncError(:final error) => Text(
          error is VoiceCloudException
              ? voiceCloudFailureText(error.failure, l10n)
              : l10n.f47P4CreditsUnknown,
        ),
        _ => Text(l10n.f47P4CreditsChecking),
      },
      if (_cloneError case final error?)
        NoticeCard(key: const Key('clone-error'), error: true, text: error),
      const SizedBox(height: 24),
      if (_cloning) ...[
        Semantics(liveRegion: true, child: Text(l10n.f47P4Cloning)),
        const LinearProgressIndicator(),
      ] else
        FilledButton.icon(
          key: const Key('clone-confirm-cloud'),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(l10n.f47P4CloneInCloud),
          onPressed: _name.text.trim().isEmpty || blocked
              ? null
              : () => unawaited(_clone()),
        ),
    ];
  }

  static String _clock(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Cómo salió la muestra: la duración, la voz, el ruido, y qué conviene
/// arreglar.
class RecordingReportView extends StatelessWidget {
  const RecordingReportView({required this.report, super.key});

  final RecordingReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final issues = report.issues;
    return Card.outlined(
      key: const Key('recording-report'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                issues.isEmpty ? l10n.f47P4SampleGood : l10n.f47P4SampleRepeat,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.f47P4SampleStats(
                report.total.inSeconds,
                report.voiced.inSeconds,
                report.signalToNoiseDb.round(),
              ),
            ),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(switch (issue) {
                        RecordingIssue.tooLittleVoice =>
                          l10n.f47P4IssueTooLittle,
                        RecordingIssue.short => l10n.f47P4IssueShort,
                        RecordingIssue.tooLong => l10n.f47P4IssueTooLong,
                        RecordingIssue.quiet => l10n.f47P4IssueQuiet,
                        RecordingIssue.noisy => l10n.f47P4IssueNoisy,
                        RecordingIssue.clipping => l10n.f47P4IssueClipping,
                      }, key: Key('recording-issue-${issue.name}')),
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
