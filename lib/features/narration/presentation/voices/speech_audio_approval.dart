import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/cloud_reading_gate.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si se sigue con [cost] —lo que costaría generar un audio con voces de la
/// nube (F47, decisión F)—: lo que diga la persona.
typedef SpeechAudioApproval =
    Future<bool> Function(BuildContext context, SpeechAudioCost cost);

/// **El enganche del costo** (F47, pasos 4, 5 y 6b): a quién se le pregunta
/// antes de generar un audio que cuesta. El podcast y «Descargar audio»
/// preguntan por acá, sin saber de ElevenLabs.
///
/// Las voces propias de la nube (paso 4) se aprueban con su puerta
/// ([cloudReadingGateProvider]), voz por voz con sus caracteres
/// ([SpeechAudioCost.charactersByVoice]) y lo que queda del mes: ver
/// [approveSpeechAudioCost].
final speechAudioApprovalProvider = Provider<SpeechAudioApproval>((ref) {
  final gate = ref.watch(cloudReadingGateProvider);
  return (context, cost) => approveSpeechAudioCost(
    context,
    cost,
    gate: gate,
    mine: () => ref.read(myVoicesServiceProvider).list(),
  );
});

/// Si se genera con [cost]:
///
/// - **cada voz propia que cobra** (`mia:<id>`) se aprueba con [gate], con
///   los caracteres que lee ella: el mismo aviso que antes de leer algo
///   largo en la nube, con su nombre y lo que queda del mes. Basta un «no»
///   para no generar, y sin nadie que pregunte la respuesta es «no»;
/// - **cualquier otra que cobre** pasa por [confirmSpeechAudioCost], con el
///   costo en su moneda.
Future<bool> approveSpeechAudioCost(
  BuildContext context,
  SpeechAudioCost cost, {
  required CloudReadingGate gate,
  required Future<List<MyVoice>> Function() mine,
}) async {
  final byVoice = cost.charactersByVoice;
  final others = byVoice.keys.where((id) => !id.startsWith(myVoicePrefix));
  if (byVoice.isEmpty || others.isNotEmpty) {
    if (!await confirmSpeechAudioCost(context, cost)) return false;
  }
  final own = [
    for (final entry in byVoice.entries)
      if (entry.key.startsWith(myVoicePrefix)) entry,
  ];
  if (own.isEmpty) return true;
  final voices = await mine();
  for (final MapEntry(key: voiceId, value: characters) in own) {
    final voice = voices
        .where((v) => v.narrationVoice.name == voiceId)
        .firstOrNull;
    final approved = await gate.approve(
      // Una que ya no está se nombra por su id: el aviso dice lo que cuesta
      // igual, y generar va a decir que falta.
      voice:
          voice?.narrationVoice ??
          NarrationVoice(
            name: voiceId,
            locale: '',
            engine: NarrationEngine.cloud,
          ),
      characters: characters,
    );
    if (!approved) return false;
  }
  return true;
}

/// Pregunta antes de generar con [cost]: cuánto cuesta, con la cuenta de la
/// persona, y que el texto se manda a la nube de esa voz.
Future<bool> confirmSpeechAudioCost(
  BuildContext context,
  SpeechAudioCost cost,
) async {
  final l10n = AppLocalizations.of(context)!;
  final amount = NumberFormat.simpleCurrency(
    locale: l10n.localeName,
    name: cost.currency,
  ).format(cost.amount);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('speech-audio-cost'),
      title: Text(l10n.f47P6bCostTitle),
      content: Text(l10n.f47P6bCostBody(amount, cost.characters)),
      actions: [
        TextButton(
          key: const Key('speech-audio-cost-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('speech-audio-cost-go'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.f47P6bCostGo),
        ),
      ],
    ),
  );
  return go ?? false;
}
