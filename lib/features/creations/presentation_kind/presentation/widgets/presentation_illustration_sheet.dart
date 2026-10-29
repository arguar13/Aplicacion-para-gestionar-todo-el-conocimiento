import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/ai_capabilities_screen.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/presentation_illustrations.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué se dibuja desde el visor.
enum IllustrationSheetMode {
  /// Una diapositiva que ya tiene la suya: «Volver a dibujar».
  redraw,

  /// Una que todavía no tiene: «Dibujar la ilustración».
  draw,

  /// Todas las que faltan: «Completar ilustraciones».
  complete,
}

/// La hoja para dibujar una ilustración —o completar las que faltan— desde
/// el visor (F43, decisión H): **primero lo que cuesta**, con la cuenta que
/// va a dibujar, el precio aproximado y el porcentaje de la cuota de hoy; si
/// esa cuenta no puede, por qué, y las otras que sí. Recién con «Dibujar» se
/// pide algo.
///
/// Mientras dibuja dice cuántas van; cerrarla corta. Lo que no sale se dice
/// con sus palabras (`illustrationReason`) y lo que había queda.
class PresentationIllustrationSheet extends ConsumerStatefulWidget {
  const PresentationIllustrationSheet({
    required this.creationId,
    required this.deck,
    required this.design,
    required this.slides,
    required this.mode,
    this.accountId,
    this.illustrations,
    super.key,
  });

  final String creationId;
  final SlideDeck deck;
  final DeckDesign design;

  /// Las diapositivas que se dibujan (posiciones).
  final List<int> slides;
  final IllustrationSheetMode mode;

  /// La cuenta elegida al crear la presentación, si se eligió otra.
  final String? accountId;
  final SlideIllustrationResolver? illustrations;

  @override
  ConsumerState<PresentationIllustrationSheet> createState() =>
      _PresentationIllustrationSheetState();
}

class _PresentationIllustrationSheetState
    extends ConsumerState<PresentationIllustrationSheet> {
  late String? _accountId = widget.accountId;
  CancellationSignal? _signal;
  var _done = 0;
  ImageFailure? _failure;
  String? _failureAccount;

  bool get _drawing => _signal != null;

  @override
  void dispose() {
    // Cerrarla mientras dibuja corta lo que se pidió.
    _signal?.cancel();
    super.dispose();
  }

  Future<void> _draw() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final signal = CancellationSignal();
    setState(() {
      _signal = signal;
      _done = 0;
      _failure = null;
    });
    try {
      final run = await drawPresentationIllustrations(
        ref,
        creationId: widget.creationId,
        slides: widget.slides,
        template: widget.design.template,
        accountId: _accountId,
        cancellation: signal,
        onProgress: (done, _) {
          if (mounted) setState(() => _done = done);
        },
      );
      if (!mounted) return;
      final misses = [
        for (final slide in widget.slides) ?run.content.missOf(slide),
      ];
      if (misses.isEmpty) {
        navigator.pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.f43PresDrawnSnack(run.drawn))),
          );
        return;
      }
      setState(() {
        _signal = null;
        _failure = misses.first.failure;
        _failureAccount = run.content.illustrationAccount;
      });
    } on CreationCancelledException {
      // La cerró la persona: no hay nada que decir.
    } on Object {
      if (!mounted) return;
      setState(() {
        _signal = null;
        _failure = ImageFailure.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = widget.slides.length;
    final estimate = ref.watch(
      creationEstimateProvider(
        CreationEstimateRequest(
          inputTokens: 0,
          expectedOutputTokens: 0,
          textRequests: 0,
          images: count,
          imageAccountId: _accountId,
        ),
      ),
    );
    final title = switch (widget.mode) {
      IllustrationSheetMode.redraw => l10n.f43PresRedrawTitle,
      IllustrationSheetMode.draw => l10n.f43PresDrawTitle,
      IllustrationSheetMode.complete => l10n.f43PresCompleteTitle,
    };
    final single = count == 1 && widget.slides.first < widget.deck.slides.length
        ? widget.slides.first
        : null;
    final failure = _failure;

    return Material(
      key: const Key('presentation-illustration-sheet'),
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.brush_outlined,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleLarge),
                    ),
                    CreationCloseButton(tooltip: l10n.f43StudioClose),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (single != null)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 150),
                            child: AspectRatio(
                              aspectRatio: widget.design.aspect.ratio,
                              child: SlideView(
                                slide: widget.deck.slides[single],
                                design: widget.design,
                                deck: widget.deck,
                                index: single,
                                illustrations: widget.illustrations,
                                borderRadius: BorderRadius.circular(12),
                                shadow: true,
                              ),
                            ),
                          ),
                        )
                      else
                        Text(
                          l10n.f43PresCompleteHint(count),
                          style: theme.textTheme.bodyLarge,
                        ),
                      const SizedBox(height: 16),
                      _Cost(estimate: estimate),
                      ..._alternatives(context, estimate),
                      if (failure != null) ...[
                        const SizedBox(height: 16),
                        _Notice(
                          key: const Key('presentation-illustration-failed'),
                          text: l10n.f43PresDrawFailed(
                            illustrationReason(
                              l10n,
                              failure,
                              account: _failureAccount,
                              textProvider: estimate.text.provider,
                            ),
                          ),
                        ),
                      ],
                      if (_drawing) ...[
                        const SizedBox(height: 16),
                        Text(
                          l10n.f43PresDrawing(
                            (_done + 1).clamp(1, count),
                            count,
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: count == 0 ? null : _done / count,
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      key: const Key('presentation-illustration-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        MaterialLocalizations.of(context).cancelButtonLabel,
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('presentation-illustration-draw'),
                      onPressed: estimate.canIllustrate && !_drawing
                          ? () => unawaited(_draw())
                          : null,
                      icon: const Icon(Icons.brush_outlined),
                      label: Text(
                        failure == null
                            ? l10n.f43PresDraw
                            : l10n.f43PresDrawAgain,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Las otras cuentas que pueden dibujar, si la elegida no puede o se
  /// prefiere otra; y, si ninguna puede, la tabla de qué puede cada IA.
  List<Widget> _alternatives(BuildContext context, CreationEstimate estimate) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (final alternative in estimate.alternatives) {
      final (id, label) = switch (alternative) {
        UseOtherImageAccount(:final account) => (
          account.id,
          l10n.f43AiAltUseAccount(account.provider.label(l10n), account.label),
        ),
        UseOnDeviceModel(:final side) => (
          side.account.id,
          l10n.f43AiAltOnDevice,
        ),
        _ => (null, null),
      };
      if (id == null || label == null) continue;
      rows.add(
        ListTile(
          key: ValueKey('presentation-illustration-account-$id'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.swap_horiz),
          title: Text(label),
          onTap: _drawing ? null : () => setState(() => _accountId = id),
        ),
      );
    }
    if (rows.isEmpty && !estimate.canIllustrate) {
      rows.add(
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('presentation-illustration-capabilities'),
            onPressed: () => unawaited(openAiCapabilitiesScreen(context)),
            icon: const Icon(Icons.info_outline),
            label: Text(l10n.f43PresWhoCanDraw),
          ),
        ),
      );
    }
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      if (estimate.alternatives.isNotEmpty)
        Text(
          l10n.f43AiAltTitle,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ...rows,
    ];
  }
}

/// Con qué cuenta se dibuja, cuánto cuesta y qué parte de la cuota de hoy.
class _Cost extends StatelessWidget {
  const _Cost({required this.estimate});

  final CreationEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final side = estimate.imageSide;
    final lines = <(IconData, Color, String)>[];
    if (!estimate.canIllustrate || side == null) {
      lines.add((
        Icons.close_rounded,
        scheme.error,
        l10n.f43AiIllustrateBlocked(
          illustrationReason(
            l10n,
            estimate.illustrateReason ?? ImageFailure.noAccount,
            account: side?.account.label,
            textProvider: estimate.text.provider,
          ),
        ),
      ));
    } else {
      final model =
          side.modelLabel ?? side.model ?? side.account.provider.label(l10n);
      final account = side.account.provider.isOnDevice
          ? model
          : '$model · ${side.account.label}';
      lines.add((
        Icons.check_rounded,
        scheme.primary,
        l10n.f43AiIllustrateWith(estimate.images, account),
      ));
      final usd = estimate.imagesUsd;
      final size = illustrationSizeLabel(l10n, estimate.imageSize);
      lines.add((
        Icons.payments_outlined,
        scheme.onSurfaceVariant,
        side.account.provider.isOnDevice
            ? l10n.f43AiImagesFree(estimate.images)
            : usd == null
            ? l10n.f43AiImagesCredits(estimate.images, size)
            : l10n.f43AiImagesCost(estimate.images, size, aiUsd(context, usd)),
      ));
      for (final share in estimate.quota) {
        if (share.accountId != side.account.id) continue;
        lines.add((
          Icons.data_usage,
          scheme.onSurfaceVariant,
          share.hasQuota
              ? l10n.f43AiQuotaShare(
                  aiPercent(context, share.percentOfQuota!),
                  aiPercent(context, share.percentUsed ?? 0),
                )
              : l10n.f43AiQuotaNone,
        ));
      }
      if (side.capability.untested) {
        lines.add((
          Icons.help_outline,
          scheme.onSurfaceVariant,
          l10n.f43AiIllustrateUntested,
        ));
      }
    }
    return Container(
      key: const Key('presentation-illustration-cost'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, (icon, color, text)) in lines.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Un aviso de algo que no salió.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre [PresentationIllustrationSheet].
Future<void> showPresentationIllustrationSheet(
  BuildContext context, {
  required String creationId,
  required SlideDeck deck,
  required DeckDesign design,
  required List<int> slides,
  required IllustrationSheetMode mode,
  String? accountId,
  SlideIllustrationResolver? illustrations,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => PresentationIllustrationSheet(
    creationId: creationId,
    deck: deck,
    design: design,
    slides: slides,
    mode: mode,
    accountId: accountId,
    illustrations: illustrations,
  ),
);

/// El porqué que más se repite en [misses], para decirlo una vez.
ImageFailure? mainFailureOf(List<IllustrationMiss> misses) {
  if (misses.isEmpty) return null;
  final counts = <ImageFailure, int>{};
  for (final miss in misses) {
    counts[miss.failure] = (counts[miss.failure] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
