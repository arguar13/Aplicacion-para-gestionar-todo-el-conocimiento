import 'dart:async';
import 'dart:io';

/// Solo internet, nunca la red de la casa (F30).
///
/// Bajar lo que una página enlaza es pedir direcciones que eligió quien
/// escribió la página. Una que diga `http://192.168.0.1/…` o
/// `http://localhost:8080/…` haría que el teléfono le pida algo al router,
/// a la impresora o a un servicio del mismo teléfono —con la sesión del
/// usuario adentro de su red— y guarde la respuesta (lo que se conoce como
/// SSRF). Por eso las bajadas de lo enlazado solo se conectan a direcciones
/// públicas.
///
/// El control se hace **al conectar**, sobre la dirección IP a la que de
/// verdad se va a conectar, y no mirando el nombre: un nombre público puede
/// resolver a una IP privada, y una redirección puede llevar a cualquier
/// lado. Como cada conexión —también la de cada redirección— pasa por
/// [publicOnlyConnectionFactory], lo que no sea público no llega a abrirse.
/// Y se conecta a la IP que se comprobó, no al nombre otra vez: así un DNS
/// que contesta una cosa al preguntar y otra al conectar no la saltea.
class PrivateNetworkException implements Exception {
  const PrivateNetworkException(this.host);

  final String host;

  @override
  String toString() =>
      'No se baja nada de la red local ni del propio teléfono: $host.';
}

/// Si [address] es de internet: no del propio equipo, ni de una red privada,
/// ni de las reservadas para otra cosa.
bool isPublicAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) return _isPublicV4(bytes);
  if (address.type != InternetAddressType.IPv6) return false;

  // Una IPv4 escrita como IPv6 (::ffff:a.b.c.d) es esa IPv4.
  final mappedPrefix = List<int>.filled(10, 0) + [0xff, 0xff];
  if (_startsWith(bytes, mappedPrefix)) return _isPublicV4(bytes.sublist(12));

  if (bytes.every((b) => b == 0)) return false; // ::
  if (_startsWith(bytes, List<int>.filled(15, 0) + [1])) return false; // ::1
  final first = bytes[0];
  final second = bytes[1];
  if (first == 0xff) return false; // multidifusión
  if (first == 0xfe && (second & 0xc0) == 0x80) return false; // fe80::/10
  if ((first & 0xfe) == 0xfc) return false; // fc00::/7, local única
  if (first == 0x20 && second == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8) {
    return false; // 2001:db8::/32, documentación
  }
  // 64:ff9b::/96 traduce a IPv4: vale lo que valga la IPv4 de adentro.
  if (_startsWith(bytes, const [0, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0])) {
    return _isPublicV4(bytes.sublist(12));
  }
  return true;
}

bool _isPublicV4(List<int> b) {
  final a = b[0];
  final c = b[1];
  if (a == 0) return false; // 0.0.0.0/8
  if (a == 10) return false; // privada
  if (a == 127) return false; // el propio equipo
  if (a == 100 && c >= 64 && c <= 127) return false; // 100.64/10, CGNAT
  if (a == 169 && c == 254) return false; // enlace local
  if (a == 172 && c >= 16 && c <= 31) return false; // privada
  if (a == 192 && c == 168) return false; // privada
  if (a == 192 && c == 0 && (b[2] == 0 || b[2] == 2)) return false;
  if (a == 198 && (c == 18 || c == 19)) return false; // pruebas de red
  if (a == 198 && c == 51 && b[2] == 100) return false; // documentación
  if (a == 203 && c == 0 && b[2] == 113) return false; // documentación
  if (a >= 224) return false; // multidifusión y reservadas
  return true;
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// Resuelve [host] y devuelve sus direcciones si **todas** son públicas.
///
/// Todas, no alguna: un nombre que resuelve a una pública y a una privada
/// es justamente el truco para que la comprobación mire una y la conexión
/// use la otra.
///
/// [isAllowed] es para las pruebas, que necesitan un servidor "público" en
/// el propio equipo; la app usa siempre [isPublicAddress].
Future<List<InternetAddress>> resolvePublic(
  String host, {
  Future<List<InternetAddress>> Function(String host)? lookup,
  bool Function(InternetAddress address) isAllowed = isPublicAddress,
}) async {
  final literal = InternetAddress.tryParse(
    host.replaceAll(RegExp(r'^\[|\]$'), ''),
  );
  final addresses = literal != null
      ? [literal]
      : await (lookup ?? InternetAddress.lookup)(host);
  if (addresses.isEmpty || !addresses.every(isAllowed)) {
    throw PrivateNetworkException(host);
  }
  return addresses;
}

/// Un `connectionFactory` de [HttpClient] que solo abre conexiones a
/// direcciones públicas ([isPublicAddress]), a la IP ya comprobada y, en
/// https, con el certificado verificado contra el nombre del servidor.
///
/// Sin proxy: el cliente que lo usa lleva `findProxy` en `DIRECT` —ver
/// [createPublicOnlyHttpClient]—, porque a través de un proxy la IP a la que
/// se conecta es la del proxy y el control no tendría sentido.
Future<ConnectionTask<Socket>> publicOnlyConnectionFactory(
  Uri url,
  String? proxyHost,
  int? proxyPort, {
  Future<List<InternetAddress>> Function(String host)? lookup,
  bool Function(InternetAddress address) isAllowed = isPublicAddress,
}) async {
  final addresses = await resolvePublic(
    url.host,
    lookup: lookup,
    isAllowed: isAllowed,
  );
  final port = url.hasPort ? url.port : (url.scheme == 'https' ? 443 : 80);
  final task = await Socket.startConnect(addresses.first, port);
  if (url.scheme != 'https') return task;

  final secured = task.socket.then(
    (socket) => SecureSocket.secure(socket, host: url.host),
  );
  return ConnectionTask.fromSocket(secured, task.cancel);
}

/// Un [HttpClient] que solo se conecta a internet: ver
/// [publicOnlyConnectionFactory].
HttpClient createPublicOnlyHttpClient({
  Future<List<InternetAddress>> Function(String host)? lookup,
  bool Function(InternetAddress address) isAllowed = isPublicAddress,
}) => HttpClient()
  ..findProxy = ((_) => 'DIRECT')
  ..connectionFactory = (url, proxyHost, proxyPort) =>
      publicOnlyConnectionFactory(
        url,
        proxyHost,
        proxyPort,
        lookup: lookup,
        isAllowed: isAllowed,
      );
