import 'package:flutter/material.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las dos líneas de lo que pide dibujar con [provider] (F43), en la hoja de
/// claves: Gemini, la facturación activa y el precio por imagen; OpenAI, la
/// organización verificada y el más barato; Hugging Face, el token y los
/// créditos. Con los precios de la tabla fechada.
class ImageRequirementLines extends StatelessWidget {
  const ImageRequirementLines({required this.provider, super.key});

  /// Gemini u OpenAI (los de F32), o `null` para Hugging Face.
  final AiProvider? provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final drawing = provider == null
        ? IllustrationProvider.huggingFace
        : IllustrationProvider.ofText(provider!);
    final cheapest = [
      for (final p in kImageModelPrices)
        if (p.provider == drawing && p.cheapest) p,
    ].firstOrNull;
    final price = cheapest == null
        ? ''
        : aiUsd(context, cheapest.usdFor(IllustrationSize.standard));
    final (first, second) = switch (drawing) {
      IllustrationProvider.gemini => (
        l10n.f43AiKeyGeminiBilling,
        l10n.f43AiKeyGeminiPrice(price),
      ),
      IllustrationProvider.openAi => (
        l10n.f43AiKeyOpenAiVerify,
        l10n.f43AiKeyOpenAiPrice(cheapest?.displayName ?? '', price),
      ),
      _ => (l10n.f43AiHfStep, l10n.f43AiHfCredits),
    };
    final style = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Container(
      key: const Key('image-requirement-lines'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, line) in [first, second].indexed) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  i == 0 ? Icons.image_outlined : Icons.payments_outlined,
                  size: 16,
                  color: scheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(line, style: style)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
