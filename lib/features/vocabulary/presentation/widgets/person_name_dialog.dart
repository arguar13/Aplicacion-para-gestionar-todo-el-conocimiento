import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Pide el nombre de una persona con su apellido y su nombre por separado
/// (F15); `null` si se canceló.
///
/// Es un diálogo de campos y no uno de texto libre por lo mismo que el
/// vocabulario guarda el nombre partido: una cita escribe «García Márquez, G.»
/// en la bibliografía y «Gabriel García Márquez» en una nota, y eso no se
/// puede hacer con un texto entero sin adivinar dónde termina el apellido. Con
/// [initial] los campos arrancan con lo que la persona ya tiene.
///
/// Debajo de los campos se ve cómo va a quedar guardada, «Apellido, Nombre»:
/// es la etiqueta con que el vocabulario la compara con las demás.
Future<PersonName?> askPersonName(
  BuildContext context, {
  required String title,
  PersonName? initial,
}) {
  return showDialog<PersonName>(
    context: context,
    builder: (context) => _PersonNameDialog(title: title, initial: initial),
  );
}

class _PersonNameDialog extends StatefulWidget {
  const _PersonNameDialog({required this.title, this.initial});

  final String title;
  final PersonName? initial;

  @override
  State<_PersonNameDialog> createState() => _PersonNameDialogState();
}

class _PersonNameDialogState extends State<_PersonNameDialog> {
  late final TextEditingController _family = TextEditingController(
    text: widget.initial?.family,
  );
  late final TextEditingController _given = TextEditingController(
    text: widget.initial?.given,
  );
  late final TextEditingController _suffix = TextEditingController(
    text: widget.initial?.suffix,
  );
  late bool _isInstitution = widget.initial?.isInstitution ?? false;

  @override
  void dispose() {
    _family.dispose();
    _given.dispose();
    _suffix.dispose();
    super.dispose();
  }

  /// El nombre que dicen los campos. Una institución no lleva nombre de pila
  /// ni sufijo, aunque hayan quedado escritos antes de marcarla.
  PersonName get _name => PersonName(
    family: _family.text.trim(),
    given: _isInstitution ? '' : _given.text.trim(),
    suffix: _isInstitution ? '' : _suffix.text.trim(),
    isInstitution: _isInstitution,
  );

  void _submit() {
    if (_name.family.isEmpty) return;
    Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = _name;

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _family,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l10n.personFamilyLabel),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (!_isInstitution) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _given,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.personGivenLabel),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _suffix,
                decoration: InputDecoration(labelText: l10n.personSuffixLabel),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.personIsInstitutionLabel),
              value: _isInstitution,
              onChanged: (value) => setState(() => _isInstitution = value),
            ),
            if (name.family.isNotEmpty)
              Text(
                l10n.personLabelPreview(name.label),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        // Sin apellido no hay a quién guardar.
        TextButton(
          onPressed: name.family.isEmpty ? null : _submit,
          child: Text(l10n.personDialogSave),
        ),
      ],
    );
  }
}
