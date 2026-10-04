import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/bounded_download.dart';
import 'package:sinapsis/core/network/host_gate.dart';
import 'package:sinapsis/features/attachments/data/services/bounded_linked_file_fetcher.dart';

import '../../../../support/in_memory_file_store.dart';

class _OneFile implements HttpClientAdapter {
  _OneFile(this.bytes, this.headers);

  final List<int> bytes;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(
    Stream.value(Uint8List.fromList(bytes)),
    200,
    headers: headers,
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  group('fileNameFor', () {
    test('el nombre de la página, con la extensión del archivo', () {
      expect(
        fileNameFor(preferred: 'Informe anual 2026', offered: 'doc_8812.pdf'),
        'Informe anual 2026.pdf',
      );
      expect(
        fileNameFor(preferred: 'Roma vs. Cartago', offered: 'x.pdf'),
        'Roma vs. Cartago.pdf',
      );
      expect(fileNameFor(preferred: 'mapa.PNG', offered: 'a.png'), 'mapa.PNG');
    });

    test('sin nombre de la página, el del servidor', () {
      expect(fileNameFor(offered: 'doc.pdf'), 'doc.pdf');
      expect(fileNameFor(preferred: '  ', offered: 'doc.pdf'), 'doc.pdf');
    });
  });

  test('baja y guarda en la subcarpeta, sin pisar', () async {
    final files = InMemoryFileStore();
    final fetcher = BoundedLinkedFileFetcher(
      downloader: BoundedDownloader(
        dio: Dio()
          ..httpClientAdapter = _OneFile(
            [1, 2, 3],
            {
              'content-type': ['application/pdf'],
            },
          ),
        hosts: HostGate(gap: Duration.zero),
        freeBytes: () async => null,
      ),
      files: files,
    );
    final url = Uri.parse('https://x.org/doc_8812.pdf');

    final first = await fetcher.fetch(
      url,
      storeId: 'src',
      folder: 'contenido',
      maxBytes: 10,
      preferredName: 'Informe',
    );
    final second = await fetcher.fetch(
      url,
      storeId: 'src',
      folder: 'contenido',
      maxBytes: 10,
      preferredName: 'Informe',
    );

    expect(first.relativePath, 'originales/src/contenido/Informe.pdf');
    expect(second.relativePath, 'originales/src/contenido/Informe-2.pdf');
    expect(first.contentType, 'application/pdf');
    expect(first.fileName, 'doc_8812.pdf');
    expect(await files.read(first.relativePath), [1, 2, 3]);

    await expectLater(
      fetcher.fetch(url, storeId: 'src', maxBytes: 2),
      throwsA(isA<DownloadTooLargeException>()),
    );
  });

  test('cancelar corta la bajada', () async {
    final fetcher = BoundedLinkedFileFetcher(
      downloader: BoundedDownloader(
        dio: Dio()..httpClientAdapter = const _Hanging(),
        hosts: HostGate(gap: Duration.zero),
        freeBytes: () async => null,
      ),
      files: InMemoryFileStore(),
    );
    final cancel = Completer<void>();

    final fetching = fetcher.fetch(
      Uri.parse('https://x.org/eterno.mp4'),
      storeId: 'src',
      maxBytes: 100,
      whenCancelled: cancel.future,
    );
    cancel.complete();

    await expectLater(fetching, throwsA(isA<DioException>()));
  });
}

/// Un servidor que no contesta nunca: solo se sale cancelando.
class _Hanging implements HttpClientAdapter {
  const _Hanging();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await cancelFuture;
    throw DioException.requestCancelled(
      requestOptions: options,
      reason: 'cancelada',
    );
  }

  @override
  void close({bool force = false}) {}
}
