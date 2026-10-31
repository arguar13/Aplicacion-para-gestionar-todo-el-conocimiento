import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/clone_voice_screen.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/create_voice_screen.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/my_voice_widgets.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/voice_cloud_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Arriba de la pestaña Mías (F47, paso 4): «Clonar una voz» y «Crear una
/// voz», cada una con lo que hace en una línea.
class MyVoicesEntry extends StatelessWidget {
  const MyVoicesEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          _EntryCard(
            key: const Key('my-voices-clone'),
            icon: Icons.record_voice_over_outlined,
            title: l10n.f47P4CloneTitle,
            text: l10n.f47P4CloneEntry,
            onTap: () => unawaited(showCloneVoice(context)),
          ),
          const SizedBox(height: 8),
          _EntryCard(
            key: const Key('my-voices-create'),
            icon: Icons.auto_awesome_outlined,
            title: l10n.f47P4CreateTitle,
            text: l10n.f47P4CreateEntry,
            onTap: () => unawaited(showCreateVoice(context)),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: '$title. $text',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(text, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La hoja de una voz propia: de dónde es, su consentimiento, cambiarle el
/// nombre o la cara, y borrarla.
Future<void> showMyVoiceActions(BuildContext context, MyVoice voice) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MyVoiceActionsSheet(voice: voice),
    );

class MyVoiceActionsSheet extends ConsumerStatefulWidget {
  const MyVoiceActionsSheet({required this.voice, super.key});

  final MyVoice voice;

  @override
  ConsumerState<MyVoiceActionsSheet> createState() =>
      _MyVoiceActionsSheetState();
}

class _MyVoiceActionsSheetState extends ConsumerState<MyVoiceActionsSheet> {
  late final _name = TextEditingController(text: widget.voice.name);
  late var _faceSeed = widget.voice.faceSeed;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final navigator = Navigator.of(context);
    await ref
        .read(myVoicesServiceProvider)
        .update(widget.voice, name: _name.text, faceSeed: _faceSeed);
    navigator.pop();
  }

  Future<void> _delete({bool onlyHere = false}) async {
    final l10n = AppLocalizations.of(context)!;
    final voice = widget.voice;
    if (!onlyHere) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('my-voice-delete-confirm'),
          title: Text(l10n.f47P4DeleteVoiceTitle(voice.name)),
          content: Text(
            voice.home == MyVoiceHome.elevenLabs
                ? l10n.f47P4DeleteVoiceCloud
                : l10n.f47P4DeleteVoicePhone,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.f47P4Cancel),
            ),
            FilledButton(
              key: const Key('my-voice-delete-yes'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.f47P3Delete),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(myVoicesServiceProvider).delete(voice, onlyHere: onlyHere);
      // Si era la elegida para su idioma, el idioma queda sin elegida: lee
      // la mejor que haya, como cuando se borra una voz bajada.
      final settings = ref.read(narrationSettingsNotifierProvider);
      if (settings.voicesByLanguage[voice.language] == voice.narrationVoice) {
        await ref
            .read(narrationSettingsNotifierProvider.notifier)
            .clearLanguage(voice.language);
      }
      messenger.showAppSnackBar(
        AppSnackBar(content: Text(l10n.f47P4Deleted(voice.name))),
      );
      navigator.pop();
    } on VoiceCloudException catch (error) {
      if (mounted) {
        setState(() => _error = voiceCloudFailureText(error.failure, l10n));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final voice = widget.voice;
    final consent = voice.consent;
    final date = DateFormat.yMMMd(l10n.localeName);
    return SingleChildScrollView(
      key: const Key('my-voice-actions'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(voice.name, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 4),
          Text(
            voice.home == MyVoiceHome.elevenLabs
                ? l10n.f47P4LivesInCloud
                : l10n.f47P4LivesOnPhone,
          ),
          if (consent != null)
            Text(
              consent.kind == VoiceConsentKind.own
                  ? l10n.f47P4ConsentOwnSaved(
                      consent.personName,
                      date.format(consent.grantedAt.toLocal()),
                    )
                  : l10n.f47P4ConsentOtherSaved(
                      consent.personName,
                      date.format(consent.grantedAt.toLocal()),
                    ),
              key: const Key('my-voice-consent'),
            ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('my-voice-rename'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.f47P4VoiceName),
          ),
          const SizedBox(height: 12),
          FacePicker(
            faceKey: _faceSeed == 0 ? voice.id : '${voice.id}#$_faceSeed',
            name: _name.text,
            onNext: () => setState(() => _faceSeed++),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const Key('my-voice-save'),
              onPressed: _busy || _name.text.trim().isEmpty
                  ? null
                  : () => unawaited(_saveChanges()),
              child: Text(l10n.f47P4Save),
            ),
          ),
          const Divider(height: 32),
          if (_error case final error?)
            NoticeCard(
              key: const Key('my-voice-delete-error'),
              error: true,
              text: l10n.f47P4DeleteCloudFailed(error),
              action: TextButton(
                key: const Key('my-voice-delete-here'),
                onPressed: _busy
                    ? null
                    : () => unawaited(_delete(onlyHere: true)),
                child: Text(l10n.f47P4DeleteOnlyHere),
              ),
            ),
          TextButton.icon(
            key: const Key('my-voice-delete'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(l10n.f47P4DeleteVoice),
            onPressed: _busy ? null : () => unawaited(_delete()),
          ),
        ],
      ),
    );
  }
}
