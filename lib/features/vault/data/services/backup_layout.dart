/// Cómo está armado el `.zip` de una copia de la bóveda: lo comparten quien lo
/// arma, quien lo restaura y quien lo fusiona, para que no puedan discrepar.
///
/// El nombre de la base adentro coincide a propósito con el que usa
/// `AppDatabase.open()` (`sinapsis.sqlite`): así el mismo `.zip` sirve para
/// llevar la bóveda de Android a Windows o al revés.
const kBackupDatabaseEntryName = 'sinapsis.sqlite';

/// La carpeta de los archivos originales, dentro del `.zip` y dentro de la
/// carpeta de documentos de la app.
const kBackupOriginalsFolder = 'originales';
