import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_illustration_plan.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_kind_providers.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/widgets/infographic_illustrations_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor de una infografía (F43, punto 5): **la lámina entera**, con
/// pellizco para acercar y alejar, arrastre, y los botones −, «Ajustar» y +.
///
/// - El diseño que se ve es el guardado en las opciones —o el que se está
///   eligiendo con «Cambiar el estilo», que lo comparte con la barra
///   (`infographicLiveDesignProvider`)—: cambiarlo nunca vuelve a la IA
///   (decisión G).
/// - Las ilustraciones ya hechas se leen del almacén; las que faltan o no
///   salieron quedan dibujadas por la app, y un aviso arriba dice por qué y
///   ofrece «Completar ilustraciones» (decisión H).
/// - El lector de pantalla lee el título y cada bloque (`InfographicView`).
/// - Sin animaciones: el arrastre se detiene donde se suelta.
class InfographicViewer extends ConsumerWidget {
  const InfographicViewer({required this.creation, super.key});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final content = InfographicContent.decode(creation.content);
    final sheet = content.sheet;
    if (sheet.blocks.isEmpty) {
      return Center(
        key: const Key('infographic-viewer-unreadable'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.f43IgUnreadable,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }
    final design =
        ref.watch(infographicLiveDesignProvider(creation.id)) ??
        infographicDesignOf(creation.options);
    final images =
        ref
            .watch(
              infographicImagesProvider(InfographicIllustrations.of(sheet)),
            )
            .valueOrNull ??
        const <String, ImageProvider>{};
    final slots = InfographicIllustrationPlan.slotsFor(sheet, design);
    final notice = _Notice.of(content, design, creation, slots);

    void openIllustrations() => unawaited(
      showInfographicIllustrations(context, creation: creation, design: design),
    );

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        key: const Key('infographic-viewer'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice != null)
            // Con la letra muy grande el aviso se desplaza adentro suyo: la
            // lámina nunca queda sin lugar.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.36,
              ),
              child: _IllustrationNotice(
                notice: notice,
                onOpen: openIllustrations,
              ),
            ),
          Expanded(
            child: InfographicZoomView(
              sheet: sheet,
              design: design,
              illustrations: infographicResolver(images),
              onIllustrations: slots.isEmpty ? null : openIllustrations,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que dice el aviso de las ilustraciones.
class _Notice {
  const _Notice({
    required this.failed,
    required this.missing,
    this.failure,
    this.account,
  });

  /// Las que no salieron, de las que se ven con este diseño.
  final int failed;

  /// Las que faltan (no salieron, o el estilo nuevo las pide).
  final int missing;

  /// El porqué más repetido de las que no salieron.
  final ImageFailure? failure;
  final String? account;

  /// El aviso de [content] con [design], o `null` si no hay nada que decir:
  /// todas hechas, o una lámina sin ilustraciones que nadie pidió.
  static _Notice? of(
    InfographicContent content,
    InfographicDesign design,
    StudyCreation creation,
    List<InfographicSlot> slots,
  ) {
    final missing = [
      for (final slot in slots)
        if (InfographicIllustrationPlan.referenceOf(content.sheet, slot.id) ==
            null)
          slot,
    ];
    if (missing.isEmpty) return null;
    final failures = [for (final slot in missing) ?content.failures[slot.id]];
    final asked =
        infographicWantsIllustrations(creation.options) ||
        InfographicAuto.arrange(content.sheet, design).style.isIllustrated;
    if (failures.isEmpty && !asked) return null;
    ImageFailure? common;
    var best = 0;
    for (final failure in failures.toSet()) {
      final count = failures.where((f) => f == failure).length;
      if (count > best) {
        best = count;
        common = failure;
      }
    }
    return _Notice(
      failed: failures.length,
      missing: missing.length,
      failure: common,
      account: content.accountLabel,
    );
  }
}

/// El aviso de arriba: cuántas ilustraciones no salieron y por qué, o cuántas
/// faltan para este estilo, con «Completar ilustraciones».
class _IllustrationNotice extends StatelessWidget {
  const _IllustrationNotice({required this.notice, required this.onOpen});

  final _Notice notice;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failure = notice.failure;
    final text = failure == null
        ? l10n.f43IgNoticeMissing(notice.missing)
        : l10n.f43IgNoticeFailed(
            notice.failed,
            illustrationReason(l10n, failure, account: notice.account),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        key: const Key('infographic-illustration-notice'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      failure == null
                          ? Icons.auto_awesome
                          : Icons.brush_outlined,
                      size: 18,
                      color: failure == null ? scheme.tertiary : scheme.error,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(text, style: theme.textTheme.bodyMedium),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: const Key('infographic-complete-illustrations'),
                  onPressed: onOpen,
                  child: Text(l10n.f43IgComplete),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La lámina para mirar de cerca: pellizco y arrastre, y los botones −,
/// «Ajustar» y + (y ✨ «Ilustraciones», si las lleva) abajo a la derecha.
///
/// Los botones acercan alrededor del centro de lo que se ve, de a
/// [zoomStep], entre la lámina entera ([minScale]) y [maxScale].
class InfographicZoomView extends StatefulWidget {
  const InfographicZoomView({
    required this.sheet,
    required this.design,
    this.illustrations,
    this.onIllustrations,
    super.key,
  });

  final Infographic sheet;
  final InfographicDesign design;
  final InfographicIllustrationResolver? illustrations;
  final VoidCallback? onIllustrations;

  static const double minScale = 1;
  static const double maxScale = 6;
  static const double zoomStep = 1.5;

  @override
  State<InfographicZoomView> createState() => InfographicZoomViewState();
}

class InfographicZoomViewState extends State<InfographicZoomView> {
  final _controller = TransformationController();
  Size _viewport = Size.zero;

  /// Cuánto está acercada ahora.
  double get scale => _controller.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Acerca (o aleja, con [factor] < 1) alrededor del centro de la pantalla:
  /// lo que se ve en el medio queda en el medio.
  void zoomBy(double factor) {
    final current = scale;
    final target = (current * factor).clamp(
      InfographicZoomView.minScale,
      InfographicZoomView.maxScale,
    );
    if (target <= InfographicZoomView.minScale + 1e-6) {
      fit();
      return;
    }
    final f = target / current;
    final center = _viewport.center(Offset.zero);
    _controller.value = Matrix4.translationValues(center.dx, center.dy, 0)
      ..multiply(Matrix4.diagonal3Values(f, f, 1))
      ..multiply(Matrix4.translationValues(-center.dx, -center.dy, 0))
      ..multiply(_controller.value);
  }

  /// La lámina entera, como al abrirla.
  void fit() => _controller.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final zoomed = scale > InfographicZoomView.minScale + 1e-3;
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: scheme.surfaceContainerLowest,
                child: InteractiveViewer(
                  key: const Key('infographic-zoom'),
                  transformationController: _controller,
                  minScale: InfographicZoomView.minScale,
                  maxScale: InfographicZoomView.maxScale,
                  // Sin animaciones, el arrastre no sigue de largo al soltar.
                  interactionEndFrictionCoefficient: still ? 1e-100 : 0.0000135,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: widget.design.orientation.ratio,
                        child: InfographicView(
                          key: const Key('infographic-viewer-sheet'),
                          sheet: widget.sheet,
                          design: widget.design,
                          illustrations: widget.illustrations,
                          borderRadius: BorderRadius.circular(16),
                          shadow: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              end: 12,
              bottom: 12,
              child: Material(
                color: scheme.surfaceContainerHigh,
                elevation: 2,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onIllustrations != null) ...[
                        IconButton(
                          key: const Key('infographic-illustrations'),
                          tooltip: l10n.f43IgIllustrations,
                          onPressed: widget.onIllustrations,
                          icon: Icon(
                            Icons.auto_awesome,
                            color: scheme.tertiary,
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: VerticalDivider(
                            width: 8,
                            color: scheme.outlineVariant,
                          ),
                        ),
                      ],
                      IconButton(
                        key: const Key('infographic-zoom-out'),
                        tooltip: l10n.f43IgZoomOut,
                        onPressed: zoomed
                            ? () => zoomBy(1 / InfographicZoomView.zoomStep)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        key: const Key('infographic-zoom-fit'),
                        tooltip: l10n.f43IgZoomFit,
                        onPressed: zoomed ? fit : null,
                        icon: const Icon(Icons.fit_screen_outlined),
                      ),
                      IconButton(
                        key: const Key('infographic-zoom-in'),
                        tooltip: l10n.f43IgZoomIn,
                        onPressed: scale < InfographicZoomView.maxScale - 1e-3
                            ? () => zoomBy(InfographicZoomView.zoomStep)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
