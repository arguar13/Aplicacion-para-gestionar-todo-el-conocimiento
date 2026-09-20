/// La base es de un esquema demasiado viejo para que esta versión de la app la
/// actualice.
///
/// Desde F10 la actualización más antigua que se soporta es
/// `AppDatabase.minimumUpgradableSchemaVersion`: los pasos de las versiones
/// anteriores se retiraron con sus pruebas, porque leían las tablas que F10
/// retira y no había cómo seguir probándolos. Se corta acá, antes de tocar
/// nada, y con un mensaje que dice qué hacer: fallar más adelante por una tabla
/// que no existe dejaría la bóveda a medio migrar.
class SchemaTooOldException implements Exception {
  const SchemaTooOldException({required this.from, required this.minimum});

  /// La versión de esquema de la base que se intentó abrir.
  final int from;

  /// La más antigua que esta versión de la app sabe actualizar.
  final int minimum;

  String get message =>
      'Esta versión de Sinapsis no puede actualizar una bóveda con el esquema '
      'v$from: solo actualiza desde el v$minimum en adelante. Abrila primero '
      'con una versión de Sinapsis que tenga el esquema v$minimum (la de F9) '
      'para que se actualice, y después con esta. No se modificó nada.';

  @override
  String toString() => 'SchemaTooOldException: $message';
}
