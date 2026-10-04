/// El encendido actual del dispositivo, para que la bóveda pida la clave una
/// vez por encendido y no cada vez que se abre la app.
///
/// Pedido del usuario: la clave solo cuando el teléfono se apaga o se
/// reinicia, o cuando cierra la sesión a mano. Al desbloquear, la bóveda anota
/// el encendido en que se abrió; al abrir la app, si es el mismo, entra sin
/// preguntar. Apagar o reiniciar el teléfono cambia el encendido, y con eso
/// vuelve a pedirla.
///
/// Devuelve un identificador del encendido actual: el mismo mientras el
/// dispositivo no se apague ni se reinicie, y otro después. `null` donde la
/// plataforma no lo da —el escritorio, la web—: ahí no hay forma de saber si
/// la máquina se reinició, y la bóveda pide la clave cada vez que se abre la
/// app, que es el lado seguro.
typedef DeviceBoot = Future<String?> Function();

/// Para las plataformas que no dicen nada de su encendido.
Future<String?> unknownDeviceBoot() async => null;
