import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/usecases/processing_failure_classifier.dart';

void main() {
  test('cada fallo conocido tiene su motivo', () {
    final cases = <Object, ProcessingFailureReason>{
      const WhisperModelNotReadyException():
          ProcessingFailureReason.transcriptionModelMissing,
      const VideoUnavailableException('abc'):
          ProcessingFailureReason.unavailable,
      NoArticleFoundException(Uri.parse('https://ejemplo.org')):
          ProcessingFailureReason.noArticle,
      const UnreadableDocumentException(FileFormat.pdf, 'cifrado'):
          ProcessingFailureReason.unreadableDocument,
      const MissingOriginalFileException('x/y.pdf'):
          ProcessingFailureReason.missingOriginalFile,
      TimeoutException('tardó'): ProcessingFailureReason.timedOut,
      const NetworkException(message: 'sin red'):
          ProcessingFailureReason.network,
      const DownloadBlockedException(message: '403'):
          ProcessingFailureReason.downloadBlocked,
      const ServerException(message: 'no está', statusCode: 404):
          ProcessingFailureReason.unavailable,
      const ServerException(message: 'se fue', statusCode: 410):
          ProcessingFailureReason.unavailable,
      const UnauthorizedException(message: 'prohibido'):
          ProcessingFailureReason.unavailable,
      const ServerException(message: 'caído', statusCode: 503):
          ProcessingFailureReason.network,
      StateError('roto'): ProcessingFailureReason.unknown,
    };

    for (final MapEntry(key: error, value: reason) in cases.entries) {
      expect(processingFailureReasonFor(error), reason, reason: '$error');
    }
  });

  test('un motivo guardado que no se reconoce se lee como desconocido', () {
    expect(ProcessingFailureReason.fromStored(null), isNull);
    expect(
      ProcessingFailureReason.fromStored('timedOut'),
      ProcessingFailureReason.timedOut,
    );
    expect(
      ProcessingFailureReason.fromStored('uno-de-una-version-nueva'),
      ProcessingFailureReason.unknown,
    );
  });
}
