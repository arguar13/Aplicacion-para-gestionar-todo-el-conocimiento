import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_naming.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja de "elegir tema": sin clasificar, uno de los que hay, o uno nuevo
/// creado ahí mismo.
///
/// Compartida entre todo lo que le pone un tema a algo —el campo Tema de la
/// captura, mover un elemento solo desde el menú de tres puntos de cada
/// fila, mover varios a la vez en el modo de selección y el tema del
/// detalle—: todos necesitan exactamente la misma lista, y escribirla varias
/// veces solo serviría para que un día se desincronicen.
///
/// Crear un tema vive acá, donde se elige uno, y no como un botón suelto de
/// la biblioteca: casi siempre se crea un tema para poner algo adentro, y
/// así nace ya con lo que se iba a guardar o mover.
///
/// Devuelve el tema elegido —recién creado o no— como `(space,)`, `(null,)`
/// para "sin clasificar", o `null` a secas si se cerró sin elegir nada. Un
/// `Space?` a secas no alcanza para eso: "cerró sin elegir" y "eligió sin
/// clasificar" vuelven las dos como `null` de `Navigator.pop`, así que hace
/// falta distinguir "no se llegó a elegir nada" de "se eligió que nada es la
/// respuesta" con la propia presencia del resultado, no con su valor. Se
/// devuelve el tema entero y no su `id` porque uno recién creado todavía
/// puede no haber llegado a `allSpacesProvider`, y quien muestra su nombre
/// —un aviso de "movido a…", el propio campo— no tendría de dónde sacarlo.
Future<(Space?,)?> showSpacePickerSheet(
  BuildContext context, {
  String? selectedSpaceId,
}) {
  return showModalBottomSheet<(Space?,)>(
    context: context,
    showDragHandle: true,
    // Con el buscador, el teclado sube: sin esto la hoja queda topeada a la
    // mitad de la pantalla y el teclado tapa justo la lista que se filtra.
    isScrollControlled: true,
    builder: (context) => _SpacePickerSheet(selectedSpaceId: selectedSpaceId),
  );
}

class _SpacePickerSheet extends ConsumerStatefulWidget {
  const _SpacePickerSheet({required this.selectedSpaceId});

  final String? selectedSpaceId;

  @override
  ConsumerState<_SpacePickerSheet> createState() => _SpacePickerSheetState();
}

class _SpacePickerSheetState extends ConsumerState<_SpacePickerSheet> {
  /// Desde cuántos temas aparece el buscador: con pocos, la lista entera se
  /// ve de una sola mirada y un campo más sería ruido.
  static const _searchFromCount = 8;

  final _searchController = TextEditingController();
  var _creating = false;

  /// Por qué no se pudo crear el último tema pedido, si no se pudo. Se
  /// muestra en la propia hoja y no en un aviso al pie: la hoja tapa
  /// justamente la parte de la pantalla donde aparecería.
  String? _createError;

  @override
  void initState() {
    super.initState();
    // Lo buscado decide qué temas se ven, así que hay que redibujar a medida
    // que se escribe.
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];

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
              ListTile(title: Text(l10n.detailSpaceChoose), dense: true),
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
                    // Buscando, "sin clasificar" no es lo que se busca: solo
                    // estorbaría arriba de los resultados.
                    if (needle.isEmpty)
                      ListTile(
                        leading: const Icon(Icons.folder_off_outlined),
                        title: Text(l10n.detailSpaceNone),
                        selected: widget.selectedSpaceId == null,
                        onTap: () => Navigator.of(context).pop((null,)),
                      ),
                    for (final space in visible)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(space.name),
                        selected: widget.selectedSpaceId == space.id,
                        trailing: widget.selectedSpaceId == space.id
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.of(context).pop((space,)),
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

  /// Crea un tema y lo devuelve como elegido. Con [typedName] —lo buscado,
  /// que no coincide con ninguno— no pregunta el nombre de nuevo.
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
    // se crea dos veces: se elige el que hay. Es lo que quería quien lo
    // escribió, y el repositorio igual rechazaría el repetido.
    final normalized = normalizeVocabularyLabel(name);
    final existing = spaces
        .where((space) => normalizeVocabularyLabel(space.name) == normalized)
        .firstOrNull;
    if (existing != null) {
      Navigator.of(context).pop((existing,));
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

    result.match(
      (failure) => setState(() {
        _creating = false;
        _createError = failure.localizedMessage(l10n);
      }),
      (space) => Navigator.of(context).pop((space,)),
    );
  }
}
