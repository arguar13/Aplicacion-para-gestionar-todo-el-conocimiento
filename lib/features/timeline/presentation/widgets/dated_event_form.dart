import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/links/presentation/providers/link_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/historical_date_form.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_item_dialog.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_seed.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/presentation/providers/dated_event_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre el formulario de un hecho fechado (F40, paso 5), para agregar uno o
/// para editar uno que ya está. Devuelve `true` si se guardó.
///
/// - Sin nada: un hecho nuevo, que la persona completa.
/// - Con [seed]: un hecho nuevo que ya trae lo que se sabe —el documento
///   preseleccionado, o una cita seleccionada con su fecha—.
/// - Con [editing]: cambia el título y las fechas de ese hecho. El documento y
///   la cita no se cambian, y guardar lo vuelve de la persona.
Future<bool> showDatedEventForm(
  BuildContext context, {
  DatedEventSeed? seed,
  TimelineEvent? editing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DatedEventForm(seed: seed, editing: editing),
  );
  return saved ?? false;
}

/// El formulario de un hecho fechado: el documento (o ninguno), qué pasó, la
/// fecha con el formulario de siempre y, si es un tramo, cuándo termina.
///
/// **Sin documento.** Todo hecho cuelga de un elemento —con él viaja a la
/// papelera, a la copia y a la unión de bóvedas, y la IA los deshace por su
/// pasada—, así que «sin documento» no es un hecho sin dueño: se guarda en la
/// nota «Hechos sueltos», que se crea la primera vez que se necesita y después
/// se reutiliza. La nota no se crea al elegirlo sino al guardar, para no dejar
/// una nota vacía por cada formulario que se cierra.
class DatedEventForm extends ConsumerStatefulWidget {
  const DatedEventForm({this.seed, this.editing, super.key});

  final DatedEventSeed? seed;
  final TimelineEvent? editing;

  @override
  ConsumerState<DatedEventForm> createState() => _DatedEventFormState();
}

class _DatedEventFormState extends ConsumerState<DatedEventForm> {
  final _title = TextEditingController();
  final _start = HistoricalDateController();
  final _end = HistoricalDateController();

  bool _hasEnd = false;

  /// Si el hecho va a la nota de los hechos sueltos y no a un documento.
  bool _loose = true;

  /// El documento elegido; `null` mientras no se eligió (o si es suelto).
  String? _itemId;

  /// Se apretó «Guardar» al menos una vez: recién ahí se marca lo que falta.
  /// Un formulario recién abierto no empieza con errores.
  bool _attempted = false;
  bool _saving = false;
  String? _saveError;

  TimelineEvent? get _editing => widget.editing;
  DatedEventSeed? get _seed => widget.seed;

  /// El documento no se cambia al editar ni cuando hay una cita: la cita es de
  /// ese texto.
  bool get _documentFixed => _editing != null || (_seed?.hasQuote ?? false);

  @override
  void initState() {
    super.initState();
    final editing = _editing;
    final seed = _seed;
    if (editing != null) {
      _title.text = editing.title;
      _start.load(editing.date);
      if (editing.end case final end?) {
        _hasEnd = true;
        _end.load(end);
      }
      _itemId = editing.itemId;
      _loose = false;
    } else if (seed != null) {
      _title.text = seed.title;
      if (seed.date case final date?) _start.load(date);
      if (seed.end case final end?) {
        _hasEnd = true;
        _end.load(end);
      }
      _itemId = seed.itemId;
      _loose = seed.itemId == null;
    }
    // Rehace lo que depende de lo escrito: el aviso de un fin anterior al
    // comienzo, el botón de guardar.
    for (final listenable in [_title, _start, _end]) {
      listenable.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Lo que dice el formulario, listo para validar y guardar, o `null` si
  /// todavía falta la fecha (o el fin que se pidió).
  DatedEventInput? _input() {
    final date = _start.date;
    if (date == null) return null;
    final HistoricalDate? end;
    if (_hasEnd) {
      end = _end.date;
      if (end == null) return null;
    } else {
      end = null;
    }
    final source = _editing;
    final seed = _seed;
    return DatedEventInput(
      title: _title.text,
      date: date,
      end: end,
      renditionId: source?.renditionId ?? seed?.renditionId,
      startOffset: source?.startOffset ?? seed?.startOffset,
      endOffset: source?.endOffset ?? seed?.endOffset,
      excerpt: source?.excerpt ?? seed?.excerpt,
    );
  }

  /// Lo que se le dice a la persona de cada campo, en su idioma. Se arma con
  /// la misma validación que después hace cumplir el repositorio.
  _Errors _errors(AppLocalizations l10n) {
    final input = _input();
    final kind = input?.problemKind;
    final startDate = _start.date;
    final endDate = _end.date;

    String? date;
    String? end;
    String? general;

    // Lo que se marca solo después del primer intento de guardar. Si la fecha
    // ya dice qué está mal (un año o un día inválidos), no se le suma un
    // «falta la fecha» que sería falso: está escrita, y mal.
    if (_attempted) {
      if (startDate == null && !_dateComplains(_start)) {
        date = l10n.timelineFormDateMissing;
      }
      if (_hasEnd && endDate == null && !_dateComplains(_end)) {
        end = l10n.timelineFormEndMissing;
      }
    }
    // Esto no: un fin anterior al comienzo se avisa apenas se escribe.
    if (kind == DatedEventProblem.endsBeforeStart) {
      end = l10n.timelineFormEndBeforeStart;
    } else if (_attempted &&
        kind != null &&
        kind != DatedEventProblem.titleMissing) {
      general = l10n.timelineFormInvalid;
    }
    final titleProblem = DatedEventInput.titleProblem(_title.text);
    return _Errors(
      title: _attempted && titleProblem == DatedEventProblem.titleMissing
          ? l10n.timelineFormTitleRequired
          : null,
      document: _attempted && !_loose && _itemId == null
          ? l10n.timelineFormDocumentRequired
          : null,
      date: date,
      end: end,
      general: general,
    );
  }

  /// Si el formulario de fecha de [controller] ya muestra su propio error.
  static bool _dateComplains(HistoricalDateController controller) =>
      controller.hasYearError || controller.hasDayError;

  Future<void> _pickDocument() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => PickItemDialog(title: l10n.timelineFormPickDocument),
    );
    if (picked != null && mounted) setState(() => _itemId = picked);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _attempted = true;
      _saveError = null;
    });
    final errors = _errors(l10n);
    final input = _input();
    if (errors.any || input == null || input.problem != null) return;

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final failure = await _persist(input, l10n);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _saving = false;
        _saveError = failure.localizedMessage(l10n);
      });
      return;
    }
    navigator.pop(true);
  }

  /// Guarda el hecho —lo cambia, si se está editando; lo agrega, si no— y
  /// devuelve lo que salió mal, o `null` si salió bien.
  Future<Failure?> _persist(
    DatedEventInput input,
    AppLocalizations l10n,
  ) async {
    final repository = ref.read(datedEventRepositoryProvider);
    final editing = _editing;
    if (editing != null) {
      final updated = await repository.update(
        editing.datedEventId!,
        title: input.title,
        date: input.date,
        end: input.end,
      );
      return updated.getLeft().toNullable();
    }

    var itemId = _itemId;
    if (_loose) {
      final note = await ref
          .read(linkRepositoryProvider)
          .findOrCreateNote(title: l10n.timelineFormLooseNoteTitle);
      final failure = note.getLeft().toNullable();
      if (failure != null) return failure;
      itemId = note.getRight().toNullable()!.item.id;
    }
    final added = await repository.add(itemId!, input);
    return added.getLeft().toNullable();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final errors = _errors(l10n);
    final editing = _editing != null;

    return Padding(
      // Con el teclado arriba, lo que se escribe queda a la vista.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      editing
                          ? l10n.timelineFormEditTitle
                          : l10n.timelineFormAddTitle,
                      key: const ValueKey('dated-event-form-heading'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    if (_quote case final quote?) ...[
                      _QuotePreview(excerpt: quote),
                      const SizedBox(height: 16),
                    ],
                    _documentSection(l10n, theme, errors.document),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('dated-event-form-title'),
                      controller: _title,
                      autofocus: !editing && _title.text.isEmpty,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.timelineFormTitleLabel,
                        hintText: l10n.timelineFormTitleHint,
                        errorText: errors.title,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.timelineFormWhen,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    HistoricalDateForm(controller: _start),
                    if (errors.date != null)
                      _FieldError(
                        key: const ValueKey('dated-event-form-date-error'),
                        message: errors.date!,
                      ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const ValueKey('dated-event-form-range'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.timelineFormRangeSwitch),
                      value: _hasEnd,
                      onChanged: (value) => setState(() => _hasEnd = value),
                    ),
                    if (_hasEnd) ...[
                      Text(
                        l10n.timelineFormUntil,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      HistoricalDateForm(controller: _end, showCirca: false),
                      if (errors.end != null)
                        _FieldError(
                          key: const ValueKey('dated-event-form-end-error'),
                          message: errors.end!,
                        ),
                    ],
                    if (errors.general != null || _saveError != null)
                      _FieldError(
                        key: const ValueKey('dated-event-form-error'),
                        message: _saveError ?? errors.general!,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('dated-event-form-cancel'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('dated-event-form-save'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _saving ? null : () => unawaited(_save()),
                    child: Text(l10n.timelineFormSave),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// La cita que acompaña al hecho, si la tiene.
  String? get _quote {
    final excerpt = _editing?.excerpt ?? _seed?.excerpt;
    return excerpt == null || excerpt.trim().isEmpty ? null : excerpt;
  }

  Widget _documentSection(
    AppLocalizations l10n,
    ThemeData theme,
    String? error,
  ) {
    final title = _documentTitle();
    final labelStyle = theme.textTheme.titleSmall;

    if (_documentFixed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.timelineFormDocumentLabel, style: labelStyle),
          const SizedBox(height: 4),
          _DocumentTile(
            key: const ValueKey('dated-event-form-document'),
            icon: _editing?.sourceKind.icon ?? Icons.description_outlined,
            title: title ?? '',
          ),
          Text(
            l10n.timelineFormDocumentFixed,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.timelineFormDocumentLabel, style: labelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('dated-event-form-doc-none'),
              label: Text(l10n.timelineFormDocumentNone),
              selected: _loose,
              onSelected: (_) => setState(() => _loose = true),
            ),
            ChoiceChip(
              key: const ValueKey('dated-event-form-doc-one'),
              label: Text(l10n.timelineFormDocumentOne),
              selected: !_loose,
              onSelected: (_) => setState(() => _loose = false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loose)
          Text(
            l10n.timelineFormDocumentLoose(l10n.timelineFormLooseNoteTitle),
            key: const ValueKey('dated-event-form-loose-hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          _DocumentTile(
            key: const ValueKey('dated-event-form-doc-pick'),
            icon: Icons.description_outlined,
            title: title ?? l10n.timelineFormPickDocument,
            muted: title == null,
            onTap: _pickDocument,
          ),
          if (error != null)
            _FieldError(
              key: const ValueKey('dated-event-form-document-error'),
              message: error,
            ),
        ],
      ],
    );
  }

  /// El título del documento elegido, o `null` si no hay o todavía carga.
  String? _documentTitle() {
    final itemId = _itemId;
    if (itemId == null || _loose) return null;
    return ref.watch(libraryItemProvider(itemId)).valueOrNull?.title ??
        _editing?.documentTitle;
  }
}

/// Los textos de error de cada campo. `null` es que no hay.
class _Errors {
  const _Errors({this.title, this.document, this.date, this.end, this.general});

  final String? title;
  final String? document;
  final String? date;
  final String? end;
  final String? general;

  /// Si hay algún error que impida guardar.
  bool get any =>
      title != null ||
      document != null ||
      date != null ||
      end != null ||
      general != null;
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una fila con el documento: elegible si tiene [onTap], de solo lectura si no.
class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.icon,
    required this.title,
    this.onTap,
    this.muted = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = muted
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: color),
                    ),
                  ),
                  if (onTap != null) Icon(Icons.expand_more, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La cita que se está fechando, de solo lectura.
class _QuotePreview extends StatelessWidget {
  const _QuotePreview({required this.excerpt});

  final String excerpt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      key: const ValueKey('dated-event-form-quote'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Semantics(
        label: l10n.timelineFormQuoteLabel,
        child: Text(
          excerpt.replaceAll(RegExp(r'\s+'), ' ').trim(),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
