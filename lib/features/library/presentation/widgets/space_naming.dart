import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Avisa si [name] ya es una etiqueta (un valor de Tema) y pregunta si se
/// sigue igual. Devuelve `true` si no hay nada que avisar o si se sigue.
///
/// Un tema y una etiqueta se llaman igual y no son lo mismo —el tema es una
/// carpeta y un elemento está en una sola; la etiqueta se pone a muchos—: con
/// el mismo nombre se confunden. Avisar y dejar seguir, no impedir.
///
/// Compartido entre crear un tema —desde el selector de temas, en la captura
/// o al mover algo— y renombrarlo desde el panel de filtros: el mismo nombre
/// confunde igual venga de donde venga. [action] es el texto del botón que
/// sigue adelante ("Crear igual", "Renombrar igual").
Future<bool> confirmSpaceNameNotATag(
  BuildContext context,
  WidgetRef ref,
  String name, {
  required String action,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final isTag =
      (await ref.read(organizeRepositoryProvider).isTemaValueName(name))
          .getOrElse((_) => false);
  if (!isTag || !context.mounted) return true;

  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.spacesNameIsTagTitle),
      content: Text(l10n.spacesNameIsTagBody(name.trim())),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return proceed ?? false;
}

/// Un diálogo con un solo campo de texto, para crear o renombrar un tema.
///
/// El `TextEditingController` se crea y se destruye acá adentro, atado al
/// ciclo de vida real de este `State` — y no afuera, en la función que abre
/// el diálogo con `showDialog` y lo destruye a mano apenas el `Future`
/// vuelve. Esa segunda forma parece inofensiva pero no lo es: `pop()`
/// resuelve el `Future` antes de que termine la animación de salida de la
/// ruta, así que el `TextField` todavía sigue montado un instante más
/// mientras se desvanece — y si el controller ya se destruyó para
/// entonces, ese `TextField` sigue vivo intenta usar un
/// `TextEditingController` ya destruido, lo que a su vez deja el árbol de
/// widgets en un estado inconsistente ("`_dependents.isEmpty`: is not
/// true"). Atar el controller al propio `State` de este widget hace que
/// Flutter lo destruya en el momento que le corresponde: cuando termina de
/// desmontar la ruta de verdad, no antes.
class SpaceNameDialog extends StatefulWidget {
  const SpaceNameDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.initialValue,
    super.key,
  });

  final String title;
  final String hint;
  final String confirmLabel;
  final String? initialValue;

  @override
  State<SpaceNameDialog> createState() => _SpaceNameDialogState();
}

class _SpaceNameDialogState extends State<SpaceNameDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
