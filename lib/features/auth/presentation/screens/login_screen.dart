import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/auth/presentation/providers/auth_notifier.dart';
import 'package:sinapsis/features/auth/presentation/providers/auth_state.dart';
import 'package:sinapsis/features/auth/presentation/widgets/custom_text_field.dart';
import 'package:sinapsis/features/auth/presentation/widgets/primary_button.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

final _emailRegExp = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final email = value?.trim() ?? '';
    if (email.isEmpty) return l10n.emailEmptyError;
    if (!_emailRegExp.hasMatch(email)) return l10n.emailInvalidError;
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.passwordEmptyError;
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    ref
        .read(authNotifierProvider.notifier)
        .login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // El caso de éxito no navega desde acá: en cuanto `AuthNotifier` marca
    // la sesión autenticada, el router (que escucha
    // `sessionControllerProvider`) redirige a /dashboard por su cuenta.
    // Esta pantalla solo reacciona al error, lo único que le concierne.
    ref.listen<AuthState>(authNotifierProvider, (previous, next) {
      if (next case AuthError(:final message)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final isLoading = ref.watch(authNotifierProvider) is AuthLoading;

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
                    Text(
                      l10n.loginTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    CustomTextField(
                      label: l10n.emailLabel,
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: l10n.passwordLabel,
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: l10n.loginButton,
                      isLoading: isLoading,
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
