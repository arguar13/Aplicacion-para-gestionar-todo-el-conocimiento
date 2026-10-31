import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Antes de leer algo largo con una voz de la nube, la persona aprueba el
/// costo (F47, paso 4, decisiones C y F): el lector pregunta acá, y quien
/// tiene la pantalla —[CloudReadingGateHost]— muestra el aviso.
///
/// **Sin nadie que pregunte, no se gasta**: si no hay una pantalla montada
/// que muestre el aviso, la respuesta es «no».
class CloudReadingGate {
  CloudReadingAsk? _ask;

  /// La pantalla que pregunta, que reemplaza a la anterior. Devuelve cómo
  /// soltarla: si ya la reemplazó otra, soltarla no suelta a la otra.
  VoidCallback attach(CloudReadingAsk ask) {
    _ask = ask;
    return () {
      if (identical(_ask, ask)) _ask = null;
    };
  }

  /// Si se aprueba leer [characters] caracteres con [voice].
  Future<bool> approve({
    required NarrationVoice voice,
    required int characters,
  }) async {
    final ask = _ask;
    if (ask == null) return false;
    return ask(voice, characters);
  }
}

/// Preguntar si se lee [characters] caracteres con [voice], en la nube.
typedef CloudReadingAsk =
    Future<bool> Function(NarrationVoice voice, int characters);

final cloudReadingGateProvider = Provider<CloudReadingGate>(
  (ref) => CloudReadingGate(),
);

/// Muestra el aviso del costo de leer en la nube, sobre la pantalla de
/// [navigatorKey]. Va arriba de todo, junto a los demás avisos de la app.
class CloudReadingGateHost extends ConsumerStatefulWidget {
  const CloudReadingGateHost({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<CloudReadingGateHost> createState() =>
      _CloudReadingGateHostState();
}

class _CloudReadingGateHostState extends ConsumerState<CloudReadingGateHost> {
  late final VoidCallback _detach;

  @override
  void initState() {
    super.initState();
    _detach = ref.read(cloudReadingGateProvider).attach(_ask);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  Future<bool> _ask(NarrationVoice voice, int characters) async {
    final context = widget.navigatorKey.currentContext;
    if (context == null) return false;
    final id = myVoiceIdOf(voice);
    // De las fichas, no de lo último que vio una pantalla: el aviso puede
    // llegar antes de que nadie haya mirado las voces.
    final voices = await ref.read(myVoicesServiceProvider).list();
    final name = voices.where((v) => v.id == id).firstOrNull?.name ?? '';
    if (!context.mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          CloudReadingCostDialog(name: name, characters: characters),
    );
    return approved ?? false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// «Leer con Marisa en la nube»: lo que cuesta, que el texto sale a
/// ElevenLabs y lo que queda del mes, si se sabe.
class CloudReadingCostDialog extends ConsumerWidget {
  const CloudReadingCostDialog({
    required this.name,
    required this.characters,
    super.key,
  });

  final String name;
  final int characters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final number = NumberFormat.decimalPattern(l10n.localeName);
    final account = ref.watch(voiceCloudAccountProvider);
    return AlertDialog(
      key: const Key('cloud-reading-cost'),
      title: Text(l10n.f47P4ReadCloudTitle(name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.f47P4ReadCloudCost(
                number.format(characters),
                number.format(readingCredits(characters)),
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.f47P4ReadCloudLeaves),
            const SizedBox(height: 8),
            switch (account) {
              AsyncData(:final value) => Text(
                l10n.f47P4CreditsLeft(number.format(value.creditsLeft)),
                key: const Key('cloud-reading-credits-left'),
              ),
              AsyncError() => Text(l10n.f47P4CreditsUnknown),
              _ => Text(l10n.f47P4CreditsChecking),
            },
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cloud-reading-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.f47P4Cancel),
        ),
        FilledButton(
          key: const Key('cloud-reading-approve'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.f47P4ReadCloudApprove),
        ),
      ],
    );
  }
}
