import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Traduce un [Failure] al mensaje que ve el usuario.
///
/// Existe por dos razones.
///
/// La primera es que este `switch` estaba copiado, idéntico, en tres
/// notifiers distintos. Cada vez que se agregara un caso a [Failure] había
/// que acordarse de los tres; el analizador avisaría (el switch es
/// exhaustivo sobre una clase sellada), pero el arreglo seguiría siendo
/// triple.
///
/// La segunda importa más: las versiones copiadas devolvían
/// `failure.message`, que es texto escrito en español dentro de las capas
/// `data` y `domain`. Eso hacía que la app se viera bilingüe pero no lo
/// fuera — con el idioma en inglés, cualquier error de red seguía saliendo
/// en español. El mensaje del dominio queda entonces para lo que sirve de
/// verdad, que es diagnóstico: registros y telemetría.
extension FailureLocalization on Failure {
  String localizedMessage(AppLocalizations l10n) {
    return switch (this) {
      NetworkFailure() => l10n.globalErrorNetwork,
      UnauthorizedFailure() => l10n.globalErrorUnauthorized,
      ServerFailure() => l10n.globalErrorServer,
      ValidationFailure() => l10n.globalErrorValidation,
      CacheFailure() => l10n.globalErrorStorage,
      FileTooLargeFailure(:final maxBytes) => l10n.globalErrorFileTooLarge(
        _megabytes(maxBytes),
      ),
      UnexpectedFailure() => l10n.globalErrorUnexpected,
    };
  }
}

/// El límite en megabytes, para decírselo a alguien que no piensa en bytes.
String _megabytes(int bytes) => (bytes / (1024 * 1024)).round().toString();
