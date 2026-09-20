import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// El identificador de dispositivo de lo escrito antes de F11, cuando
/// `KnowledgeEntries.deviceId` era un texto fijo (`kMirrorDeviceIdPlaceholder`)
/// y nada sabía desde qué equipo se había cambiado algo.
///
/// Una fusión trata lo que viene de un dispositivo así como de origen
/// desconocido: no puede haber conflicto con alguien que no se sabe quién es, y
/// gana lo más reciente.
const kLegacyDeviceId = 'legacy';

/// El identificador que usa una `AppDatabase` que nadie configuró: las bases en
/// memoria de las pruebas, y la copia de otra bóveda que una fusión abre solo
/// para leerla. La app real nunca lo usa: `AppDatabase.open` exige el suyo.
const kUnspecifiedDeviceId = 'unspecified';

/// Quién es ESTA instalación de la app.
///
/// Un UUID que se crea la primera vez y no cambia: lo lleva cada campo que este
/// dispositivo modifica (`field_version.device_id`), y es lo que permite a una
/// fusión saber si dos cambios al mismo campo los hizo la misma persona en el
/// mismo equipo —una edición sigue a la otra— o dos equipos distintos.
///
/// Vive en las preferencias del dispositivo y NO en la base, a propósito: una
/// copia de la bóveda lleva la base a otro equipo, y si el identificador
/// viajara con ella los dos equipos pasarían a ser «el mismo dispositivo» y
/// ningún conflicto se vería nunca. Reinstalar la app crea otro: para la fusión
/// es un dispositivo nuevo, que es lo que es.
class DeviceIdentity {
  const DeviceIdentity(this.id);

  /// Dónde se guarda en las preferencias.
  static const preferencesKey = 'sinapsis.device_id';

  final String id;

  /// El identificador guardado, o uno nuevo —que se guarda— si es la primera
  /// vez que corre la app en este dispositivo.
  static Future<DeviceIdentity> loadOrCreate(
    SharedPreferences prefs, {
    IdGenerator ids = const UuidV7Generator(),
  }) async {
    final stored = prefs.getString(preferencesKey);
    if (stored != null && stored.isNotEmpty) return DeviceIdentity(stored);

    final created = ids.next();
    await prefs.setString(preferencesKey, created);
    return DeviceIdentity(created);
  }
}

/// Si [deviceId] es el de algo escrito antes de que existieran los
/// identificadores de dispositivo.
bool isLegacyDevice(String deviceId) =>
    deviceId == kLegacyDeviceId || deviceId == kMirrorDeviceIdPlaceholder;
