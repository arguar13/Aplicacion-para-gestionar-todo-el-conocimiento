import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/custom_text_field.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/capture/data/adapters/file_adapter.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_notifier.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_state.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Meter algo en la bóveda.
///
/// Un solo campo grande, sin elegir antes de qué se trata: quien captura pega
/// lo que tiene y la app reconoce qué es. Obligar a declarar "esto es un
/// enlace" o "esto es una nota" convertiría un gesto de dos segundos en un
/// formulario.
///
/// Lo que sí se muestra es *qué entendió* la app, y en vivo. Ver "se va a
/// guardar como YouTube" antes de apretar nada evita la sorpresa de
/// descubrir después que algo quedó clasificado donde no iba.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _inputController = TextEditingController();
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();

  /// El archivo elegido, si hay uno.
  ///
  /// Vive en la pantalla y no en el notifier porque es estado de la pantalla:
  /// mientras no se apriete guardar, no le incumbe a nadie más. Lo que sí
  /// sale de acá es que la captura pasa a ser de archivo y no de texto.
  CapturedFile? _file;

  @override
  void initState() {
    super.initState();
    // Lo escrito decide qué se muestra abajo, así que hay que redibujar a
    // medida que se escribe.
    _inputController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputController
      ..removeListener(_onInputChanged)
      ..dispose();
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  /// Qué va a guardar la app con lo que hay escrito ahora.
  ///
  /// Se le pregunta al mismo registro de adaptadores que hará el trabajo de
  /// verdad, y no a una copia de las reglas escrita para la interfaz: dos
  /// versiones de la misma lógica terminan discrepando, y entonces la
  /// pantalla promete una cosa y la app guarda otra.
  SourceKind? get _detectedKind {
    final input = _inputController.text.trim();
    if (input.isEmpty) return null;

    return ref
        .read(sourceAdapterRegistryProvider)
        .resolve(CaptureRequest.text(rawInput: input))
        .producesKind;
  }

  /// Abre el selector del sistema.
  ///
  /// Cancelar no es un error y no muestra nada: es la respuesta más común de
  /// un selector de archivos, porque abrirlo por accidente pasa todo el
  /// tiempo. La falta de permiso sí se avisa, porque pide una acción distinta
  /// —ir a los ajustes del sistema— y sin el aviso el botón parecería roto.
  Future<void> _chooseFile() async {
    final l10n = AppLocalizations.of(context)!;

    try {
      final chosen = await ref.read(fileChooserProvider).pickOne();
      if (chosen == null || !mounted) return;

      setState(() => _file = chosen);
    } on FileAccessDeniedException {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.captureFileAccessDenied)));
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final file = _file;

    if (file == null && _inputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.captureEmptyError)));
      return;
    }

    final notifier = ref.read(captureNotifierProvider.notifier);
    final saved = file != null
        ? await notifier.captureFile(
            file: file,
            title: _titleController.text,
            note: _noteController.text,
          )
        : await notifier.capture(
            rawInput: _inputController.text,
            title: _titleController.text,
            note: _noteController.text,
          );

    if (!mounted || !saved) return;

    // Al volver, el elemento ya está en la lista: la biblioteca escucha los
    // cambios de la base y se actualiza sola.
    //
    // No se cierra con un `pop` a secas porque no siempre hay algo que
    // cerrar. A esta pantalla se llega apilándola sobre la biblioteca, pero
    // en web también se puede llegar escribiendo la dirección: ahí la pila
    // está vacía y `pop` revienta con "There is nothing to pop" justo
    // después de haber guardado bien. En ese caso se va a la biblioteca, que
    // es adonde el usuario quería llegar de todos modos.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.library);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = ref.watch(captureNotifierProvider);

    ref.listen<CaptureState>(captureNotifierProvider, (previous, next) {
      if (next case CaptureFailed(:final failure)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(failure.localizedMessage(l10n))),
          );
      }
    });

    final detected = _detectedKind;
    final file = _file;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.captureTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TextField(
                  controller: _inputController,
                  // El foco automático solo cuando se va a escribir: con un
                  // archivo ya elegido, abrir el teclado sobre un campo
                  // desactivado tapa media pantalla para nada.
                  autofocus: file == null,
                  enabled: file == null,
                  minLines: 5,
                  maxLines: 12,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: file == null
                        ? l10n.captureHint
                        : l10n.captureFileBlocksText,
                  ),
                ),
                const SizedBox(height: 12),
                // Alto reservado aunque no haya nada que decir, para que el
                // formulario no salte al empezar a escribir.
                SizedBox(
                  height: 24,
                  child: detected == null || file != null
                      ? null
                      : Row(
                          children: [
                            Icon(
                              detected.icon,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.captureWillSaveAs(detected.label(l10n)),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                if (file == null)
                  OutlinedButton.icon(
                    onPressed: _chooseFile,
                    icon: const Icon(Icons.attach_file),
                    label: Text(l10n.captureChooseFile),
                  )
                else
                  _ChosenFileCard(
                    file: file,
                    onRemove: () => setState(() => _file = null),
                  ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: l10n.captureOptionalTitleLabel,
                  controller: _titleController,
                  validator: (_) => null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: l10n.captureOptionalNoteLabel,
                  controller: _noteController,
                  validator: (_) => null,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: l10n.captureAction,
                  isLoading: state is CaptureSaving,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se ve cuando ya hay un archivo elegido.
///
/// Muestra el nombre, de qué formato es y cuánto pesa. Lo del formato no es
/// decoración: es el aviso temprano de que un `.pages` o un `.zip` se va a
/// guardar pero no va a dar texto, y de que un `.docx` renombrado a `.txt`
/// igual se reconoció bien.
class _ChosenFileCard extends StatelessWidget {
  const _ChosenFileCard({required this.file, required this.onRemove});

  final CapturedFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final format = file.format;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(format.sourceKind.icon),
        title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          l10n.captureFileSize(
            formatFileSize(file.sizeInBytes),
            describeFormat(format),
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.captureFileRemove,
          onPressed: onRemove,
        ),
      ),
    );
  }
}

/// El tamaño de un archivo, en la unidad que le sirve a una persona.
///
/// Nadie lee "3.613.707 bytes". Se usan potencias de 1024 —que es como miden
/// los sistemas de archivos— y un solo decimal a partir de los megabytes:
/// más precisión no cambia ninguna decisión.
String formatFileSize(int bytes) {
  const unidades = ['B', 'kB', 'MB', 'GB'];

  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < unidades.length - 1) {
    value /= 1024;
    unit++;
  }

  // Los bytes y los kilobytes sin decimales: "512 B" y "40 kB" se leen mejor
  // que "512,0 B".
  final rounded = unit >= 2
      ? value.toStringAsFixed(1)
      : value.round().toString();
  return '$rounded ${unidades[unit]}';
}
