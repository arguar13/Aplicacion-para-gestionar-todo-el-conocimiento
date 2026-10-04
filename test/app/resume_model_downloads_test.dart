import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/resume_model_downloads.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/network/model_download_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

import '../support/fake_ai_organize_queue.dart';
import '../support/fake_chat_model_manager.dart';
import '../support/fake_embedding_model_manager.dart';
import '../support/fake_system_downloads.dart';
import '../support/fake_whisper_model_manager.dart';
import '../support/silent_logger.dart';

/// Un gestor al que no se le puede preguntar: el canal con el sistema falló.
class _UnreachableChatModelManager extends FakeChatModelManager {
  @override
  Future<bool> isDownloading() async =>
      throw PlatformException(code: 'system_downloads');
}

/// Al abrir la app (F29): las descargas de los modelos que siguieron con la
/// app cerrada vuelven a verse, sin que se pida ninguna nueva.
void main() {
  late FakeChatModelManager chat;
  late FakeEmbeddingModelManager embedding;
  late FakeWhisperModelManager whisper;
  late SharedPreferences prefs;
  late FakeAiOrganizeQueue queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    queue = FakeAiOrganizeQueue();
    chat = FakeChatModelManager();
    embedding = FakeEmbeddingModelManager();
    whisper = FakeWhisperModelManager();
  });

  ProviderContainer containerWith({required bool systemDownloads}) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appLoggerProvider.overrideWithValue(const SilentLogger()),
        systemDownloadsProvider.overrideWithValue(
          systemDownloads ? FakeSystemDownloads(Directory.systemTemp) : null,
        ),
        chatModelManagerProvider.overrideWithValue(chat),
        embeddingModelManagerProvider.overrideWithValue(embedding),
        whisperModelManagerProvider.overrideWithValue(whisper),
        aiOrganizeQueueProvider.overrideWithValue(queue),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('se engancha a las que siguen y deja quietas las demás', () async {
    chat.downloading = true;
    whisper.downloading = true;
    final container = containerWith(systemDownloads: true);

    await resumeModelDownloads(container.read);

    expect(
      container.read(chatModelDownloadProvider),
      isA<ModelDownloadRunning>(),
    );
    expect(
      container.read(transcriptionModelDownloadProvider),
      isA<ModelDownloadRunning>(),
    );
    expect(
      container.read(embeddingModelDownloadProvider),
      isA<ModelDownloadIdle>(),
    );
    expect(chat.lastDownload, isNotNull);
    expect(embedding.lastDownload, isNull);
  });

  test('una que terminó con la app cerrada se recoge, el modelo queda listo '
      'y la IA que lo esperaba se entera', () async {
    chat.downloading = true;
    final container = containerWith(systemDownloads: true);

    await resumeModelDownloads(container.read);
    await chat.lastDownload!.close();
    await pumpEventQueue();

    expect(chat.ready, isTrue);
    expect(container.read(chatModelDownloadProvider), isA<ModelDownloadIdle>());
    expect(queue.wakes, 1);
  });

  test('si mirar una falla, las otras se enganchan igual', () async {
    chat = _UnreachableChatModelManager();
    whisper.downloading = true;
    final container = containerWith(systemDownloads: true);

    // El fallo no se pierde: llega a quien llama, después de las demás.
    await expectLater(
      resumeModelDownloads(container.read),
      throwsA(isA<PlatformException>()),
    );

    expect(container.read(chatModelDownloadProvider), isA<ModelDownloadIdle>());

    expect(
      container.read(transcriptionModelDownloadProvider),
      isA<ModelDownloadRunning>(),
    );
  });

  test('bajadas dentro de la app no sobreviven a cerrarla: no hay nada a qué '
      'engancharse', () async {
    chat.downloading = true;
    final container = containerWith(systemDownloads: false);

    await resumeModelDownloads(container.read);

    expect(container.read(chatModelDownloadProvider), isA<ModelDownloadIdle>());
    expect(chat.lastDownload, isNull);
  });
}
