import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue_state.dart';
import 'package:sinapsis/features/vault/data/datasources/vault_local_data_source.dart';
import 'package:sinapsis/features/vault/data/models/lockout_state.dart';
import 'package:sinapsis/features/vault/domain/services/pin_hasher.dart';

/// Dobles compartidos por los tests que necesitan una bóveda sin tocar el
/// sistema operativo.
///
/// Viven acá y no repetidos en cada archivo porque cuatro copias del mismo
/// fake divergen: una se actualiza al cambiar la interfaz y las otras tres
/// se arreglan a los tumbos cuando alguien las pisa.

/// [VaultLocalDataSource] en memoria.
///
/// `flutter_secure_storage` usa canales de plataforma que no existen en un
/// widget test, así que cualquier prueba que toque la bóveda necesita algo
/// como esto.
class FakeVaultLocalDataSource implements VaultLocalDataSource {
  FakeVaultLocalDataSource({
    String? credential,
    LockoutState? lockout,
    String? openBoot,
    this.delay = Duration.zero,
  }) : _credential = credential,
       _lockout = lockout ?? LockoutState.initial,
       _openBoot = openBoot;

  /// Una bóveda ya creada, cuyo PIN es [pin] según [FakePinHasher].
  factory FakeVaultLocalDataSource.withPin(
    String pin, {
    String? openBoot,
    Duration delay = Duration.zero,
  }) => FakeVaultLocalDataSource(
    credential: FakePinHasher.encode(pin),
    openBoot: openBoot,
    delay: delay,
  );

  /// Cuánto tarda cada lectura.
  ///
  /// Por defecto, nada: casi ningún test necesita simular lentitud. Sirve
  /// para los que prueban qué se ve *durante* la espera — sin una demora
  /// real, la lectura resuelve antes del primer frame y el estado
  /// intermedio no llega a existir, aunque en un dispositivo de verdad sea
  /// perfectamente visible.
  final Duration delay;

  String? _credential;
  LockoutState _lockout;
  String? _openBoot;
  var _credentialWrites = 0;

  /// Para poder comprobar en un test qué quedó guardado.
  String? get credential => _credential;
  LockoutState get lockout => _lockout;

  /// El encendido en que se abrió la bóveda, o `null` si está cerrada.
  String? get openBoot => _openBoot;

  /// Cuántas veces se escribió el credencial.
  ///
  /// Permite distinguir "se volvió a derivar" de "no se tocó" en casos
  /// donde el valor resultante sería idéntico y comparar strings no
  /// alcanzaría.
  int get credentialWrites => _credentialWrites;

  @override
  Future<String?> readCredential() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return _credential;
  }

  @override
  Future<void> writeCredential(String credential) async {
    _credentialWrites++;
    _credential = credential;
  }

  @override
  Future<LockoutState> readLockout() async => _lockout;

  @override
  Future<void> writeLockout(LockoutState state) async => _lockout = state;

  @override
  Future<String?> readOpenBoot() async => _openBoot;

  @override
  Future<void> writeOpenBoot(String boot) async => _openBoot = boot;

  @override
  Future<void> clearOpenBoot() async => _openBoot = null;
}

/// [PinHasher] que no deriva nada: guarda el PIN tal cual, con un prefijo.
///
/// Es exactamente lo que jamás haría la implementación real, y acá es lo
/// correcto: derivar de verdad cuesta cerca de un segundo por llamada —es
/// el punto de un KDF—, y un test de interfaz que desbloquea tres veces
/// pasaría más tiempo derivando que probando. La derivación real tiene sus
/// propios tests en `pbkdf2_pin_hasher_test.dart`, que es donde importa.
class FakePinHasher implements PinHasher {
  FakePinHasher({this.forcedVerification});

  static const _prefix = 'fake-hash:';

  /// Para simular un resultado concreto sin tener que construir el
  /// credencial que lo produciría — por ejemplo
  /// [PinVerification.correctNeedsRehash].
  final PinVerification? forcedVerification;

  static String encode(String pin) => '$_prefix$pin';

  @override
  Future<String> hash(String pin) async => encode(pin);

  @override
  Future<PinVerification> verify({
    required String pin,
    required String encoded,
  }) async {
    if (forcedVerification != null) return forcedVerification!;

    return encoded == encode(pin)
        ? PinVerification.correct
        : PinVerification.incorrect;
  }
}

/// [PinHasher] que siempre falla al leer el credencial guardado.
///
/// Simula una bóveda dañada: el caso en que el usuario escribe su clave
/// correcta y aun así no puede entrar, que la app tiene que saber
/// distinguir de una clave equivocada.
class CorruptedPinHasher implements PinHasher {
  const CorruptedPinHasher();

  @override
  Future<String> hash(String pin) async => 'irrelevante';

  @override
  Future<PinVerification> verify({
    required String pin,
    required String encoded,
  }) async {
    throw const CorruptedCredentialException('credencial de prueba dañado');
  }
}

/// Cola de procesamiento que no procesa nada.
///
/// La usan los tests de la biblioteca y del detalle. Sin ella, abrir la
/// biblioteca en un test dispararía el procesamiento real de lo pendiente, y
/// entonces una prueba sobre cómo se ve un elemento en espera dependería de
/// si la cola llegó a tocarlo antes de la aserción. Un test de la lista tiene
/// que probar la lista.
///
/// Recibe las dependencias reales y no las usa: así el doble no puede
/// desincronizarse del constructor de la clase base. Los tests de la cola
/// usan la de verdad, con clientes de red falsos.
class InertProcessingQueue extends ProcessingQueueNotifier {
  InertProcessingQueue({
    required super.processItem,
    required super.processingStates,
    required super.logger,
  });

  /// Lo que se pidió encolar. Permite comprobar que una pantalla encola lo
  /// que corresponde, sin que nada se procese de verdad.
  final enqueued = <String>[];

  /// Cuántas veces se pidió retomar lo pendiente.
  int pendingSweeps = 0;

  @override
  void enqueue(String itemId) => enqueued.add(itemId);

  @override
  Future<void> resume() async => pendingSweeps++;

  /// Simula lo que publicaría la cola de verdad mientras trabaja: qué está
  /// en curso y cuánto va. Para probar la barra de avance sin procesar nada.
  // ignore: use_setters_to_change_properties
  void showProgress(Map<String, ProcessingProgress> active) =>
      state = ProcessingQueueState(active: active);
}

/// El encendido de un teléfono de prueba, siempre el mismo (ver `DeviceBoot`).
///
/// En las pruebas de Flutter la plataforma es Android, y sin esto la bóveda
/// le preguntaría su encendido al canal nativo, que en una prueba no existe.
const kTestDeviceBoot = 'arranque-de-prueba';

Future<String?> testDeviceBoot() async => kTestDeviceBoot;
