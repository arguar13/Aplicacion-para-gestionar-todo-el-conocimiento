import 'dart:async';

import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/transform/domain/clients/social_post_client.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// Qué motivo se guarda para [error], lo que lanzó un transformador.
///
/// Solo reconoce tipos del dominio —y [TimeoutException], de `dart:async`—:
/// cada cliente de red traduce sus propios fallos a esos tipos antes de que
/// lleguen acá, así este criterio no depende de ningún paquete de afuera.
ProcessingFailureReason processingFailureReasonFor(
  Object error,
) => switch (error) {
  WhisperModelNotReadyException() =>
    ProcessingFailureReason.transcriptionModelMissing,
  VideoUnavailableException() ||
  SocialPostUnavailableException() => ProcessingFailureReason.unavailable,
  NoArticleFoundException() => ProcessingFailureReason.noArticle,
  UnreadableDocumentException() => ProcessingFailureReason.unreadableDocument,
  MissingOriginalFileException() => ProcessingFailureReason.missingOriginalFile,
  TimeoutException() => ProcessingFailureReason.timedOut,
  NetworkException() => ProcessingFailureReason.network,
  _ => ProcessingFailureReason.unknown,
};
