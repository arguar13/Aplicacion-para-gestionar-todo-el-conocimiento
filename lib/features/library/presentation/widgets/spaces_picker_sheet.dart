import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_naming.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja de los temas de algo (F37): marcar uno o varios de los que hay,
/// buscarlos y crear uno nuevo ahí mismo, que queda marcado.
///
/// Arranca con [selected] marcados. Con [requireOne], «Listo» no se puede
/// tocar sin ninguno marcado, y la hoja dice por qué: es lo que se está por
/// guardar, y todo lo que se guarda va a algún tema.
///
/// Devuelve los temas marcados —enteros, porque uno recién creado todavía
/// puede no haber llegado a `allSpacesProvider` y quien muestra su nombre no
/// tendría de dónde sacarlo—, o `null` si se cerró sin tocar «Listo».
Future<List<Space>?> showSpacesPickerSheet(
  BuildContext context, {
  required Set<String> selected,
  bool requireOne = false,
}) {
  return showModalBottomSheet<List<Space>>(
    context: context,
    showDragHandle: true,
    // Con el buscador, el teclado sube: sin esto la hoja queda topeada a la
    // mitad de la pantalla y el teclado tapa justo la lista que se filtra.
    isScrollControlled: true,
    builder: (context) =>
        _SpacesPickerSheet(selected: selected, requireOne: requireOne),
  );
}

class _SpacesPickerSheet extends ConsumerStatefulWidget {
  const _SpacesPickerSheet({required this.selected, required this.requireOne});

  final Set<String> selected;
  final bool requireOne;

  @override
  ConsumerState<_SpacesPickerSheet> createState() => _SpacesPickerSheetState();
}

class _SpacesPickerSheetState extends ConsumerState<_SpacesPickerSheet> {
  /// Desde cuántos temas aparece el buscador: con pocos, la lista entera se
  /// ve de una sola mirada y un campo más sería ruido.
  static const _searchFromCount = 8;

  final _searchController = TextEditingController();
  late final Set<String> _selected = {...widget.selected};

  /// Los creados en esta hoja, hasta que lleguen a `allSpacesProvider`.
  final _created = <String, Space>{};
  var _creating = false;

  /// Por qué no se pudo crear el último tema pedido, si no se pudo. Se
  /// muestra en la propia hoja: un aviso al pie quedaría tapado por ella.
  String? _createError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Los de la base y, al final, los recién creados que todavía no llegaron.
  List<Space> _all(List<Space> spaces) {
    final ids = {for (final space in spaces) space.id};
    return [
      ...spaces,
      for (final space in _created.values)
        if (!ids.contains(space.id)) space,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final spaces = _all(
      ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[],
    );

    // Sin distinguir mayúsculas ni acentos, igual que el vocabulario: quien
    // busca "filosofia" quiere encontrar "Filosofía".
    final typed = _searchController.text.trim();
    final needle = normalizeVocabularyLabel(typed);
    final visible = needle.isEmpty
        ? spaces
        : [
            for (final space in spaces)
              if (normalizeVocabularyLabel(space.name).contains(needle)) space,
          ];
    final hasExactMatch = visible.any(
      (space) => normalizeVocabularyLabel(space.name) == needle,
    );
    // Lo buscado que no es ningún tema se ofrece crear tal cual, sin pasar
    // por el diálogo del nombre: ya se escribió una vez.
    final nameToCreate = typed.isNotEmpty && !hasExactMatch ? typed : null;
    final missing = widget.requireOne && _selected.isEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l10n.spacesPickerTitle),
                subtitle: Text(l10n.spacesPickerHint),
                dense: true,
              ),
              if (spaces.length >= _searchFromCount)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l10n.spacesSearchHint,
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: _creating
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.create_new_folder_outlined),
                      title: Text(
                        nameToCreate == null
                            ? l10n.spacesNewAction
                            : l10n.spacesCreateNamed(nameToCreate),
                      ),
                      subtitle: _createError == null
                          ? null
                          : Text(
                              _createError!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                      iconColor: theme.colorScheme.primary,
                      textColor: theme.colorScheme.primary,
                      enabled: !_creating,
                      onTap: () => _create(spaces, nameToCreate),
                    ),
                    for (final space in visible)
                      CheckboxListTile(
                        secondary: const Icon(Icons.folder_outlined),
                        title: Text(space.name),
                        value: _selected.contains(space.id),
                        onChanged: (marked) => setState(() {
                          if (marked ?? false) {
                            _selected.add(space.id);
                          } else {
                            _selected.remove(space.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: missing
                          ? Text(
                              l10n.spacesPickerNeedOne,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    FilledButton(
                      onPressed: missing
                          ? null
                          : () => Navigator.of(context).pop([
                              for (final space in spaces)
                                if (_selected.contains(space.id)) space,
                            ]),
                      child: Text(l10n.spacesPickerDone),
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

  /// Crea un tema y lo deja marcado. Con [typedName] —lo buscado, que no
  /// coincide con ninguno— no pregunta el nombre de nuevo.
  Future<void> _create(List<Space> spaces, String? typedName) async {
    final l10n = AppLocalizations.of(context)!;

    final name =
        typedName ??
        await showDialog<String>(
          context: context,
          builder: (context) => SpaceNameDialog(
            title: l10n.spacesNewTitle,
            hint: l10n.spacesNameHint,
            confirmLabel: l10n.commonCreate,
          ),
        );
    if (name == null || name.trim().isEmpty || !mounted) return;

    // Un nombre que ya es un tema —sin distinguir mayúsculas ni acentos— no
    // se crea dos veces: se marca el que hay. Es lo que quería quien lo
    // escribió, y el repositorio igual rechazaría el repetido.
    final normalized = normalizeVocabularyLabel(name);
    final existing = spaces
        .where((space) => normalizeVocabularyLabel(space.name) == normalized)
        .firstOrNull;
    if (existing != null) {
      setState(() {
        _selected.add(existing.id);
        _searchController.clear();
      });
      return;
    }

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
      _createError = null;
    });
    final result = await ref.read(organizeRepositoryProvider).createSpace(name);
    if (!mounted) return;

    setState(() {
      _creating = false;
      result.match(
        (failure) => _createError = failure.localizedMessage(l10n),
        (space) {
          _created[space.id] = space;
          _selected.add(space.id);
          _searchController.clear();
        },
      );
    });
  }
}
