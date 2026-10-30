import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/transform/domain/entities/stored_video_text.dart';
import 'package:sinapsis/features/transform/presentation/providers/foreign_video_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Dónde se ofrece volver a extraer: cambia qué videos se miran y qué dice la
/// confirmación.
enum ForeignVideoPlace {
  /// La Bandeja: el texto de la fuente.
  inbox,

  /// Procesado: el texto del documento, que es una copia del de la fuente.
  processed,
}

/// «Volver a extraer» un video guardado cuyo texto no está en su idioma
/// (F45, paso 4): en la tarjeta de la Bandeja ([ForeignVideoTextNotice.inbox])
/// y en el documento de Procesado ([ForeignVideoTextNotice.processed]).
///
/// Dice en qué está y qué se habla, y el botón; mientras se vuelve a extraer,
/// «Volviendo a extraer…» con el botón apagado. Sin nada que ofrecer —el
/// texto está en su idioma, o no se sabe—, no dibuja nada.
class ForeignVideoTextNotice extends ConsumerWidget {
  const ForeignVideoTextNotice.inbox({
    required String sourceId,
    this.padding = const EdgeInsets.only(top: 12),
    super.key,
  }) : _id = sourceId,
       _place = ForeignVideoPlace.inbox;

  const ForeignVideoTextNotice.processed({
    required String documentId,
    this.padding = const EdgeInsets.only(bottom: 12),
    super.key,
  }) : _id = documentId,
       _place = ForeignVideoPlace.processed;

  final String _id;
  final ForeignVideoPlace _place;

  /// El aire alrededor, solo cuando hay algo que ofrecer.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foreign = ref.watch(switch (_place) {
      ForeignVideoPlace.inbox => pendingForeignVideoTextProvider(_id),
      ForeignVideoPlace.processed => processedForeignVideoTextProvider(_id),
    });
    if (foreign == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final found = l10n.f45S4LanguageName(foreign.verdict.language ?? '');
    final spoken = foreign.spoken;
    final working = foreign.video.reextracting;

    return Padding(
      padding: padding,
      child: _OfferCard(
        key: const Key('foreign-video-text'),
        title: l10n.f45S4ForeignTextTitle,
        body: spoken == null
            ? l10n.f45S4ForeignTextBodyNoSpoken(found)
            : l10n.f45S4ForeignTextBody(found, l10n.f45S4LanguageName(spoken)),
        action: FilledButton.tonalIcon(
          key: const Key('foreign-video-text-reextract'),
          onPressed: working
              ? null
              : () => unawaited(_reextract(context, ref, [foreign], _place)),
          icon: const Icon(Icons.refresh),
          label: Text(working ? l10n.f45S4Reextracting : l10n.f45S4Reextract),
        ),
      ),
    );
  }
}

/// La franja de arriba de la Bandeja y de Procesado (F45, paso 4): cuántos
/// videos tienen el texto en otro idioma, y «Volver a extraer» para todos de
/// una vez.
///
/// Cuenta los que todavía no se están volviendo a extraer. En la Bandeja no
/// cuenta el de la tarjeta que se mira ([exceptSourceId]), que ya lo ofrece:
/// con ese solo, no se muestra.
class ForeignVideoTextsBanner extends ConsumerWidget {
  const ForeignVideoTextsBanner.inbox({this.exceptSourceId, super.key})
    : _place = ForeignVideoPlace.inbox;

  const ForeignVideoTextsBanner.processed({super.key})
    : _place = ForeignVideoPlace.processed,
      exceptSourceId = null;

  final ForeignVideoPlace _place;

  /// El video de la tarjeta que se mira, que lo ofrece por su cuenta.
  final String? exceptSourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all =
        ref.watch(switch (_place) {
          ForeignVideoPlace.inbox => pendingForeignVideoTextsProvider,
          ForeignVideoPlace.processed => processedForeignVideoTextsProvider,
        }).valueOrNull ??
        const <ForeignVideoText>[];
    final waiting = [
      for (final foreign in all)
        if (!foreign.video.reextracting) foreign,
    ];
    final others = waiting.where((f) => f.sourceId != exceptSourceId);
    if (others.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _OfferCard(
            key: const Key('foreign-video-texts-banner'),
            title: l10n.f45S4ForeignTextsBanner(waiting.length),
            body: l10n.f45S4ForeignTextsHint,
            action: FilledButton.tonalIcon(
              key: const Key('foreign-video-texts-reextract'),
              onPressed: () =>
                  unawaited(_reextract(context, ref, waiting, _place)),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.f45S4ReextractAll(waiting.length)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pide volver a extraer [videos] y lo confirma abajo.
Future<void> _reextract(
  BuildContext context,
  WidgetRef ref,
  List<ForeignVideoText> videos,
  ForeignVideoPlace place,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final asked = await ref.read(reextractForeignVideosProvider)(videos);
  if (asked == 0) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(switch (place) {
          ForeignVideoPlace.inbox => l10n.f45S4ReextractStarted(asked),
          ForeignVideoPlace.processed => l10n.f45S4ReextractStartedProcessed(
            asked,
          ),
        }),
      ),
    );
}

/// El aviso de un texto en otro idioma: el ícono de traducir en su círculo,
/// qué pasa, por qué y el botón, sobre una superficie propia —el mismo
/// lenguaje que la franja de estado de la tarjeta de la Bandeja—. Con la
/// letra al doble, el texto se parte y el botón baja a su renglón.
class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.title,
    required this.body,
    required this.action,
    super.key,
  });

  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.tertiary.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.tertiaryContainer,
                ),
                child: Icon(
                  Icons.translate,
                  size: 20,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  action,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
