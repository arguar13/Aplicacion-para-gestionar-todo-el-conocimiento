import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_capability_card.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_illustration_plan.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_kind_providers.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «Ilustraciones con IA» de la infografía [creation], con [design].
Future<void> showInfographicIllustrations(
  BuildContext context, {
  required StudyCreation creation,
  required InfographicDesign design,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) =>
      InfographicIllustrationsSheet(creationId: creation.id, design: design),
);

/// Las ilustraciones con IA de una infografía ya hecha (F43, decisión H): cada
/// lugar que el estilo de ahora ilustra, con la suya —hecha, sin hacer o con
/// el porqué de que no salió—, **rehacer una sola** y **«Completar las que
/// faltan»**.
///
/// Antes de dibujar, siempre el costo: «Con tu IA actual» solo con las
/// imágenes —cuántas, con qué cuenta, cuánto cuestan y cuánto de la cuota de
/// hoy—, y si esa cuenta no puede, las otras que sí. Mientras dibuja dice
/// cuántas van y se puede cancelar. Lo que sale se guarda en la creación
/// (`StudyCreationRepository.amend`); el texto no se toca.
class InfographicIllustrationsSheet extends ConsumerStatefulWidget {
  const InfographicIllustrationsSheet({
    required this.creationId,
    required this.design,
    super.key,
  });

  final String creationId;
  final InfographicDesign design;

  @override
  ConsumerState<InfographicIllustrationsSheet> createState() =>
      _InfographicIllustrationsSheetState();
}

class _InfographicIllustrationsSheetState
    extends ConsumerState<InfographicIllustrationsSheet> {
  /// Lo que se va a dibujar, mientras se mira el costo; `null` si nada.
  List<String>? _pending;

  /// La cuenta elegida en el aviso; `null`, la del pedido o la que escribe.
  String? _accountId;
  var _accountChosen = false;

  CancellationSignal? _signal;
  var _done = 0;
  var _total = 0;

  /// Cómo terminó lo último que se dibujó.
  String? _result;

  bool get _running => _signal != null;

  String? _requestedAccount(StudyCreation creation) {
    if (_accountChosen) return _accountId;
    final id = creation.options[CreationOptionKeys.imageAccountId];
    return id is String && id.isNotEmpty ? id : null;
  }

  Future<void> _draw(StudyCreation creation, List<String> ids) async {
    final l10n = AppLocalizations.of(context)!;
    final content = InfographicContent.decode(creation.content);
    final slots = [
      for (final slot in InfographicIllustrationPlan.slotsFor(
        content.sheet,
        widget.design,
      ))
        if (ids.contains(slot.id)) slot,
    ];
    if (slots.isEmpty) return;
    final signal = CancellationSignal();
    setState(() {
      _signal = signal;
      _pending = null;
      _done = 0;
      _total = slots.length;
      _result = null;
    });
    String? result;
    try {
      final drawn = await ref
          .read(infographicIllustratorProvider)
          .illustrate(
            creationId: creation.id,
            content: content,
            design: widget.design,
            slots: slots,
            accountId: _requestedAccount(creation),
            cancellation: signal,
            onProgress: (done, total) {
              if (mounted) setState(() => _done = done);
            },
          );
      final saved = await ref
          .read(studyCreationRepositoryProvider)
          .amend(creation.id, content: drawn.encode());
      final failed = slots.where((s) => drawn.failures.containsKey(s.id));
      result = saved.isLeft()
          ? l10n.f43IgDrawSaveFailed
          : l10n.f43IgDrawResult(slots.length - failed.length, failed.length);
    } on CreationCancelledException {
      result = l10n.f43IgDrawCancelled;
    }
    if (!mounted) return;
    setState(() {
      _signal = null;
      _result = result;
    });
  }

  void _onAlternative(IllustrationAlternative alternative) {
    setState(() {
      switch (alternative) {
        case ContinueWithoutIllustrations():
          _pending = null;
        case UseOtherImageAccount(:final account):
          _accountChosen = true;
          _accountId = account.id;
        case UseOnDeviceModel(:final side):
          _accountChosen = true;
          _accountId = side.account.id;
        case AddImageKey() || AddHuggingFaceToken():
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final creation = ref
        .watch(studyCreationProvider(widget.creationId))
        .valueOrNull;
    final content = InfographicContent.decode(creation?.content);
    final sheet = content.sheet;
    final slots = InfographicIllustrationPlan.slotsFor(sheet, widget.design);
    final missing = [
      for (final slot in slots)
        if (InfographicIllustrationPlan.referenceOf(sheet, slot.id) == null)
          slot.id,
    ];
    final images =
        ref
            .watch(
              infographicImagesProvider(InfographicIllustrations.of(sheet)),
            )
            .valueOrNull ??
        const <String, ImageProvider>{};
    final pending = _pending;

    return Material(
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
            key: const Key('infographic-illustrations-sheet'),
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
                        Icons.auto_awesome,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.f43IgIllustrationsTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    CreationCloseButton(tooltip: l10n.f43InfoDesignClose),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.f43IgIllustrationsIntro,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (creation == null || slots.isEmpty)
                        Text(
                          l10n.f43IgIllustrationsNone,
                          key: const Key('infographic-illustrations-none'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      for (final slot in slots)
                        _SlotRow(
                          key: ValueKey('infographic-slot-${slot.id}'),
                          slot: slot,
                          label: slot.isHeader
                              ? l10n.f43IgSlotHeader
                              : sheet.blocks[slot.blockIndex!].headline,
                          image:
                              switch (InfographicIllustrationPlan.referenceOf(
                                sheet,
                                slot.id,
                              )) {
                                final String reference => images[reference],
                                null => null,
                              },
                          done:
                              InfographicIllustrationPlan.referenceOf(
                                sheet,
                                slot.id,
                              ) !=
                              null,
                          failure: content.failures[slot.id] == null
                              ? null
                              : illustrationReason(
                                  l10n,
                                  content.failures[slot.id]!,
                                  account: content.accountLabel,
                                ),
                          enabled: !_running,
                          onDraw: () => setState(() {
                            _pending = [slot.id];
                            _result = null;
                          }),
                        ),
                      if (_result != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _result!,
                          key: const Key('infographic-illustrations-result'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (_running) ...[
                        const SizedBox(height: 16),
                        _Progress(
                          done: _done,
                          total: _total,
                          onCancel: () => _signal?.cancel(),
                        ),
                      ] else if (pending != null && creation != null) ...[
                        const SizedBox(height: 16),
                        _CostPanel(
                          count: pending.length,
                          accountId: _requestedAccount(creation),
                          onAlternative: _onAlternative,
                          onCancel: () => setState(() => _pending = null),
                          onConfirm: () => unawaited(_draw(creation, pending)),
                        ),
                      ] else if (missing.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('infographic-complete-missing'),
                          onPressed: () => setState(() {
                            _pending = missing;
                            _result = null;
                          }),
                          icon: const Icon(Icons.auto_awesome),
                          label: Text(
                            l10n.f43IgCompleteMissing(missing.length),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un lugar con su ilustración: la miniatura (la de verdad, o un recuadro),
/// qué es, cómo está y «Rehacer» o «Dibujar».
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.label,
    required this.image,
    required this.done,
    required this.failure,
    required this.enabled,
    required this.onDraw,
    super.key,
  });

  final InfographicSlot slot;
  final String label;
  final ImageProvider? image;
  final bool done;
  final String? failure;
  final bool enabled;
  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Una que no se pudo rehacer conserva la de antes, y lo dice.
    final status = switch ((done, failure)) {
      (true, null) => l10n.f43IgSlotDone,
      (true, final String reason) => l10n.f43IgSlotRedoFailed(reason),
      (false, final String reason) => l10n.f43IgSlotFailed(reason),
      (false, null) => l10n.f43IgSlotMissing,
    };
    final thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox.square(
        dimension: 52,
        child: image != null
            ? Image(
                image: image!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(scheme),
              )
            : _placeholder(scheme),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(
            children: [
              ExcludeSemantics(child: thumbnail),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: failure != null
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                key: ValueKey('infographic-slot-draw-${slot.id}'),
                onPressed: enabled ? onDraw : null,
                child: Text(done ? l10n.f43IgRedo : l10n.f43IgDraw),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _placeholder(ColorScheme scheme) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Icon(Icons.brush_outlined, color: scheme.onSurfaceVariant),
  );
}

/// Lo que cuesta antes de dibujar: «Con tu IA actual» solo con las imágenes,
/// y «Cancelar» · «Dibujar».
class _CostPanel extends ConsumerWidget {
  const _CostPanel({
    required this.count,
    required this.accountId,
    required this.onAlternative,
    required this.onCancel,
    required this.onConfirm,
  });

  final int count;
  final String? accountId;
  final ValueChanged<IllustrationAlternative> onAlternative;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final estimate = ref.watch(
      creationEstimateProvider(
        CreationEstimateRequest(
          inputTokens: 0,
          expectedOutputTokens: 0,
          textRequests: 0,
          images: count,
          imageAccountId: accountId,
        ),
      ),
    );
    return Column(
      key: const Key('infographic-illustrations-cost'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AiCapabilityCard(
          estimate: estimate,
          illustrationsOnly: true,
          onAlternative: onAlternative,
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              key: const Key('infographic-illustrations-back'),
              onPressed: onCancel,
              child: Text(l10n.f43IgBack),
            ),
            FilledButton.icon(
              key: const Key('infographic-illustrations-confirm'),
              onPressed: estimate.canIllustrate ? onConfirm : null,
              icon: const Icon(Icons.auto_awesome),
              label: Text(l10n.f43IgDrawCount(count)),
            ),
          ],
        ),
      ],
    );
  }
}

/// «Dibujando 2 de 5…», con su barra y «Cancelar».
class _Progress extends StatelessWidget {
  const _Progress({
    required this.done,
    required this.total,
    required this.onCancel,
  });

  final int done;
  final int total;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      key: const Key('infographic-illustrations-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.f43IgDrawing(done + 1 > total ? total : done + 1, total),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total == 0 ? null : done / total,
            minHeight: 6,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: const Key('infographic-illustrations-stop'),
            onPressed: onCancel,
            child: Text(l10n.f43IgStop),
          ),
        ),
      ],
    );
  }
}
