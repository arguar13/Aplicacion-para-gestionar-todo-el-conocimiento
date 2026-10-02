import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/features/citations/domain/services/citation_source_of.dart';
import 'package:sinapsis/features/reference/domain/services/reference_draft.dart';
import 'package:sinapsis/features/reference/presentation/providers/reference_providers.dart';
import 'package:sinapsis/features/reference/presentation/reference_presentation.dart';
import 'package:sinapsis/features/reference/presentation/widgets/metadata_suggestion_banner.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los datos bibliográficos de una fuente (F15): lo que hace falta para citarla
/// —de qué tipo de obra es, quién la escribió, cuándo se publicó y lo que ese
/// tipo pide—, con un formulario para completarlos.
///
/// Sin nada cargado dice qué se gana con completarlo. Con datos, muestra lo
/// mínimo —el tipo, las personas, la fecha y lo que el estilo pide de esa
/// clase de obra— y pliega el resto en «Más datos». El formulario pide solo lo
/// que el tipo de obra usa, pero nunca esconde lo que la obra ya tiene.
class ReferenceSection extends ConsumerStatefulWidget {
  const ReferenceSection({required this.item, super.key});

  final KnowledgeItem item;

  @override
  ConsumerState<ReferenceSection> createState() => _ReferenceSectionState();
}

class _ReferenceSectionState extends ConsumerState<ReferenceSection> {
  var _editing = false;

  @override
  void initState() {
    super.initState();
    // Otra oportunidad de proponer lo que se pueda leer del original (F15,
    // D12): para una fuente capturada antes de que este generador
    // existiera, o cuando la primera vez —al capturar— no encontró nada
    // todavía (la página no se había terminado de archivar). Una vez por
    // apertura, no en cada reconstrucción: por eso vive en `initState` y no
    // en `build`. `createMetadataSuggestion` reemplaza lo que hubiera
    // pendiente, así que no importa si ya había una.
    unawaited(
      ref.read(metadataSuggestionGeneratorProvider).generate(widget.item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reference = ref.watch(referenceProvider(widget.item.id)).valueOrNull;
    // Mientras se lee, no se dibuja nada: un formulario vacío que después se
    // llena solo sería peor que un instante en blanco.
    if (reference == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final suggestion =
        (ref.watch(pendingSuggestionsProvider(widget.item.id)).valueOrNull ??
                const [])
            .whereType<MetadataSuggestion>()
            .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.referenceSectionTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (suggestion != null) ...[
          MetadataSuggestionBanner(suggestion: suggestion),
          const SizedBox(height: 8),
        ],
        if (_editing)
          _ReferenceForm(
            item: widget.item,
            reference: reference,
            onClose: () => setState(() => _editing = false),
          )
        else
          _ReferenceView(
            item: widget.item,
            reference: reference,
            onEdit: () => setState(() => _editing = true),
          ),
      ],
    );
  }
}

/// La referencia como se lee: lo mínimo a la vista y el resto plegado.
class _ReferenceView extends StatelessWidget {
  const _ReferenceView({
    required this.item,
    required this.reference,
    required this.onEdit,
  });

  final KnowledgeItem item;
  final ReferenceData reference;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final date = PublicationDate.fromStored(
      item.source.publishedAt,
      reference.publicationPrecision,
    );
    final dateText = publicationDateText(l10n, date);

    if (reference.isEmpty && dateText == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.referenceEmptyHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('reference-complete'),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_note),
            label: Text(l10n.referenceCompleteAction),
          ),
        ],
      );
    }

    final type = reference.type ?? citationSourceOf(item, reference).type;
    final shown = <ReferenceField, String>{
      for (final field in ReferenceField.values)
        if (_valueOf(reference, field) case final value?) field: value,
    };
    final primary = primaryFieldsFor(type);
    final more = [
      for (final field in shown.keys)
        if (!primary.contains(field)) field,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(
          label: l10n.referenceFieldType,
          value: reference.type?.label(l10n) ?? l10n.referenceNoType,
        ),
        for (final role in ContributorRole.values)
          if (reference.byRole(role).isNotEmpty)
            _InfoRow(
              label: role.listLabel(l10n),
              value: reference.byRole(role).map((c) => c.name.label).join('; '),
            ),
        if (dateText != null)
          _InfoRow(label: l10n.referenceDateTitle, value: dateText),
        for (final field in primary)
          if (shown[field] case final value?)
            _InfoRow(label: field.label(l10n, type), value: value),
        if (more.isNotEmpty)
          ExpansionTile(
            key: const Key('reference-more'),
            tilePadding: EdgeInsets.zero,
            title: Text(l10n.referenceMoreData),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final field in more)
                _InfoRow(label: field.label(l10n, type), value: shown[field]!),
            ],
          ),
        const SizedBox(height: 4),
        TextButton.icon(
          key: const Key('reference-edit'),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(l10n.referenceEditAction),
        ),
      ],
    );
  }
}

/// El valor de [field] en [reference], como texto, o `null` si no tiene.
String? _valueOf(ReferenceData reference, ReferenceField field) =>
    switch (field) {
      ReferenceField.container => reference.containerTitle,
      ReferenceField.publisher => reference.publisher,
      ReferenceField.place => reference.publisherPlace,
      ReferenceField.edition => reference.edition,
      ReferenceField.volume => reference.volume,
      ReferenceField.issue => reference.issue,
      ReferenceField.pages => reference.pages,
      ReferenceField.isbn => reference.isbn,
      ReferenceField.issn => reference.issn,
      ReferenceField.doi => reference.doi,
      ReferenceField.accessed =>
        reference.accessedAt == null
            ? null
            : isoDateText(reference.accessedAt!),
      ReferenceField.citationKey => reference.citationKey,
    };

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              contextMenuBuilder: buildSelectionMenu,
            ),
          ),
        ],
      ),
    );
  }
}

/// Una persona que se está escribiendo: su texto vive en un controlador.
class _PersonEntry {
  _PersonEntry({
    required this.id,
    required this.role,
    required String text,
    this.isInstitution = false,
  }) : controller = TextEditingController(text: text);

  /// Para que la fila conserve su identidad cuando cambia de lugar.
  final int id;
  final ContributorRole role;
  final TextEditingController controller;
  bool isInstitution;
}

/// El formulario: pide lo que el tipo de obra usa y no esconde lo que la obra
/// ya tiene.
class _ReferenceForm extends ConsumerStatefulWidget {
  const _ReferenceForm({
    required this.item,
    required this.reference,
    required this.onClose,
  });

  final KnowledgeItem item;
  final ReferenceData reference;
  final VoidCallback onClose;

  @override
  ConsumerState<_ReferenceForm> createState() => _ReferenceFormState();
}

class _ReferenceFormState extends ConsumerState<_ReferenceForm> {
  late final ReferenceDraft _initial;
  late ReferenceType? _type;
  late bool _undated;
  final _people = <_PersonEntry>[];
  final _fields = <ReferenceField, TextEditingController>{};
  late final TextEditingController _year;
  late final TextEditingController _month;
  late final TextEditingController _day;
  var _nextPersonId = 0;
  var _errors = <ReferenceDraftError>{};
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _initial = ReferenceDraft.of(
      widget.reference,
      widget.item.source.publishedAt,
    );
    _type = _initial.type;
    _undated = _initial.undated;
    for (final person in _initial.people) {
      _people.add(
        _PersonEntry(
          id: _nextPersonId++,
          role: person.role,
          text: person.text,
          isInstitution: person.isInstitution,
        ),
      );
    }
    for (final field in ReferenceField.values) {
      _fields[field] = TextEditingController(text: _initial.fields[field]);
    }
    _year = TextEditingController(text: _initial.year);
    _month = TextEditingController(text: _initial.month);
    _day = TextEditingController(text: _initial.day);
  }

  @override
  void dispose() {
    for (final person in _people) {
      person.controller.dispose();
    }
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _year.dispose();
    _month.dispose();
    _day.dispose();
    super.dispose();
  }

  /// El tipo con que se piden los datos: el elegido o, sin tipo, el que se
  /// deduce de cómo se capturó.
  ReferenceType? get _effectiveType =>
      _type ?? citationSourceOf(widget.item, const ReferenceData()).type;

  ReferenceDraft _draft() => ReferenceDraft(
    type: _type,
    people: [
      for (final person in _people)
        PersonDraft(
          role: person.role,
          text: person.controller.text,
          isInstitution: person.isInstitution,
        ),
    ],
    fields: {for (final entry in _fields.entries) entry.key: entry.value.text},
    year: _year.text,
    month: _month.text,
    day: _day.text,
    undated: _undated,
  );

  Future<void> _save() async {
    final draft = _draft();
    final errors = draft.validate();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _errors = {};
      _saving = true;
    });
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = ref.read(referenceRepositoryProvider);
      final saved = await repository.saveReference(
        widget.item.id,
        draft.build(),
      );
      final dateChanged =
          draft.year.trim() != _initial.year ||
          draft.month.trim() != _initial.month ||
          draft.day.trim() != _initial.day ||
          draft.undated != _initial.undated;
      if (saved && dateChanged) {
        await repository.savePublishedAt(widget.item.id, draft.publishedAt);
      }
      if (!saved) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.referenceSaveFailed)),
        );
        if (mounted) setState(() => _saving = false);
        return;
      }
      if (mounted) widget.onClose();
      // Ver `LibraryRepositoryImpl`: un `TypeError` es un `Error`, no una
      // `Exception`, y también hay que avisarlo.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.referenceSaveFailed)));
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addPerson(ContributorRole role) => setState(() {
    _people.add(_PersonEntry(id: _nextPersonId++, role: role, text: ''));
  });

  void _removePerson(_PersonEntry person) => setState(() {
    _people.remove(person);
    person.controller.dispose();
  });

  /// Cambia de lugar a [person] con la anterior o la siguiente de su misma
  /// clase: el orden importa dentro de cada rol, no entre roles.
  void _movePerson(_PersonEntry person, int direction) {
    final same = [
      for (final p in _people)
        if (p.role == person.role) p,
    ];
    final at = same.indexOf(person);
    final other = at + direction;
    if (other < 0 || other >= same.length) return;
    setState(() {
      final a = _people.indexOf(person);
      final b = _people.indexOf(same[other]);
      _people[a] = same[other];
      _people[b] = person;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final type = _effectiveType;

    final roles = [
      ...rolesFor(type),
      for (final role in ContributorRole.values)
        if (!rolesFor(type).contains(role) &&
            _people.any((p) => p.role == role))
          role,
    ];
    final wanted = fieldsFor(type);
    final ordered = [
      ...wanted,
      for (final field in ReferenceField.values)
        if (!wanted.contains(field) && _fields[field]!.text.trim().isNotEmpty)
          field,
    ];
    final primary = primaryFieldsFor(type);
    final primaryFields = [
      for (final field in ordered)
        if (primary.contains(field)) field,
    ];
    final moreFields = [
      for (final field in ordered)
        if (!primary.contains(field)) field,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ReferenceType?>(
          key: const Key('reference-type'),
          initialValue: _type,
          decoration: InputDecoration(labelText: l10n.referenceFieldType),
          items: [
            DropdownMenuItem<ReferenceType?>(child: Text(l10n.referenceNoType)),
            for (final option in ReferenceType.values)
              DropdownMenuItem<ReferenceType?>(
                value: option,
                child: Text(option.label(l10n)),
              ),
          ],
          onChanged: (value) => setState(() => _type = value),
        ),
        const SizedBox(height: 16),
        for (final role in roles) ...[
          Text(
            role.listLabel(l10n),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final person in _people.where((p) => p.role == role))
            _PersonRow(
              key: ValueKey('reference-person-${person.id}'),
              person: person,
              onToggleInstitution: () =>
                  setState(() => person.isInstitution = !person.isInstitution),
              onMoveUp: () => _movePerson(person, -1),
              onMoveDown: () => _movePerson(person, 1),
              onRemove: () => _removePerson(person),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: Key('reference-add-${role.name}'),
              onPressed: () => _addPerson(role),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                l10n.referenceAddPersonAction(role.label(l10n).toLowerCase()),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          l10n.referenceDateTitle,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _numberField(
                const Key('reference-year'),
                _year,
                l10n.referenceYear,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField(
                const Key('reference-month'),
                _month,
                l10n.referenceMonth,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField(
                const Key('reference-day'),
                _day,
                l10n.referenceDay,
              ),
            ),
          ],
        ),
        if (_errors.contains(ReferenceDraftError.date))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.referenceErrorDate,
              key: const Key('reference-error-date'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        SwitchListTile(
          key: const Key('reference-undated'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.referenceUndatedSwitch),
          value: _undated,
          onChanged: (value) => setState(() => _undated = value),
        ),
        const SizedBox(height: 8),
        for (final field in primaryFields) _textField(l10n, field, type),
        if (moreFields.isNotEmpty)
          ExpansionTile(
            key: const Key('reference-more-form'),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: moreFields.any(
              (field) => _fields[field]!.text.trim().isNotEmpty,
            ),
            title: Text(l10n.referenceMoreData),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final field in moreFields) _textField(l10n, field, type),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('reference-cancel'),
              onPressed: _saving ? null : widget.onClose,
              child: Text(l10n.referenceCancelAction),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('reference-save'),
              onPressed: _saving ? null : _save,
              child: Text(l10n.referenceSaveAction),
            ),
          ],
        ),
      ],
    );
  }

  Widget _numberField(
    Key key,
    TextEditingController controller,
    String label,
  ) => TextField(
    key: key,
    controller: controller,
    enabled: !_undated,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, isDense: true),
  );

  Widget _textField(
    AppLocalizations l10n,
    ReferenceField field,
    ReferenceType? type,
  ) {
    final error = switch (field) {
      ReferenceField.doi when _errors.contains(ReferenceDraftError.doi) =>
        l10n.referenceErrorDoi,
      ReferenceField.isbn when _errors.contains(ReferenceDraftError.isbn) =>
        l10n.referenceErrorIsbn,
      ReferenceField.issn when _errors.contains(ReferenceDraftError.issn) =>
        l10n.referenceErrorIssn,
      ReferenceField.accessed
          when _errors.contains(ReferenceDraftError.accessed) =>
        l10n.referenceErrorAccessed,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        key: Key('reference-field-${field.name}'),
        controller: _fields[field],
        decoration: InputDecoration(
          labelText: field.label(l10n, type),
          errorText: error,
          isDense: true,
        ),
      ),
    );
  }
}

/// Una persona: el campo donde se escribe y lo que se puede hacer con ella.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.onToggleInstitution,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    super.key,
  });

  final _PersonEntry person;
  final VoidCallback onToggleInstitution;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          TextField(
            key: Key('reference-person-field-${person.id}'),
            controller: person.controller,
            decoration: InputDecoration(
              hintText: l10n.referencePersonHint,
              isDense: true,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: l10n.referencePersonInstitution,
                isSelected: person.isInstitution,
                icon: const Icon(Icons.apartment_outlined),
                selectedIcon: const Icon(Icons.apartment),
                onPressed: onToggleInstitution,
              ),
              IconButton(
                tooltip: l10n.referencePersonMoveUp,
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: onMoveUp,
              ),
              IconButton(
                tooltip: l10n.referencePersonMoveDown,
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: onMoveDown,
              ),
              IconButton(
                tooltip: l10n.referencePersonRemove,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
