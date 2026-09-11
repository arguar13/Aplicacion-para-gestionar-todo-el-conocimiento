/// Reglas que tiene que cumplir un PIN para ser aceptado, y qué pasa
/// cuando alguien se equivoca varias veces seguidas.
///
/// Vive en `domain` y no en la pantalla porque son reglas del producto, no
/// de la interfaz: la misma política tiene que aplicar venga el PIN de un
/// formulario, de una prueba automatizada o de cualquier entrada futura.
abstract final class PinPolicy {
  /// Seis dígitos. Cuatro (lo habitual en un teléfono) da diez mil
  /// combinaciones, que con el límite de intentos de más abajo alcanzaría;
  /// pero seis cuesta lo mismo de escribir y multiplica por cien el espacio
  /// de búsqueda para el caso en que alguien se lleve el credencial del
  /// almacén del sistema.
  static const minLength = 6;

  /// Sin tope real: el usuario puede usar una clave larga si prefiere. El
  /// límite existe solo para que un pegado accidental de medio documento no
  /// termine derivándose.
  static const maxLength = 128;

  /// Intentos fallidos seguidos antes de imponer una espera.
  static const maxAttemptsBeforeLockout = 5;

  /// Esperas sucesivas, una por cada tanda de intentos fallidos. Crecen
  /// rápido: probar el millón de combinaciones de un PIN de seis dígitos a
  /// través de la interfaz de la app pasa a llevar siglos, que es
  /// exactamente el punto. La última se repite indefinidamente.
  static const lockoutDurations = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
    Duration(hours: 1),
  ];

  /// Cuánto hay que esperar después de la [round]-ésima tanda de fallos
  /// (empezando en cero). Pasada la última, se queda en la más larga en vez
  /// de crecer para siempre: bloquear un dispositivo durante días no
  /// protege más y sí deja a su dueño afuera.
  static Duration lockoutFor(int round) {
    if (round < 0) return Duration.zero;
    return round < lockoutDurations.length
        ? lockoutDurations[round]
        : lockoutDurations.last;
  }

  /// Un PIN es válido si tiene la longitud mínima y no se pasa del tope.
  ///
  /// No se exige que sean solo dígitos a propósito: el campo de la
  /// interfaz ofrece teclado numérico, pero quien quiera usar una frase
  /// como clave debería poder — le da más entropía, no menos.
  static bool isValid(String pin) =>
      pin.length >= minLength && pin.length <= maxLength;
}
