import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_capability_card.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_usage_bar.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_kind_icon.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los idiomas de «Seleccionar idioma», cada uno con su nombre en su idioma.
const kCreationLanguages = <(String, String)>[
  ('es', 'Español'),
  ('en', 'English'),
  ('pt', 'Português'),
  ('fr', 'Français'),
  ('it', 'Italiano'),
  ('de', 'Deutsch'),
];

/// Abre la hoja de personalizar de [kind] sobre [scope] (F43, punto 3 del
/// plan; decisión C: tocar una tarjeta de crear abre su hoja, ya con lo
/// último que se eligió). Con [regenerating], es «Volver a generar con otras
/// opciones» de esa creación: abre con sus opciones y sus fuentes, y
/// generar la vuelve a la cola en su mismo lugar.
Future<void> showCreationCustomizeSheet(
  BuildContext context, {
  required StudyCreationKind kind,
  required CreationScope scope,
  StudyCreation? regenerating,
}) {
  // El aviso de la creación anterior («En camino…») se dibuja encima de las
  // hojas y taparía «Generar ahora», que va abajo y fijo: abrir otra hoja lo
  // da por leído.
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => CreationCustomizeSheet(
      kind: kind,
      scope: scope,
      regenerating: regenerating,
    ),
  );
}

/// La hoja de personalizar, una sola para todas (punto 3 del plan), con el
/// esqueleto de las capturas:
///
/// - **arriba**, el ícono, el título y la ✕ redonda;
/// - **en el medio**, lo de ese tipo: las piezas comunes que pide
///   ([CreationKindSpec.fields]: idioma, fuentes, descripción, tema con sus
///   sugeridos) y sus opciones ([CreationKindSpec.options] y
///   [CreationKindSpec.optionsBuilder]); en los que piden ilustraciones, la
///   tarjeta «Con tu IA actual»;
/// - **abajo, fijo**, «Uso de IA» y «Generar más tarde» · «Generar ahora»
///   —o «Crear» en las de extraer, que no le piden nada a la IA—.
class CreationCustomizeSheet extends ConsumerStatefulWidget {
  const CreationCustomizeSheet({
    required this.kind,
    required this.scope,
    this.regenerating,
    super.key,
  });

  final StudyCreationKind kind;
  final CreationScope scope;
  final StudyCreation? regenerating;

  @override
  ConsumerState<CreationCustomizeSheet> createState() =>
      _CreationCustomizeSheetState();
}

class _CreationCustomizeSheetState
    extends ConsumerState<CreationCustomizeSheet> {
  /// Desde qué alto de hoja —con la letra de siempre; crece con la letra— la
  /// barra de abajo queda fija.
  static const _fixedBarMinHeight = 560.0;

  late CreationKindSpec _spec;
  late Map<String, Object?> _options;
  late String _language;
  String? _imageAccountId;

  /// Las fuentes tildadas; `null` es «todas las del recorte».
  Set<String>? _picked;
  var _sourcesOpen = false;
  var _busy = false;

  /// «Cómo» (F43, M18): si se eligió «Para cada documento», y su «También los
  /// que ya tienen». Abre siempre en una sola creación: «Para cada documento»
  /// pone a trabajar a la IA con cada uno, y eso se elige cada vez.
  var _eachDocument = false;
  var _alsoExisting = false;

  final _description = TextEditingController();
  final _topic = TextEditingController();
  final _texts = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _spec = ref.read(creationKindRegistryProvider).of(widget.kind);
    final last = ref.read(creationLastChoicesProvider);
    final regenerating = widget.regenerating;
    final saved = regenerating?.options ?? last.optionsOf(widget.kind);
    _options = _spec.withDefaults(saved);
    _language = regenerating?.languageCode ?? last.languageCode ?? 'es';
    if (regenerating != null) {
      _picked = regenerating.sourceIds.toSet();
      _description.text = _textOf(saved, CreationOptionKeys.description);
      _topic.text = _textOf(saved, CreationOptionKeys.topic);
      final account = saved[CreationOptionKeys.imageAccountId];
      _imageAccountId = account is String ? account : null;
    }
  }

  static String _textOf(Map<String, Object?> options, String key) {
    final value = options[key];
    return value is String ? value : '';
  }

  @override
  void dispose() {
    _description.dispose();
    _topic.dispose();
    for (final controller in _texts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _set(String key, Object? value) => setState(() => _options[key] = value);

  /// Los documentos tildados, en el orden del recorte.
  List<String> _chosen(List<String> all) => [
    for (final id in all)
      if (_picked == null || _picked!.contains(id)) id,
  ];

  void _toggleSource(List<String> all, String id, {required bool on}) {
    setState(() {
      final picked = _picked ?? all.toSet();
      on ? picked.add(id) : picked.remove(id);
      _picked = picked.length == all.length && all.every(picked.contains)
          ? null
          : picked;
    });
  }

  /// Lo que eligió en «Con tu IA actual»: seguir sin ilustraciones, otra
  /// cuenta o el modelo del teléfono. Agregar una clave lo resuelve la
  /// tarjeta misma.
  void _onAlternative(IllustrationAlternative alternative) {
    setState(() {
      switch (alternative) {
        case ContinueWithoutIllustrations():
          for (final option in _spec.options) {
            if (option is CreationToggleOption && option.illustrations) {
              _options[option.key] = false;
            }
          }
          _imageAccountId = null;
        case UseOtherImageAccount(:final account):
          _imageAccountId = account.id;
        case UseOnDeviceModel(:final side):
          _imageAccountId = side.account.id;
        case AddImageKey() || AddHuggingFaceToken():
          break;
      }
    });
  }

  /// Si la hoja pregunta «Cómo» (F43, M18): el tipo lo ofrece y hay más de un
  /// documento tildado. Con uno solo no hay pregunta: es una creación. Volver
  /// a generar es de una creación que ya existe: tampoco.
  bool _offersHow(List<String> chosen) =>
      _spec.eachDocument != null &&
      widget.regenerating == null &&
      chosen.length > 1;

  /// Si va «Para cada documento»: elegido, y todavía con la pregunta a la
  /// vista (destildar hasta dejar uno vuelve a una creación).
  bool _isEach(List<String> chosen) => _eachDocument && _offersHow(chosen);

  CreationEachDocumentContext _eachContext(List<String> chosen) =>
      CreationEachDocumentContext(
        sourceIds: chosen,
        options: Map.unmodifiable(_options),
        languageCode: _language,
        topic: () => _topic.text.trim(),
        alsoExisting: _alsoExisting,
        setAlsoExisting: (on) => setState(() => _alsoExisting = on),
        finish: _finishEach,
      );

  /// Lo pidió «Para cada documento»: se recuerda lo elegido como al generar,
  /// y la hoja se cierra con su aviso. No hay fila en «Lo creado»: el avance
  /// se ve en el aviso de arriba de Repasar.
  Future<void> _finishEach(String message) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await ref
        .read(creationLastChoicesProvider)
        .save(widget.kind, _options, _language);
    if (!mounted) return;
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generate(List<String> sourceIds, {required bool runNow}) async {
    if (sourceIds.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final description = _description.text.trim();
    final topic = _topic.text.trim();
    final options = <String, Object?>{
      ..._options,
      if (_spec.fields.contains(CreationField.description) &&
          description.isNotEmpty)
        CreationOptionKeys.description: description,
      if (_spec.fields.contains(CreationField.topic) && topic.isNotEmpty)
        CreationOptionKeys.topic: topic,
      if (_imageAccountId != null && _spec.illustrationsFor(_options) > 0)
        CreationOptionKeys.imageAccountId: _imageAccountId,
    };
    setState(() => _busy = true);
    // Lo elegido se recuerda para la próxima; lo que se escribió para este
    // recorte —la descripción, el tema, la cuenta de un aviso— no.
    await ref
        .read(creationLastChoicesProvider)
        .save(widget.kind, _options, _language);
    final queue = ref.read(creationQueueProvider);
    final regenerating = widget.regenerating;
    final result = regenerating == null
        ? await queue.create(
            CreationRequest(
              kind: widget.kind,
              scope: widget.scope,
              sourceIds: sourceIds,
              options: options,
              languageCode: _language,
              runNow: runNow,
            ),
          )
        : await queue.regenerate(
            regenerating.id,
            runNow: runNow,
            options: options,
            sourceIds: sourceIds,
            languageCode: _language,
          );
    if (!mounted) return;
    result.match(
      (_) {
        setState(() => _busy = false);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.f43StudioCreateFailed)));
      },
      (_) {
        navigator.pop();
        final text = !_spec.usesAi
            ? l10n.f43StudioCreatedSnack
            : (runNow ? l10n.f43StudioQueuedSnack : l10n.f43StudioLaterSnack);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final all = ref
        .watch(creationScopeDocumentIdsProvider(widget.scope))
        .valueOrNull;
    final chosen = all == null ? const <String>[] : _chosen(all);
    final each = _isEach(chosen) ? _spec.eachDocument : null;
    final eachContext = each == null ? null : _eachContext(chosen);
    // «Uso de IA» estima una creación: «Para cada documento» no lo es.
    final estimate = _spec.usesAi && chosen.isNotEmpty && each == null
        ? _estimate(chosen)
        : null;
    final maxHeight = media.size.height * 0.92;
    final Widget bar = each != null && eachContext != null
        ? _BarFrame(child: each.action(context, eachContext))
        : _ActionBar(
            usesAi: _spec.usesAi,
            estimate: estimate,
            estimating: _spec.usesAi && chosen.isNotEmpty && estimate == null,
            busy: _busy,
            canGenerate: chosen.isNotEmpty,
            onNow: () => unawaited(_generate(chosen, runNow: true)),
            onLater: () => unawaited(_generate(chosen, runNow: false)),
          );
    final onlyForOne = each?.onlyForOne ?? const <String>{};
    // Abajo y fijo, como en las capturas, mientras deje lugar para las
    // opciones. Con la letra muy grande en un teléfono bajo, la barra sola
    // ocuparía casi toda la hoja: pasa al final de la lista, que se desplaza.
    final fixedBar =
        maxHeight >= MediaQuery.textScalerOf(context).scale(_fixedBarMinHeight);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          key: const Key('creation-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  CreationKindIcon(spec: _spec, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _spec.sheetTitle(l10n),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  CreationCloseButton(
                    key: const Key('creation-sheet-close'),
                    tooltip: l10n.f43StudioClose,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_spec.usesAi) _extractIntro(context, chosen),
                    ..._commonFields(context, all, chosen),
                    for (final option in _spec.options)
                      if (option.isVisible(_options) &&
                          !onlyForOne.contains(option.key))
                        ..._option(context, option),
                    if (_spec.optionsBuilder case final builder?)
                      builder(
                        context,
                        CreationOptionsContext(
                          kind: widget.kind,
                          scope: widget.scope,
                          options: Map.unmodifiable(_options),
                          set: _set,
                          sources: _sourcesOf(all),
                        ),
                      ),
                    if (each != null && eachContext != null)
                      each.panel(context, eachContext),
                    if (estimate != null &&
                        (estimate.wantsIllustrations ||
                            !estimate.canWriteText)) ...[
                      const SizedBox(height: 20),
                      AiCapabilityCard(
                        estimate: estimate,
                        onAlternative: _onAlternative,
                      ),
                    ],
                    if (!fixedBar) ...[const SizedBox(height: 16), bar],
                  ],
                ),
              ),
            ),
            if (fixedBar) bar,
          ],
        ),
      ),
    );
  }

  /// Lo que estima «Uso de IA» para lo elegido ahora: el material se arma
  /// igual que en la cola —el texto entero, el resumen, la síntesis o por
  /// partes— para la ventana del modelo elegido. `null` mientras se arma.
  CreationEstimate? _estimate(List<String> chosen) {
    final output = _spec.outputTokensFor(_options);
    final material = ref
        .watch(
          creationSheetMaterialProvider(
            CreationMaterialRequest(
              sourceIds: CreationSourceIds(chosen),
              outputTokens: output,
            ),
          ),
        )
        .valueOrNull;
    if (material == null) return null;
    // Por partes, cada parte es un pedido con su borrador y un último pedido
    // los une; de una vez, uno solo.
    final parts = material.mode.isSingle ? 0 : material.parts.length;
    final requests = parts + 1;
    return ref.watch(
      creationEstimateProvider(
        CreationEstimateRequest(
          inputTokens:
              material.estimatedInputTokens +
              kCreationInstructionTokens * requests,
          expectedOutputTokens: output + parts * math.min(output, 600),
          textRequests: requests,
          images: _spec.illustrationsFor(_options),
          imageAccountId: _imageAccountId,
        ),
      ),
    );
  }

  List<CreationSource> _sourcesOf(List<String>? all) => all == null
      ? const []
      : ref
                .watch(creationSourcesProvider(CreationSourceIds(all)))
                .valueOrNull ??
            const [];

  /// Las de extraer: qué hacen, y a cuántas fuentes les falta lo que muestran
  /// (se les pide el análisis al crear).
  Widget _extractIntro(BuildContext context, List<String> chosen) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sources = chosen.isEmpty
        ? const <CreationSource>[]
        : ref
                  .watch(creationSourcesProvider(CreationSourceIds(chosen)))
                  .valueOrNull ??
              const <CreationSource>[];
    final missing = sources.where((s) {
      if (!s.isLive) return false;
      return switch (widget.kind) {
        StudyCreationKind.summary => !s.hasSummary,
        StudyCreationKind.synthesis => !s.hasSynthesis,
        _ => !s.hasKeywords,
      };
    }).length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.f43StudioExtractIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (missing > 0) ...[
            const SizedBox(height: 8),
            Text(
              l10n.f43StudioExtractMissing(missing),
              key: const Key('creation-extract-missing'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _commonFields(
    BuildContext context,
    List<String>? all,
    List<String> chosen,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final fields = _spec.fields;
    return [
      if (fields.contains(CreationField.language)) ...[
        CreationSectionLabel(l10n.f43StudioLanguage),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _PickerPill<String>(
            key: const Key('creation-language'),
            icon: Icons.translate,
            value: _language,
            items: [
              for (final (code, name) in kCreationLanguages) (code, name),
            ],
            onChanged: (code) => setState(() => _language = code),
          ),
        ),
      ],
      // Las fuentes van siempre: sin ellas no hay nada que crear.
      CreationSectionLabel(l10n.f43StudioSourcesTitle),
      _sources(context, all, chosen),
      if (_offersHow(chosen)) ..._howField(context, _spec.eachDocument!),
      if (fields.contains(CreationField.description)) ...[
        CreationSectionLabel(l10n.f43StudioDescribe),
        TextField(
          key: const Key('creation-description'),
          controller: _description,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: (_spec.descriptionHint ?? (l) => l.f43StudioDescribeHint)(
              l10n,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
      if (fields.contains(CreationField.topic)) ..._topicField(context),
    ];
  }

  Widget _sources(
    BuildContext context,
    List<String>? all,
    List<String> chosen,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (all != null && all.isEmpty) {
      return Text(
        l10n.f43StudioSourcesEmpty,
        key: const Key('creation-sources-empty'),
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
      );
    }
    final total = all?.length ?? 0;
    final partial = all != null && chosen.length != total;
    final count = l10n.f43StudioSources(chosen.length);
    final ofTotal = l10n.f43StudioSourcesOf(chosen.length, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('creation-sources-toggle'),
            onTap: all == null
                ? null
                : () => setState(() => _sourcesOpen = !_sourcesOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.source_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      partial ? '$count ($ofTotal)' : count,
                      key: const Key('creation-sources-count'),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  Icon(_sourcesOpen ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
        ),
        if (chosen.isEmpty && all != null && all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.f43StudioSourcesNoneChosen,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        if (_sourcesOpen && all != null) _sourceList(context, all, chosen),
      ],
    );
  }

  Widget _sourceList(
    BuildContext context,
    List<String> all,
    List<String> chosen,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final sources = _sourcesOf(all);
    final chosenSet = chosen.toSet();
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: const Key('creation-sources-all'),
            onPressed: _picked == null
                ? null
                : () => setState(() => _picked = null),
            child: Text(l10n.f43StudioSourcesAll),
          ),
        ),
        // Con muchas, la lista se desplaza sola dentro de la hoja.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: scaler.scale(300)),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sources.length,
            itemBuilder: (context, index) {
              final source = sources[index];
              final marks = [
                if (source.hasSummary) l10n.f43StudioHasSummary,
                if (source.hasSynthesis) l10n.f43StudioHasSynthesis,
              ];
              return CheckboxListTile(
                key: ValueKey('creation-source-option-${source.documentId}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: chosenSet.contains(source.documentId),
                title: Text(
                  source.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: marks.isEmpty ? null : Text(marks.join(' · ')),
                onChanged: (on) =>
                    _toggleSource(all, source.documentId, on: on ?? false),
              );
            },
          ),
        ),
      ],
    );
  }

  /// «Cómo» (F43, M18): una creación o «Para cada documento», y, con este,
  /// qué va a pasar.
  List<Widget> _howField(BuildContext context, CreationEachDocument each) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return [
      CreationSectionLabel(l10n.f43S21How),
      CreationSegmented<bool>(
        keyPrefix: 'creation-how',
        selected: _eachDocument,
        onChanged: (value) => setState(() => _eachDocument = value),
        segments: [
          CreationSegment(value: false, label: each.oneLabel(l10n), id: 'one'),
          CreationSegment(value: true, label: each.eachLabel(l10n), id: 'each'),
        ],
      ),
      if (_eachDocument) ...[
        const SizedBox(height: 8),
        Text(
          each.eachHint(l10n),
          key: const Key('creation-how-each-hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }

  List<Widget> _topicField(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final suggested =
        ref.watch(creationSuggestedTopicsProvider(widget.scope)).valueOrNull ??
        const <String>[];
    return [
      CreationSectionLabel(l10n.f43StudioTopic),
      TextField(
        key: const Key('creation-topic'),
        controller: _topic,
        decoration: InputDecoration(
          hintText: l10n.f43StudioTopicHint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      if (suggested.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          l10n.f43StudioSuggested,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final topic in suggested)
              ActionChip(
                key: ValueKey('creation-suggested-$topic'),
                avatar: const Icon(Icons.add, size: 18),
                label: Text(topic),
                shape: const StadiumBorder(),
                onPressed: () => setState(() => _topic.text = topic),
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _option(BuildContext context, CreationOptionSpec option) {
    final l10n = AppLocalizations.of(context)!;
    final key = 'creation-option-${option.key}';
    return switch (option) {
      final CreationChoiceOption o => [
        CreationSectionLabel(o.label(l10n)),
        if (o.asMenu)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _PickerPill<String>(
              key: ValueKey(key),
              icon: Icons.palette_outlined,
              value: o.valueIn(_options),
              items: [for (final c in o.choices) (c.value, c.label(l10n))],
              onChanged: (value) => _set(o.key, value),
            ),
          )
        else
          CreationSegmented<String>(
            keyPrefix: key,
            selected: o.valueIn(_options),
            onChanged: (value) => _set(o.key, value),
            segments: [
              for (final c in o.choices)
                CreationSegment(
                  value: c.value,
                  label: c.label(l10n),
                  id: c.value,
                ),
            ],
          ),
      ],
      final CreationMultiChoiceOption o => [
        CreationSectionLabel(o.label(l10n)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in o.choices)
              FilterChip(
                key: ValueKey('$key-${c.value}'),
                label: Text(c.label(l10n)),
                shape: const StadiumBorder(),
                selected: o.valuesIn(_options).contains(c.value),
                onSelected: (on) {
                  final values = o.valuesIn(_options).toSet();
                  on ? values.add(c.value) : values.remove(c.value);
                  // Al menos uno: un cuestionario sin tipos de pregunta no
                  // pregunta nada.
                  if (values.isEmpty) return;
                  _set(o.key, [
                    for (final choice in o.choices)
                      if (values.contains(choice.value)) choice.value,
                  ]);
                },
              ),
          ],
        ),
      ],
      final CreationToggleOption o => [
        const SizedBox(height: 12),
        SwitchListTile(
          key: ValueKey(key),
          contentPadding: EdgeInsets.zero,
          title: Text(o.label(l10n)),
          subtitle: o.hint == null ? null : Text(o.hint!(l10n)),
          value: o.valueIn(_options),
          onChanged: (on) => _set(o.key, on),
        ),
      ],
      final CreationTextOption o => [
        CreationSectionLabel(o.label(l10n)),
        TextField(
          key: ValueKey(key),
          controller: _texts.putIfAbsent(
            o.key,
            () => TextEditingController(text: _textOf(_options, o.key)),
          ),
          minLines: 1,
          maxLines: o.maxLines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: o.hint?.call(l10n),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          // Sin `setState`: el texto no cambia nada de lo que se ve.
          onChanged: (text) => _options[o.key] = text,
        ),
      ],
    };
  }
}

/// Abajo, fijo: «Uso de IA» y los botones.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.usesAi,
    required this.estimate,
    required this.estimating,
    required this.busy,
    required this.canGenerate,
    required this.onNow,
    required this.onLater,
  });

  final bool usesAi;
  final CreationEstimate? estimate;
  final bool estimating;
  final bool busy;
  final bool canGenerate;
  final VoidCallback onNow;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = canGenerate && !busy;
    // Si la IA elegida no puede escribir ahora, «Generar ahora» no se ofrece:
    // la tarjeta de arriba dice por qué, y «más tarde» espera a que pueda.
    final canNow = enabled && (estimate?.canWriteText ?? true);
    return _BarFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (usesAi) ...[
            Text(
              l10n.f43StudioAiUsage,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            if (estimate case final estimate?)
              AiUsageBar(estimate: estimate)
            else if (estimating)
              Text(
                l10n.f43StudioEstimating,
                key: const Key('creation-estimating'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
          ],
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            overflowAlignment: OverflowBarAlignment.end,
            children: usesAi
                ? [
                    OutlinedButton(
                      key: const Key('creation-generate-later'),
                      style: creationSheetButtonStyle,
                      onPressed: enabled ? onLater : null,
                      child: Text(l10n.f43StudioGenerateLater),
                    ),
                    FilledButton.icon(
                      key: const Key('creation-generate-now'),
                      style: creationSheetButtonStyle,
                      onPressed: canNow ? onNow : null,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(l10n.f43StudioGenerateNow),
                    ),
                  ]
                : [
                    FilledButton.icon(
                      key: const Key('creation-create'),
                      style: creationSheetButtonStyle,
                      onPressed: enabled ? onNow : null,
                      icon: const Icon(Icons.check),
                      label: Text(l10n.f43StudioCreateNow),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// Los botones de abajo de la hoja: altos y redondos, como en las capturas.
/// Los usa también el botón de «Para cada documento» (F43, M18).
final creationSheetButtonStyle = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  ),
);

/// El fondo de la barra de abajo, con su borde arriba y el margen del
/// sistema: el mismo para «Uso de IA» con sus botones y para el botón de
/// «Para cada documento».
class _BarFrame extends StatelessWidget {
  const _BarFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: child,
        ),
      ),
    );
  }
}

/// Una píldora que muestra lo elegido y abre la lista: el idioma, la
/// plantilla.
class _PickerPill<T> extends StatelessWidget {
  const _PickerPill({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
    super.key,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label =
        items.where((i) => i.$1 == value).firstOrNull?.$2 ?? items.first.$2;
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      tooltip: label,
      itemBuilder: (context) => [
        for (final (item, name) in items)
          PopupMenuItem<T>(
            key: ValueKey('picker-item-$item'),
            value: item,
            child: Text(name),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
