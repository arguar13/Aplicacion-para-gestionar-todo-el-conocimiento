import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:sinapsis/core/network/bounded_download.dart';
import 'package:sinapsis/core/network/host_gate.dart';
import 'package:sinapsis/core/network/public_network.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/attachments/data/services/bounded_linked_file_fetcher.dart';
import 'package:sinapsis/features/attachments/data/services/zip_archive_expander.dart';
import 'package:sinapsis/features/attachments/domain/services/archive_expander.dart';
import 'package:sinapsis/features/attachments/domain/services/linked_file_fetcher.dart';

/// Fuera de la web: un [Dio] propio que solo se conecta a internet
/// (`createPublicOnlyHttpClient`), sin el interceptor de errores global —que
/// un enlace roto de una página ajena no es un error del usuario—, de a una
/// bajada por servidor y acotada.
LinkedFileFetcher? createLinkedFileFetcher({
  required FileStore files,
  required HostGate hosts,
  required Future<int?> Function() freeBytes,
  required BaseOptions options,
}) {
  final dio = Dio(options)
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: createPublicOnlyHttpClient,
    );
  return BoundedLinkedFileFetcher(
    downloader: BoundedDownloader(dio: dio, hosts: hosts, freeBytes: freeBytes),
    files: files,
  );
}

/// Fuera de la web, los `.zip` se descomprimen con zlib nativo, por tandas.
ArchiveExpander? createArchiveExpander({required FileStore files}) =>
    ZipArchiveExpander(files: files);
