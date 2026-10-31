import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «La nube para voces» (F47, paso 4): prenderla, cargar la clave de
/// ElevenLabs y ver lo gastado.
Future<void> showVoiceCloudSheet(BuildContext context) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => const VoiceCloudSheet(),
  );
}

/// Por qué no se pudo algo con ElevenLabs, dicho para la persona.
String voiceCloudFailureText(
  VoiceCloudFailure failure,
  AppLocalizations l10n,
) => switch (failure) {
  VoiceCloudFailure.noKey => l10n.f47P4FailNoKey,
  VoiceCloudFailure.invalidKey => l10n.f47P4FailInvalidKey,
  VoiceCloudFailure.noCredits => l10n.f47P4FailNoCredits,
  VoiceCloudFailure.planRequired => l10n.f47P4FailPlan,
  VoiceCloudFailure.voiceNotFound => l10n.f47P4FailVoiceGone,
  VoiceCloudFailure.busy => l10n.f47P4FailBusy,
  VoiceCloudFailure.unavailable => l10n.f47P4FailUnavailable,
  VoiceCloudFailure.rejected => l10n.f47P4FailRejected,
  VoiceCloudFailure.network => l10n.f47P4FailNetwork,
  VoiceCloudFailure.unknown => l10n.f47P4FailUnknown,
};

/// La nube para voces: **apagada de entrada** (decisión F). Dice qué sale del
/// teléfono y lo que cuesta, con la fecha de los precios; al prenderla se
/// carga la clave, que va al almacén seguro y nunca se muestra entera.
class VoiceCloudSheet extends ConsumerStatefulWidget {
  const VoiceCloudSheet({super.key});

  @override
  ConsumerState<VoiceCloudSheet> createState() => _VoiceCloudSheetState();
}

class _VoiceCloudSheetState extends ConsumerState<VoiceCloudSheet> {
  final _key = TextEditingController();
  var _editingKey = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    await ref.read(voiceCloudSettingsProvider.notifier).saveKey(key);
    _key.clear();
    if (!mounted) return;
    setState(() => _editingKey = false);
    ref.invalidate(voiceCloudAccountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.watch(voiceCloudSettingsProvider);
    final notifier = ref.read(voiceCloudSettingsProvider.notifier);

    return SingleChildScrollView(
      key: const Key('voice-cloud-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.f47P4CloudTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Text(l10n.f47P4CloudIntro),
          const SizedBox(height: 12),
          _Fact(icon: Icons.upload_outlined, text: l10n.f47P4CloudLeaves),
          _Fact(icon: Icons.payments_outlined, text: l10n.f47P4CloudCosts),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('voice-cloud-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.f47P4CloudSwitch),
            subtitle: Text(
              settings.enabled ? l10n.f47P4CloudOn : l10n.f47P4CloudOff,
            ),
            value: settings.enabled,
            onChanged: (value) =>
                unawaited(notifier.setEnabled(enabled: value)),
          ),
          if (settings.enabled) ...[
            const Divider(),
            if (settings.hasKey && !_editingKey) ...[
              ListTile(
                key: const Key('voice-cloud-key-saved'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.key_rounded),
                title: Text(l10n.f47P4CloudKeySaved),
                subtitle: Text(l10n.f47P4CloudKeySavedHint),
              ),
              // Debajo y no al costado: con la letra al doble no entran.
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    key: const Key('voice-cloud-key-change'),
                    onPressed: () => setState(() => _editingKey = true),
                    child: Text(l10n.f47P4CloudKeyChange),
                  ),
                  TextButton(
                    key: const Key('voice-cloud-key-delete'),
                    onPressed: () => unawaited(notifier.deleteKey()),
                    child: Text(l10n.f47P4CloudKeyDelete),
                  ),
                ],
              ),
            ] else ...[
              TextField(
                key: const Key('voice-cloud-key-field'),
                controller: _key,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.f47P4CloudKeyLabel,
                  helperText: l10n.f47P4CloudKeyHelp,
                  helperMaxLines: 3,
                ),
                onSubmitted: (_) => unawaited(_saveKey()),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  key: const Key('voice-cloud-key-save'),
                  onPressed: () => unawaited(_saveKey()),
                  child: Text(l10n.f47P4CloudKeySave),
                ),
              ),
            ],
            if (settings.ready) ...[
              const SizedBox(height: 12),
              const VoiceCloudUsage(),
            ],
          ],
        ],
      ),
    );
  }
}

/// Lo gastado este mes en ElevenLabs: el plan, los créditos, cuándo se
/// renuevan, si clona y cuántas voces ocupa.
class VoiceCloudUsage extends ConsumerWidget {
  const VoiceCloudUsage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern(l10n.localeName);
    final account = ref.watch(voiceCloudAccountProvider);
    return Card.outlined(
      key: const Key('voice-cloud-usage'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.f47P4CloudUsageTitle,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            switch (account) {
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.f47P4CloudPlan(value.tier)),
                  Text(
                    l10n.f47P4CloudCredits(
                      number.format(value.creditsUsed),
                      number.format(value.creditLimit),
                    ),
                  ),
                  if (value.resetsAt case final at?)
                    Text(
                      l10n.f47P4CloudResets(
                        DateFormat.yMMMd(l10n.localeName).format(at.toLocal()),
                      ),
                    ),
                  Text(
                    value.canClone
                        ? l10n.f47P4CloudCanClone
                        : l10n.f47P4CloudCannotClone,
                  ),
                  if (value.voiceSlotsUsed case final used?)
                    if (value.voiceLimit case final limit?)
                      Text(l10n.f47P4CloudSlots(used, limit)),
                ],
              ),
              AsyncError(:final error) => Text(
                error is VoiceCloudException
                    ? voiceCloudFailureText(error.failure, l10n)
                    : l10n.f47P4FailUnknown,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              _ => Text(l10n.f47P4CreditsChecking),
            },
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('voice-cloud-refresh'),
                onPressed: () => ref.invalidate(voiceCloudAccountProvider),
                child: Text(l10n.f47P4CloudRefresh),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
