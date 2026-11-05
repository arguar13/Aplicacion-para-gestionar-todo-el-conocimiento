import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si se sigue con [cost] —lo que costaría generar un audio con voces de la
/// nube (F47, decisión F)—: lo que diga la persona.
typedef SpeechAudioApproval =
    Future<bool> Function(BuildContext context, SpeechAudioCost cost);

/// **El enganche del costo** (F47, pasos 4, 5 y 6b): a quién se le pregunta
/// antes de generar un audio que cuesta. Lo de fábrica es un aviso con el
/// costo y los caracteres ([confirmSpeechAudioCost]).
///
/// El paso 4 lo cambia por su propia puerta (`cloudReadingGateProvider`),
/// que aprueba voz por voz con sus caracteres
/// ([SpeechAudioCost.charactersByVoice]) y lleva la cuenta de lo gastado:
/// el podcast y «Descargar audio» preguntan por acá, sin saber de ElevenLabs.
final speechAudioApprovalProvider = Provider<SpeechAudioApproval>(
  (ref) => confirmSpeechAudioCost,
);

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
