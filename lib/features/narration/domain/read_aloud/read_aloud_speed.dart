/// La velocidad más lenta y la más rápida del lector en voz alta (F47, paso
/// 2, decisión H): de 0,5× a 3×, sin candados.
const readAloudMinSpeed = 0.5;
const readAloudMaxSpeed = 3.0;

/// El paso de la regla de la velocidad: una décima, como «1,2×».
const readAloudSpeedStep = 0.1;

/// Las velocidades a un toque, debajo de la regla.
const readAloudSpeedPresets = [1.0, 1.2, 1.5, 2.0, 3.0];

/// [speed] llevada a la décima más cercana y dentro de los límites del
/// lector.
///
/// Cuenta en décimas enteras y divide al final: `12 * 0.1` es
/// `1.2000000000000002`, y una velocidad así no sería igual a la de su atajo
/// ni se guardaría como la que se eligió.
double snapReadAloudSpeed(double speed) {
  final tenths = (speed * 10).round().clamp(
    (readAloudMinSpeed * 10).round(),
    (readAloudMaxSpeed * 10).round(),
  );
  return tenths / 10;
}
