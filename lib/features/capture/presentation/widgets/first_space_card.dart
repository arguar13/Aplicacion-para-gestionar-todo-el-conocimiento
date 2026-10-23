import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_naming.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La tarjeta de la captura cuando todavía no hay ningún tema (F37): todo lo
/// que se guarda va a alguno, así que antes de lo primero se crea uno, ahí
/// mismo, con solo su nombre.
///
/// Lo creado vuelve por [onCreated], para que quien guarda lo deje elegido.
class FirstSpaceCard extends ConsumerStatefulWidget {
  const FirstSpaceCard({required this.onCreated, super.key});

  final ValueChanged<Space> onCreated;

  @override
  ConsumerState<FirstSpaceCard> createState() => _FirstSpaceCardState();
}

class _FirstSpaceCardState extends ConsumerState<FirstSpaceCard> {
  final _nameController = TextEditingController();
  var _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // El botón se habilita con un nombre escrito.
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (!await confirmSpaceNameNotATag(
          context,
          ref,
          name,
          action: l10n.spacesNameIsTagCreate,
        ) ||
        !mounted) {
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });
    final result = await ref.read(organizeRepositoryProvider).createSpace(name);
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _creating = false;
        _error = failure.localizedMessage(l10n);
      }),
      widget.onCreated,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final canCreate = !_creating && _nameController.text.trim().isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.create_new_folder_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.captureFirstSpaceTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.captureFirstSpaceBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => canCreate ? _create() : null,
              decoration: InputDecoration(
                hintText: l10n.captureFirstSpaceHint,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: canCreate ? _create : null,
                icon: _creating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text(l10n.captureFirstSpaceCreate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
