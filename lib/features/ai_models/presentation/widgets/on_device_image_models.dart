import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/core/util/external_url_launcher.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/ai_models/data/on_device/on_device_model_files.dart';
import 'package:sinapsis/features/ai_models/data/on_device/stable_diffusion_image_engine.dart';
import 'package:sinapsis/features/ai_models/domain/entities/device_profile.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/ai_models/domain/services/on_device_verdict.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/on_device_image_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «Imágenes en el teléfono (Exigente)» (F43, paso 3b), desde Ajustes →
/// IA.
Future<void> openOnDeviceImageScreen(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const OnDeviceImageScreen()));

/// «Imágenes en el teléfono (Exigente)»: lo que exige, el veredicto del
/// teléfono y una tarjeta por modelo, con sus pasos.
class OnDeviceImageScreen extends StatelessWidget {
  const OnDeviceImageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.f43DeviceScreenTitle)),
      body: ListView(
        key: const Key('on-device-image-screen'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            l10n.f43AiOnDeviceIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const OnDeviceImageModelsPanel(),
        ],
      ),
    );
  }
}

/// Lo de «Exigente — en el teléfono»: lo que exige, este teléfono, y las
/// tarjetas de SDXS-512 y SD-Turbo. Lo usan «¿Qué puede cada IA?» y la
/// pantalla de Ajustes. Vacío sin motor.
class OnDeviceImageModelsPanel extends ConsumerWidget {
  const OnDeviceImageModelsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(stableDiffusionImageEngineProvider) == null) {
      return const SizedBox.shrink();
    }
    return Column(
      key: const Key('on-device-models'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Requirements(),
        const SizedBox(height: 12),
        for (final model in OnDeviceImageModel.values) ...[
          OnDeviceModelCard(model: model),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Lo que exige la categoría, a la vista, y lo que tiene este teléfono.
class _Requirements extends ConsumerWidget {
  const _Requirements();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final device = ref.watch(onDeviceProfileProvider).valueOrNull;
    return Container(
      key: const Key('on-device-requirements'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.f43DeviceNeedsTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _Line(icon: Icons.memory_outlined, text: l10n.f43DeviceNeedRam),
          _Line(icon: Icons.sd_storage_outlined, text: l10n.f43DeviceNeedSpace),
          _Line(
            icon: Icons.device_thermostat_outlined,
            text: l10n.f43DeviceNeedHeat,
          ),
          _Line(
            icon: Icons.photo_size_select_large,
            text: l10n.f43DeviceNeed512,
          ),
          _Line(icon: Icons.wifi_off_outlined, text: l10n.f43DeviceNeedOffline),
          if (device != null) ...[
            const SizedBox(height: 8),
            _Line(
              key: const Key('on-device-this-phone'),
              icon: Icons.smartphone_outlined,
              text: _phoneLine(l10n, device),
              strong: true,
            ),
          ],
        ],
      ),
    );
  }

  static String _phoneLine(AppLocalizations l10n, DeviceProfile device) {
    final ram = device.ramGb;
    final free = device.freeStorageBytes;
    return [
      if (ram == null)
        l10n.f43DevicePhoneRamUnknown
      else
        l10n.f43DevicePhoneRam(ram),
      if (free != null)
        l10n.f43DevicePhoneFree(formatFileSize(free, l10n.localeName)),
    ].join(' · ');
  }
}

/// La tarjeta de un modelo: quién es, su licencia, lo que pesa y pide, si a
/// este teléfono le alcanza y por qué, lo que tarda, sus pasos y sus
/// botones.
class OnDeviceModelCard extends ConsumerStatefulWidget {
  const OnDeviceModelCard({required this.model, super.key});

  final OnDeviceImageModel model;

  @override
  ConsumerState<OnDeviceModelCard> createState() => _OnDeviceModelCardState();
}

class _OnDeviceModelCardState extends ConsumerState<OnDeviceModelCard> {
  CancelToken? _measuring;
  double? _pausedAt;

  OnDeviceImageModel get _model => widget.model;

  @override
  void initState() {
    super.initState();
    unawaited(_readPaused());
  }

  /// Lo que quedó de una descarga pausada (también de antes de cerrar la
  /// app), para ofrecer «Seguir».
  Future<void> _readPaused() async {
    final actions = ref.read(onDeviceImageActionsProvider);
    final paused = await actions?.pausedProgress(_model);
    if (mounted && paused != _pausedAt) setState(() => _pausedAt = paused);
  }

  void _say(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
      );
  }

  /// Corta la descarga (en curso o pausada) y vuelve a mirar lo que quedó
  /// a medias: lo que se leyó al pasar a quieta puede ser de antes de
  /// borrarlo.
  Future<void> _cancelDownload() async {
    await ref.read(onDeviceImageActionsProvider)?.cancel(_model);
    await _readPaused();
  }

  Future<void> _measure() async {
    final l10n = AppLocalizations.of(context)!;
    final actions = ref.read(onDeviceImageActionsProvider);
    if (actions == null) return;
    final cancel = CancelToken();
    setState(() => _measuring = cancel);
    try {
      final measured = await actions.measure(_model, cancel: cancel);
      if (!mounted) return;
      _say(
        l10n.f43DeviceMeasured(
          _model.spec.displayName,
          aiDuration(l10n, measured.perImage),
        ),
      );
    } on ImageGenerationException catch (error) {
      if (!mounted || error.failure == ImageFailure.cancelled) return;
      _say(
        l10n.f43DeviceMeasureFailed(illustrationReason(l10n, error.failure)),
      );
    } finally {
      if (mounted) setState(() => _measuring = null);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final spec = _model.spec;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.f43DeviceDeleteTitle(spec.displayName)),
        content: Text(
          l10n.f43DeviceDeleteBody(formatFileSize(spec.bytes, l10n.localeName)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const Key('on-device-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.f43DeviceDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(onDeviceImageActionsProvider)?.delete(_model);
    if (mounted) _say(l10n.f43DeviceDeleted(spec.displayName));
  }

  Future<void> _openLink() async {
    final l10n = AppLocalizations.of(context)!;
    final url = _model.spec.officialUrl;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await launchExternalUrl(url)) return;
    messenger?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: SelectableText(l10n.f43AiOpenLinkFailed(url)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    ref
      ..watch(onDeviceImageChangesProvider)
      ..watch(onDeviceProfileProvider);
    final engine = ref.watch(stableDiffusionImageEngineProvider);
    if (engine == null) return const SizedBox.shrink();
    final download = ref.watch(onDeviceModelDownloadProvider(_model));
    ref.listen(onDeviceModelDownloadProvider(_model), (_, next) {
      if (next is! ModelDownloadRunning) unawaited(_readPaused());
    });
    final spec = _model.spec;
    final downloaded = engine.isDownloaded(_model);
    final verdict = engine.verdictOf(_model);
    final measured = engine.measurementOf(_model);
    final active = downloaded && engine.activeModel == _model;
    final (accent, onAccent) = _model == OnDeviceImageModel.sdxs
        ? (scheme.tertiaryContainer, scheme.onTertiaryContainer)
        : (scheme.secondaryContainer, scheme.onSecondaryContainer);

    return Container(
      key: Key('on-device-model-${spec.id}'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
                child: Icon(
                  _model == OnDeviceImageModel.sdxs
                      ? Icons.bolt_outlined
                      : Icons.auto_awesome_outlined,
                  color: onAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _model == OnDeviceImageModel.sdxs
                          ? l10n.f43DeviceSdxsTagline
                          : l10n.f43DeviceTurboTagline,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                _Badge(
                  key: Key('on-device-active-${spec.id}'),
                  text: l10n.f43DeviceInUse,
                  color: scheme.primary,
                ),
            ],
          ),
          const SizedBox(height: 10),
          _Line(
            icon: Icons.gavel_outlined,
            text: openModelLicenseLine(l10n, spec.license),
          ),
          _Line(
            icon: Icons.download_outlined,
            text: l10n.f43DeviceSize(
              formatFileSize(spec.bytes, l10n.localeName),
            ),
          ),
          _Line(
            icon: Icons.memory_outlined,
            text: l10n.f43DeviceRam(spec.minRamGb, spec.recommendedRamGb),
          ),
          _Line(
            key: Key('on-device-time-${spec.id}'),
            icon: Icons.timer_outlined,
            text: measured == null
                ? l10n.f43DeviceTimeEstimated(
                    aiDuration(l10n, engine.timePerImageOf(_model)),
                  )
                : measured.load == null
                ? l10n.f43DeviceTimeMeasured(
                    aiDuration(l10n, measured.perImage),
                  )
                : l10n.f43DeviceTimeMeasuredWithLoad(
                    aiDuration(l10n, measured.perImage),
                    aiDuration(l10n, measured.load!),
                  ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: Key('on-device-link-${spec.id}'),
              onPressed: () => unawaited(_openLink()),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.f43AiOpenLink),
            ),
          ),
          _VerdictBox(model: _model, verdict: verdict),
          const SizedBox(height: 12),
          _Steps(
            model: _model,
            downloaded: downloaded,
            measured: measured != null,
            active: active,
          ),
          const SizedBox(height: 8),
          _actions(context, l10n, download, downloaded, verdict),
        ],
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    AppLocalizations l10n,
    ModelDownloadState download,
    bool downloaded,
    OnDeviceVerdict verdict,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actions = ref.watch(onDeviceImageActionsProvider);
    final engine = ref.watch(stableDiffusionImageEngineProvider)!;
    final spec = _model.spec;
    final id = spec.id;
    final size = formatFileSize(spec.bytes, l10n.localeName);

    if (download case ModelDownloadRunning(:final progress)) {
      return _Progress(
        key: Key('on-device-downloading-$id'),
        progress: progress,
        label: l10n.f43DeviceDownloading(_percent(progress)),
        hint: actions?.canPause ?? false ? null : l10n.f43DeviceSystemDownload,
        buttons: [
          if (actions?.canPause ?? false)
            OutlinedButton.icon(
              key: Key('on-device-pause-$id'),
              onPressed: () => unawaited(actions!.pause(_model)),
              icon: const Icon(Icons.pause, size: 18),
              label: Text(l10n.f43DevicePause),
            ),
          TextButton(
            key: Key('on-device-cancel-$id'),
            onPressed: () => unawaited(_cancelDownload()),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
      );
    }
    final paused = download is ModelDownloadPaused
        ? download.progress
        : (downloaded ? null : _pausedAt);
    if (paused != null && !downloaded) {
      return _Progress(
        key: Key('on-device-paused-$id'),
        progress: paused,
        label: l10n.f43DevicePaused(_percent(paused)),
        buttons: [
          FilledButton.icon(
            key: Key('on-device-resume-$id'),
            onPressed: verdict.cannot ? null : () => actions?.download(_model),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(l10n.f43DeviceResume),
          ),
          TextButton(
            key: Key('on-device-cancel-$id'),
            onPressed: () => unawaited(_cancelDownload()),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
      );
    }

    if (!downloaded) {
      final error = download is ModelDownloadFailed
          ? _downloadError(l10n, download.error)
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error,
                key: Key('on-device-download-error-$id'),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                key: Key('on-device-download-$id'),
                onPressed: verdict.cannot
                    ? null
                    : () => actions?.download(_model),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  error == null
                      ? l10n.f43DeviceDownload(size)
                      : l10n.f43DeviceRetry,
                ),
              ),
            ],
          ),
        ],
      );
    }

    final measuring = _measuring;
    if (measuring != null) {
      return _Progress(
        key: Key('on-device-measuring-$id'),
        label: l10n.f43DeviceMeasuring,
        buttons: [
          TextButton(
            key: Key('on-device-measure-cancel-$id'),
            onPressed: measuring.isCancelled ? null : measuring.cancel,
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
      );
    }

    final closed = engine.isClosed(_model);
    final active = engine.activeModel == _model;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonalIcon(
          key: Key('on-device-measure-$id'),
          onPressed: verdict.cannot && !closed
              ? null
              : () => unawaited(_measure()),
          icon: const Icon(Icons.speed_outlined, size: 18),
          label: Text(closed ? l10n.f43DeviceTryAgain : l10n.f43DeviceMeasure),
        ),
        if (!active && !verdict.cannot)
          OutlinedButton.icon(
            key: Key('on-device-use-$id'),
            onPressed: () => unawaited(actions?.use(_model)),
            icon: const Icon(Icons.check, size: 18),
            label: Text(l10n.f43DeviceUse),
          ),
        TextButton.icon(
          key: Key('on-device-delete-$id'),
          onPressed: () => unawaited(_delete()),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l10n.f43DeviceDelete),
          style: TextButton.styleFrom(foregroundColor: scheme.error),
        ),
      ],
    );
  }

  String _percent(double progress) => '${(progress * 100).floor()} %';

  String _downloadError(AppLocalizations l10n, Object error) => switch (error) {
    InsufficientStorageException(:final requiredBytes?) =>
      l10n.f43DeviceDownloadNoSpace(
        formatFileSize(requiredBytes, l10n.localeName),
      ),
    InsufficientStorageException() => l10n.f43DeviceDownloadNoSpaceUnknown,
    OnDeviceModelIntegrityException() => l10n.f43DeviceDownloadCorrupt,
    ModelDownloadHttpException(:final statusCode) =>
      l10n.f43DeviceDownloadServer(statusCode),
    _ => l10n.f43DeviceDownloadFailed,
  };
}

/// «Tu teléfono: puede / justo / no alcanza», con cada porqué.
class _VerdictBox extends StatelessWidget {
  const _VerdictBox({required this.model, required this.verdict});

  final OnDeviceImageModel model;
  final OnDeviceVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success =
        theme.extension<AppSemanticColors>()?.success ?? scheme.primary;
    final (label, color, icon) = switch (verdict.level) {
      OnDeviceVerdictLevel.can => (
        l10n.f43DeviceVerdictCan,
        success,
        Icons.check_circle,
      ),
      OnDeviceVerdictLevel.tight => (
        l10n.f43DeviceVerdictTight,
        scheme.tertiary,
        Icons.error_outline,
      ),
      OnDeviceVerdictLevel.cannot => (
        l10n.f43DeviceVerdictCannot,
        scheme.error,
        Icons.cancel,
      ),
    };
    return Container(
      key: Key('on-device-verdict-${model.spec.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (final reason in verdict.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 26),
              child: Text(
                _reasonText(context, reason, verdict.level),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  static String _reasonText(
    BuildContext context,
    OnDeviceVerdictReason reason,
    OnDeviceVerdictLevel level,
  ) {
    final l10n = AppLocalizations.of(context)!;
    String size(int bytes) => formatFileSize(bytes, l10n.localeName);
    return switch (reason) {
      NotAndroid() => l10n.f43DeviceReasonNotAndroid,
      Not64BitArm() => l10n.f43DeviceReasonNot64,
      CpuTooOld() => l10n.f43DeviceReasonCpu,
      ClosedLastTime() => l10n.f43DeviceReasonClosed,
      StorageShort(:final neededBytes, :final freeBytes) =>
        l10n.f43DeviceReasonStorage(size(neededBytes), size(freeBytes)),
      RamFacts(ramGb: null) => l10n.f43DeviceReasonRamUnknown,
      RamFacts(:final ramGb?, :final minGb) when ramGb < minGb =>
        l10n.f43DeviceReasonRamLow(ramGb, minGb),
      RamFacts(:final ramGb?, :final recommendedGb)
          when ramGb < recommendedGb =>
        l10n.f43DeviceReasonRamTight(ramGb, recommendedGb),
      RamFacts(:final ramGb?) => l10n.f43DeviceReasonRamOk(ramGb),
    };
  }
}

/// Los pasos de un modelo, cada uno con ✓ cuando está hecho.
class _Steps extends StatelessWidget {
  const _Steps({
    required this.model,
    required this.downloaded,
    required this.measured,
    required this.active,
  });

  final OnDeviceImageModel model;
  final bool downloaded;
  final bool measured;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final size = formatFileSize(model.spec.bytes, l10n.localeName);
    final steps = [
      (l10n.f43DeviceStepDownload(size), downloaded),
      (l10n.f43DeviceStepMeasure, measured),
      (l10n.f43DeviceStepUse, active),
    ];
    return Column(
      key: Key('on-device-steps-${model.spec.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.f43DeviceStepsTitle,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final (index, (text, done)) in steps.indexed)
          _StepLine(number: index + 1, text: text, done: done),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({
    required this.number,
    required this.text,
    required this.done,
  });

  final int number;
  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success =
        theme.extension<AppSemanticColors>()?.success ?? scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? success : scheme.surfaceContainerHighest,
            ),
            child: done
                ? Icon(Icons.check, size: 14, color: scheme.surface)
                : Text(
                    '$number',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Lo que va mientras baja o mide: la barra (si se sabe cuánto va), qué
/// hace y sus botones. Sin animaciones: la barra solo se mueve con lo bajado.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.label,
    required this.buttons,
    this.progress,
    this.hint,
    super.key,
  });

  final String label;
  final List<Widget> buttons;
  final double? progress;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (progress != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              if (progress == null) ...[
                Icon(
                  Icons.hourglass_top_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 6, children: buttons),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.text,
    this.strong = false,
    super.key,
  });

  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: strong
                  ? style?.copyWith(fontWeight: FontWeight.w600)
                  : style,
            ),
          ),
        ],
      ),
    );
  }
}

/// La línea de Ajustes → IA: el modelo del teléfono en una frase.
String onDeviceSummaryLine(
  AppLocalizations l10n,
  StableDiffusionImageEngine engine,
) {
  final model = engine.activeModel;
  if (!engine.isDownloaded(model)) {
    return engine.verdictOf(model).cannot
        ? l10n.f43DeviceSummaryCannot
        : l10n.f43DeviceSummaryOptional;
  }
  final time = aiDuration(l10n, engine.timePerImageOf(model));
  return engine.measurementOf(model) == null
      ? l10n.f43DeviceSummaryReadyEstimated(model.spec.displayName, time)
      : l10n.f43DeviceSummaryReady(model.spec.displayName, time);
}
