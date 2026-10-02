/// Excepciones lanzadas por `data sources` (red, caché). Los repositorios
/// las capturan y las traducen a un `Failure` antes de llegar a `domain`.
class ServerException implements Exception {
  const ServerException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;
}

class NetworkException implements Exception {
  const NetworkException({required this.message});

  final String message;
}

/// El servidor de un video no deja bajar su audio desde esta app: YouTube
/// responde "prohibido" a lo que no es su propia app (F24). Reintentar no lo
/// cambia.
class DownloadBlockedException implements Exception {
  const DownloadBlockedException({required this.message});

  final String message;

  @override
  String toString() => 'Bajada bloqueada: $message';
}

class UnauthorizedException implements Exception {
  const UnauthorizedException({required this.message});

  final String message;
}

class CacheException implements Exception {
  const CacheException({required this.message});

  final String message;
}
