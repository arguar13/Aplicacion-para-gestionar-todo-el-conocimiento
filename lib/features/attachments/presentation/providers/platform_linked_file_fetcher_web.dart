import 'package:dio/dio.dart';
import 'package:sinapsis/core/network/host_gate.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/attachments/domain/services/archive_expander.dart';
import 'package:sinapsis/features/attachments/domain/services/linked_file_fetcher.dart';

/// En la web no se baja lo que enlaza una página: el navegador no deja
/// pedirle archivos a otros sitios (CORS) ni saber a qué IP se conecta, que
/// es lo que protege de la red local. La página se guarda como hasta F29.
LinkedFileFetcher? createLinkedFileFetcher({
  required FileStore files,
  required HostGate hosts,
  required Future<int?> Function() freeBytes,
  required BaseOptions options,
}) => null;

/// En la web no se baja nada, así que no hay `.zip` que abrir.
ArchiveExpander? createArchiveExpander({required FileStore files}) => null;
