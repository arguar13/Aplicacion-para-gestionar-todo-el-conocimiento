import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/custom_text_field.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/vault/domain/entities/pin_policy.dart';
import 'package:sinapsis/features/vault/presentation/providers/create_vault_notifier.dart';
import 'package:sinapsis/features/vault/presentation/providers/create_vault_state.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Primer arranque: acá se elige la clave que protege la bóveda.
///
/// El texto explicativo no es decorativo. Esta app guarda todo en el
/// dispositivo y la clave no viaja a ningún servidor, así que no existe un
/// "olvidé mi contraseña": nadie —ni el desarrollador— puede recuperarla.
/// Decirlo antes de que la elija es la diferencia entre una decisión
/// informada y una pérdida silenciosa de todo lo guardado.
class CreateVaultScreen extends ConsumerStatefulWidget {
  const CreateVaultScreen({super.key});

  @override
  ConsumerState<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends ConsumerState<CreateVaultScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmationController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  String? _validatePin(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final pin = value ?? '';

    if (pin.isEmpty) return l10n.vaultPasscodeEmptyError;
    if (!PinPolicy.isValid(pin)) {
      return l10n.vaultPasscodeTooShortError(PinPolicy.minLength);
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if ((value ?? '') != _pinController.text) {
      return AppLocalizations.of(context)!.vaultPasscodeMismatchError;
    }
    return null;
  }

  void _submit() {
    // La misma regla se comprueba de nuevo en `CreateVaultUseCase`. No es
    // duplicación por descuido: acá sirve para señalar el campo exacto
    // mientras se escribe, y allá para que la regla valga aunque la
    // llamada venga de otro lado.
    if (_formKey.currentState?.validate() != true) return;

    ref
        .read(createVaultNotifierProvider.notifier)
        .create(
          pin: _pinController.text,
          confirmation: _confirmationController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // El éxito no se maneja acá: al quedar creada, la bóveda pasa a
    // `unlocked` y el router se lleva al usuario solo. Esta pantalla solo
    // reacciona al fallo, que es lo único que le concierne.
    ref.listen<CreateVaultState>(createVaultNotifierProvider, (previous, next) {
      if (next case CreateVaultFailed(:final failure)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(failure.localizedMessage(l10n))),
          );
      }
    });

    final isCreating =
        ref.watch(createVaultNotifierProvider) is CreateVaultCreating;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.vaultCreateTitle,
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.vaultCreateSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    CustomTextField(
                      label: l10n.vaultPasscodeLabel,
                      controller: _pinController,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      validator: _validatePin,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: l10n.vaultConfirmPasscodeLabel,
                      controller: _confirmationController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      validator: _validateConfirmation,
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: l10n.vaultCreateAction,
                      isLoading: isCreating,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
