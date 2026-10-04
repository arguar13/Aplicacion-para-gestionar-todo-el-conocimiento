import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/error/global_error_bus.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/network/interceptors/error_interceptor.dart';
import 'package:sinapsis/core/network/interceptors/logging_interceptor.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';

/// Cliente HTTP de la app.
///
/// Cambió de propósito con el paso a funcionar sin servidor. Antes era el
/// cliente de *nuestra* API: tenía una `baseUrl` fija, mandaba un token en
/// cada request y cerraba la sesión ante un 401. Sinapsis ya no tiene API
/// propia —todo se procesa y se guarda en el dispositivo—, así que lo que
/// queda es un cliente para traer contenido de terceros: la página que el
/// usuario quiere archivar, los subtítulos de un video, la imagen de una
/// publicación.
///
/// De ahí las dos diferencias con su versión anterior:
///
/// - **Sin `baseUrl`.** Cada descarga apunta a un host distinto y usa la
///   URL absoluta de su fuente. Una base fija no significaría nada acá.
/// - **Sin cabeceras de autenticación.** No hay sesión que acreditar. Los
///   interceptores que inyectaban el token y reaccionaban al 401 se
///   eliminaron junto con el backend; dejarlos habría sido dejar
///   maquinaria que no protege nada.
///
/// Quedan los dos que siguen teniendo sentido: el registro de cada
/// petición y el manejo transversal de errores.
final dioProvider = Provider<Dio>((ref) {
  final logger = ref.watch(appLoggerProvider);

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      // Más generoso que el de conexión: una página con muchos recursos o
      // una pista de subtítulos larga tarda en llegar, y cortarla a los 15
      // segundos convertiría una descarga lenta en un error.
      receiveTimeout: const Duration(seconds: 60),
      // Sin `Content-Type: application/json` por defecto: lo que se trae
      // es HTML, XML, imágenes o texto plano, según la fuente.
      headers: const {
        // Algunos sitios responden distinto —o directamente rechazan— a un
        // cliente sin User-Agent. Se identifica de forma honesta en vez de
        // hacerse pasar por un navegador.
        'User-Agent': 'Sinapsis/0.1 (+lector de contenido personal)',
      },
    ),
  );

  dio.interceptors.addAll([
    NetworkLoggingInterceptor(logger: logger),
    GlobalErrorInterceptor(
      logger: logger,
      telemetry: ref.watch(telemetryServiceProvider),
      onDomainError: (exception) =>
          ref.read(globalErrorNotifierProvider.notifier).report(exception),
    ),
  ]);

  return dio;
});

/// Cliente HTTP para los recursos que se incrustan al archivar una página
/// completa: imágenes, hojas de estilo, fuentes.
///
/// Deliberadamente **sin** [GlobalErrorInterceptor]. Archivar una sola
/// página pide decenas de estos recursos, y que uno falle —un CDN caído, una
/// imagen bloqueada por CORS— es lo esperado, no un problema del usuario: el
/// archivado sigue igual, sin ese recurso incrustado. Con el interceptor
/// global cada uno de esos fallos rutinarios dispararía el aviso de error de
/// toda la app, sin que hubiera ninguna acción que el usuario pudiera tomar
/// al respecto. El registro de peticiones sí se mantiene, para poder
/// diagnosticar sin generar ruido visible.
final resourceFetchDioProvider = Provider<Dio>((ref) {
  final logger = ref.watch(appLoggerProvider);

  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'User-Agent': 'Sinapsis/0.1 (+lector de contenido personal)',
      },
    ),
  )..interceptors.add(NetworkLoggingInterceptor(logger: logger));
});

/// Los límites de tiempo de las descargas de modelos —cientos de megas a
/// varios gigas—: que una conexión lenta pero viva siga, y que una muerta
/// se corte y se retome.
///
/// - `connectTimeout`, 15 s: lo que tarda en abrirse la conexión.
/// - `receiveTimeout`, 30 s: en dio 5.11 cubre solo la espera de las
///   **cabeceras** de la respuesta (`io_adapter.dart`, el `timeout` sobre
///   `request.close()`), no el cuerpo; por eso no corta una descarga lenta
///   de horas. Sin él, un servidor que acepta la conexión y no contesta
///   dejaba la descarga esperando para siempre.
/// - El cuerpo lo vigila `ResumableDownload.stallTimeout`: un minuto sin
///   recibir un solo byte.
BaseOptions modelDownloadBaseOptions() => BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 30),
  headers: const {'User-Agent': 'Sinapsis/0.1 (+lector de contenido personal)'},
);
