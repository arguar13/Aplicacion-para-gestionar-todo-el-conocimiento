import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/custom_text_field.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
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
        .resolve(CaptureRequest(rawInput: input))
        .producesKind;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;

    if (_inputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.captureEmptyError)));
      return;
    }

    final saved = await ref
        .read(captureNotifierProvider.notifier)
        .capture(
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
                  autofocus: true,
                  minLines: 5,
                  maxLines: 12,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(hintText: l10n.captureHint),
                ),
                const SizedBox(height: 12),
                // Alto reservado aunque no haya nada que decir, para que el
                // formulario no salte al empezar a escribir.
                SizedBox(
                  height: 24,
                  child: detected == null
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
