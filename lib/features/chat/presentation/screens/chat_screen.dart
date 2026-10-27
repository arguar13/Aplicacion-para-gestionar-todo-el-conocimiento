import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/thumbnail_decode.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/chat_attachment.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/language_model_missing.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/usecases/ask_vault_question_usecase.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_selection.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_conversations_panel.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_top_bar.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántos caracteres de los documentos adjuntos a un mensaje se le mandan
/// al modelo, entre todos (F30). El modelo lee, como mucho, 2048 tokens de
/// una vez —instrucción, lo conversado, el mensaje y la respuesta—: 1.800
/// caracteres son unos 500. Hasta F30 eran 6.000 por documento, más de lo
/// que entraba con todo lo demás. Con un documento adjunto, el modelo ve su
/// principio —donde suele estar lo que orienta— y el resto sigue en la
/// biblioteca.
const _kAttachmentTextBudget = 1800;

/// Con documentos adjuntos, cuántas fuentes de la bóveda acompañan al
/// mensaje: menos que sin ellos, para que entre todo.
const _kSourcesWithAttachments = 2;

/// Un adjunto ya elegido y guardado, listo para mandarse con el próximo
/// mensaje.
///
/// Guarda los bytes además de [attachment] —que ya tiene su
/// [ChatAttachment.relativePath] en el almacén— para no tener que releerlos
/// del disco al armar el mensaje multimodal ni al dibujar la miniatura en
/// el compositor.
class _PendingAttachment {
  const _PendingAttachment({required this.attachment, required this.bytes});

  final ChatAttachment attachment;
  final Uint8List bytes;
}

/// El chat de la app, en dos modos, con historial persistente.
///
/// **Con mi bóveda**: busca qué hay guardado y, si el modelo de lenguaje ya
/// está descargado, redacta una respuesta que cita esas fuentes. Sin el
/// modelo, ya sirve como buscador —principio 4: degradar antes que
/// fallar—. Ver la decisión 20 en docs/arquitectura.md.
///
/// **Conversación libre**: el mismo modelo, sin restringirlo al contenido
/// de la bóveda — para hablar con él como con cualquier asistente. Acá no
/// hay red de contención: sin el modelo descargado no hay nada que
/// contestar, porque no existe una "búsqueda" de respaldo para una charla
/// que no busca nada.
///
/// Cada modo guarda su propio historial de conversaciones —ver la decisión
/// 26 en docs/arquitectura.md—: abrir una conversación pasada arma una
/// sesión nueva del modelo, así que no recuerda lo hablado antes de
/// reabrirla, aunque el historial completo se siga mostrando en pantalla.
/// Es una limitación aceptada y no un error: `flutter_gemma` no ofrece
/// forma de recargar una sesión ya cerrada con su historial previo sin
/// volver a pedirle una respuesta por cada mensaje viejo.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_PendingAttachment> _pendingAttachments = [];

  /// Si el modelo elegido puede contestar y, si no, qué le falta (F32):
  /// bajar Gemma, una clave, la cuota. `null` mientras se mira.
  LanguageModelStatus? _modelStatus;
  bool get _modelReady => _modelStatus?.isReady ?? false;
  var _asking = false;
  var _attaching = false;

  /// Dónde está parado el chat —el modo, el cuaderno y la conversación
  /// abierta de cada modo— (F42): vive en [chatSelectionProvider], porque
  /// lo cambian también la barra, el panel de conversaciones y el «+» del
  /// campo. La pantalla lo escucha ([_onSelectionChanged]) para cerrar lo
  /// que ya no corresponde.
  ChatSelection get _selection => ref.read(chatSelectionProvider);
  ChatConversationMode get _mode => _selection.mode;

  /// A qué cuaderno queda acotado el modo con la bóveda (F16, D1). `null`
  /// es "toda la bóveda"; el modo libre lo ignora.
  String? get _notebookId => _selection.notebookId;

  /// La sesión de la conversación libre en curso. Vive mientras dure la
  /// charla —no se abre y se cierra pregunta a pregunta—, para que el
  /// modelo tenga todo lo dicho antes como contexto.
  FreeConversation? _conversation;

  /// Lo mismo, para el modo con la bóveda.
  VaultConversation? _vaultConversation;

  /// La respuesta que el modelo está escribiendo, para mostrarla mientras
  /// llega (F30); `null` si no hay ninguna o todavía no escribió nada.
  final _streamingText = ValueNotifier<String?>(null);

  /// En qué conversación se está escribiendo la respuesta: la burbuja que
  /// crece se muestra solo ahí, no en la del otro modo.
  String? _askingConversationId;

  /// Corta la respuesta que se está escribiendo; `null` si no hay ninguna.
  Future<void> Function()? _stopReply;

  String? get _currentConversationId => _selection.conversationId;

  /// El turno del modelo, al que la pantalla le avisa si está a la vista
  /// (F27): mientras lo esté, una charla abierta no suelta el modelo.
  late final LanguageModelGate _gate;
  late final AppLifecycleListener _lifecycle;

  /// Si la ruta del chat se ve: el `Navigator` apaga el `TickerMode` de las
  /// pantallas tapadas por otra.
  ValueListenable<TickerModeData>? _routeVisible;

  @override
  void initState() {
    super.initState();
    _gate = ref.read(languageModelGateProvider);
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _tellPresence());
    _streamingText.addListener(_followStreaming);
    ref.listenManual(chatSelectionProvider, _onSelectionChanged);
    _refreshModelStatus();
  }

  /// Mientras la respuesta crece, la lista la sigue —si se estaba mirando el
  /// final—: quien subió a releer algo no es arrastrado hacia abajo.
  void _followStreaming() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels > 120) return;
      _scrollController.jumpTo(position.maxScrollExtent);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.getValuesNotifier(context);
    if (visible != _routeVisible) {
      _routeVisible?.removeListener(_tellPresence);
      _routeVisible = visible..addListener(_tellPresence);
    }
    _tellPresence();
  }

  /// Le dice al turno del modelo si el chat está a la vista: la ruta sin
  /// otra encima y la app en primer plano. Con la pantalla apagada, o en
  /// otra pantalla, una charla sin mensajes suelta el modelo pasado
  /// `kChatIdleRelease`, y la cola de la IA sigue.
  void _tellPresence() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final visible =
        mounted &&
        (_routeVisible?.value.enabled ?? false) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    final cameBack = visible && !_gate.chatVisible;
    _gate.chatVisible = visible;
    // Al salir de la app el modelo pudo haberse soltado para liberar memoria
    // (F30): al volver al chat se vuelve a cargar, antes del mensaje.
    if (cameBack && _modelReady) unawaited(_warmUp());
  }

  @override
  void dispose() {
    _routeVisible?.removeListener(_tellPresence);
    _lifecycle.dispose();
    _gate.chatVisible = false;
    // Salir corta la respuesta en curso: lo escrito hasta ahí se guarda.
    unawaited(_stopReply?.call());
    _streamingText
      ..removeListener(_followStreaming)
      ..dispose();
    _controller.dispose();
    _scrollController.dispose();
    unawaited(_conversation?.close());
    unawaited(_vaultConversation?.close());
    super.dispose();
  }

  Future<void> _refreshModelStatus() async {
    _showModelStatus(await ref.read(languageModelStatusCheckProvider)());
  }

  void _showModelStatus(LanguageModelStatus status) {
    if (!mounted) return;
    final wasReady = _modelReady;
    setState(() => _modelStatus = status);
    if (status.isReady && !wasReady) unawaited(_warmUp());
  }

  /// Carga el modelo mientras la persona escribe (F30), en vez de con el
  /// primer mensaje: cargar ~3,7 GB son segundos que así no se esperan. Si
  /// falla, el primer mensaje lo vuelve a intentar y ahí muestra el error;
  /// acá solo se registra.
  Future<void> _warmUp() async {
    final model = ref.read(chatModelProvider);
    final telemetry = ref.read(telemetryServiceProvider);
    try {
      await model.warmUp();
      // El motor es de terceros y falla de formas sin un tipo propio.
    } on Object catch (error, stackTrace) {
      telemetry.recordError(
        error,
        stackTrace,
        hint: 'ChatScreen: cargar el modelo de antemano',
      );
    }
  }

  /// La pantalla del modelo —o [route], la que resuelve lo que falta— y, al
  /// volver, si ya puede contestar.
  Future<void> _openModelScreen([
    String route = RoutePaths.languageModel,
  ]) async {
    await context.push(route);
    if (!mounted) return;
    unawaited(_refreshModelStatus());
  }

  /// Cambió dónde está parado el chat (F42), lo cambie quien lo cambie: la
  /// barra, el panel o el «+». Lo que ya no corresponde se cierra acá, con
  /// las reglas de siempre:
  ///
  /// - la respuesta que se está escribiendo se corta si su conversación ya
  ///   no está abierta —otra conversación, una nueva, otro cuaderno, o la
  ///   borraron—; cambiar de modo no la corta, sigue en la suya;
  /// - la sesión del modelo de un modo se cierra si cambió su conversación:
  ///   abrir una vieja arma otra (ver la decisión 26).
  void _onSelectionChanged(ChatSelection? previous, ChatSelection next) {
    final asking = _askingConversationId;
    if (asking != null && !next.holds(asking)) unawaited(_stopReply?.call());
    if (previous?.vaultConversationId != next.vaultConversationId) {
      unawaited(_vaultConversation?.close());
      _vaultConversation = null;
    }
    if (previous?.freeConversationId != next.freeConversationId) {
      unawaited(_conversation?.close());
      _conversation = null;
    }
    final opened = next.conversationId;
    if (opened != null && opened != previous?.conversationId) _scrollToEnd();
  }

  /// Deja el modo activo listo para arrancar una conversación nueva y
  /// vacía, sin borrar ninguna de las guardadas: la próxima vez que se
  /// mande un mensaje, se crea una fila nueva en el historial.
  void _newConversation() =>
      ref.read(chatSelectionProvider.notifier).startNew();

  Future<void> _pickAttachmentKind() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l10n.chatAttachImageAction),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_addAttachment());
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.chatAttachDocumentAction),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_addAttachment());
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Trae un archivo del selector del sistema y lo clasifica **por sus
  /// bytes**, no por cuál de las dos opciones del menú se tocó: los dos
  /// caminos abren el mismo selector sin filtrar —igual que
  /// `SystemFileChooser`, que tampoco confía en la extensión— y es
  /// `FileFormat.sourceKind` quien decide si es una imagen o un documento.
  Future<void> _addAttachment() async {
    final l10n = AppLocalizations.of(context)!;

    final CapturedFile? chosen;
    try {
      chosen = await ref.read(fileChooserProvider).pickOne();
    } on FileAccessDeniedException {
      if (!mounted) return;
      _showSnack(l10n.captureFileAccessDenied);
      return;
    }
    if (chosen == null || !mounted) return;

    // Una vez más allá del `null`, se guarda en su propia variable: la
    // promoción de `chosen` a no anulable no sobrevive dentro de los
    // cierres de `setState` de más abajo, porque quedó asignada dentro de
    // un `try` — a esta, asignada de una sola vez y nunca dentro de un
    // `try`, sí se la puede usar sin `!` en cualquier lado.
    final file = chosen;

    // Un adjunto del chat se le pasa al modelo, así que se necesita entero en
    // memoria: se comprueba el tamaño —que el selector informa sin leer el
    // archivo— antes de leerlo, y lo que pasa del tope se rechaza con un
    // aviso claro en vez de dejar que la app se quede sin memoria.
    if (file.isTooLarge) {
      _showSnack(
        l10n.globalErrorFileTooLarge(
          (CapturedFile.maxBytes / (1024 * 1024)).round().toString(),
        ),
      );
      return;
    }
    final bytes = await file.readAll();
    if (!mounted) return;

    final format = file.format;
    if (format.sourceKind == SourceKind.image) {
      // El modelo mira una foto por mensaje (F30): es lo que le entra en la
      // ventana junto con el resto, y lo que el motor carga.
      if (_pendingAttachments.any(
        (a) => a.attachment.kind == ChatAttachmentKind.image,
      )) {
        _showSnack(l10n.chatAttachOneImage);
        return;
      }
      final ids = ref.read(idGeneratorProvider);
      final relativePath = await ref
          .read(fileStoreProvider)
          .save(bytes: bytes, suggestedName: file.name, id: ids.next());
      if (!mounted) return;
      setState(() {
        _pendingAttachments.add(
          _PendingAttachment(
            attachment: ChatAttachment(
              name: file.name,
              kind: ChatAttachmentKind.image,
              relativePath: relativePath,
            ),
            bytes: bytes,
          ),
        );
      });
      return;
    }

    final parser = ref
        .read(documentParsersProvider)
        .where((p) => p.canParse(format))
        .firstOrNull;
    if (parser == null) {
      _showSnack(l10n.chatAttachUnreadable(file.name));
      return;
    }

    setState(() => _attaching = true);
    try {
      final parsed = await parser.parse(
        DocumentSource.memory(bytes, name: file.name),
      );
      final ids = ref.read(idGeneratorProvider);
      final relativePath = await ref
          .read(fileStoreProvider)
          .save(bytes: bytes, suggestedName: file.name, id: ids.next());
      if (!mounted) return;
      setState(() {
        _pendingAttachments.add(
          _PendingAttachment(
            attachment: ChatAttachment(
              name: file.name,
              kind: ChatAttachmentKind.document,
              relativePath: relativePath,
              extractedText: parsed.markdown,
            ),
            bytes: bytes,
          ),
        );
      });
      // `DocumentParser.parse` declara que lanza `UnreadableDocumentException`
      // ante bytes corruptos: un archivo así no es un defecto del programa.
    } on UnreadableDocumentException {
      if (!mounted) return;
      _showSnack(l10n.chatAttachUnreadable(file.name));
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  void _removeAttachment(_PendingAttachment attachment) {
    setState(() => _pendingAttachments.remove(attachment));
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final attachments = List<_PendingAttachment>.of(_pendingAttachments);
    if ((text.isEmpty && attachments.isEmpty) || _asking) return;

    final l10n = AppLocalizations.of(context)!;
    final repo = ref.read(chatConversationRepositoryProvider);
    final ids = ref.read(idGeneratorProvider);
    final clock = ref.read(clockProvider);
    final mode = _mode;

    setState(() {
      _asking = true;
      _controller.clear();
      _pendingAttachments.clear();
    });
    _scrollToEnd();

    var conversationId = _currentConversationId;
    if (conversationId == null) {
      final conversation = await repo.createConversation(
        mode,
        notebookId: _notebookId,
      );
      conversationId = conversation.id;
      if (mounted) {
        ref.read(chatSelectionProvider.notifier).started(mode, conversationId);
      }
    }
    _askingConversationId = conversationId;

    await repo.addMessage(
      PersistedChatMessage(
        id: ids.next(),
        conversationId: conversationId,
        isUser: true,
        text: text,
        createdAt: clock(),
        attachments: [for (final a in attachments) a.attachment],
      ),
    );
    _scrollToEnd();

    final promptText = _buildPrompt(text, attachments);
    final images = [
      for (final a in attachments)
        if (a.attachment.kind == ChatAttachmentKind.image) a.bytes,
    ];

    final answer = switch (mode) {
      ChatConversationMode.vault => await _answerVault(
        text: text,
        promptText: promptText,
        images: images,
        conversationId: conversationId,
        id: ids.next(),
        clock: clock,
        l10n: l10n,
      ),
      ChatConversationMode.free => await _answerFree(
        promptText: promptText,
        images: images,
        conversationId: conversationId,
        id: ids.next(),
        clock: clock,
        l10n: l10n,
      ),
    };

    // Se guarda aunque se haya salido de la pantalla a mitad: lo que el
    // modelo alcanzó a escribir no se pierde.
    await repo.addMessage(answer);
    if (!mounted) return;
    _streamingText.value = null;
    setState(() {
      _asking = false;
      _askingConversationId = null;
    });
    _scrollToEnd();
  }

  /// Sigue la respuesta que el modelo va escribiendo (F30): la muestra
  /// mientras crece y la deja cortar con [_stopReply]. Termina con todo lo
  /// escrito, cómo terminó y, si falló, por qué.
  Future<_Reply> _follow(ChatReplyStream replies) {
    final done = Completer<_Reply>();
    var text = '';
    late final StreamSubscription<String> subscription;
    subscription = replies.listen(
      (latest) {
        text = latest;
        if (mounted) _streamingText.value = latest;
      },
      onError: (Object error) {
        if (!done.isCompleted) done.complete((text: text, error: error));
      },
      onDone: () {
        if (!done.isCompleted) done.complete((text: text, error: null));
      },
      cancelOnError: true,
    );
    _stopReply = () async {
      if (done.isCompleted) return;
      done.complete((text: text, error: const _Stopped()));
      await subscription.cancel();
    };
    if (mounted) setState(() {});
    return done.future.whenComplete(() => _stopReply = null);
  }

  /// El mensaje del modelo que se guarda con [reply]: el texto que alcanzó a
  /// escribir y, si no terminó bien, por qué.
  PersistedChatMessage _replyMessage(
    _Reply reply, {
    required String id,
    required String conversationId,
    required DateTime Function() clock,
    required AppLocalizations l10n,
    List<ChatSource> sources = const [],
  }) {
    final written = reply.text.trim().isNotEmpty;
    final error = switch (reply.error) {
      null => null,
      _Stopped() => written ? null : l10n.chatReplyStoppedEmpty,
      ChatMessageTooLongException() => l10n.chatMessageTooLong,
      ChatImagesUnsupportedException() => l10n.chatImagesUnsupported,
      _ => written ? l10n.chatReplyInterrupted : l10n.globalErrorUnexpected,
    };
    return PersistedChatMessage(
      id: id,
      conversationId: conversationId,
      isUser: false,
      text: written ? reply.text.trim() : '',
      sources: written ? sources : const [],
      createdAt: clock(),
      error: error,
    );
  }

  /// El mensaje que ve el modelo: el texto del usuario más, si adjuntó
  /// documentos, el contenido que se les extrajo —recortado a
  /// [_kAttachmentTextBudget]—. Lo que se guarda en [PersistedChatMessage]
  /// y se muestra en pantalla es solo [text], sin este agregado: la persona
  /// que preguntó no necesita releer el documento entero que ella misma
  /// adjuntó.
  String _buildPrompt(String text, List<_PendingAttachment> attachments) {
    final docs = [
      for (final a in attachments)
        if (a.attachment.kind == ChatAttachmentKind.document &&
            (a.attachment.extractedText ?? '').isNotEmpty)
          a.attachment,
    ];
    if (docs.isEmpty) return text;

    // El tope se reparte entre los documentos.
    final each = _kAttachmentTextBudget ~/ docs.length;
    final content = docs
        .map((doc) {
          final extracted = doc.extractedText!.trim();
          final truncated = extracted.length > each
              ? '${extracted.substring(0, each)}…'
              : extracted;
          return '### ${doc.name}\n$truncated';
        })
        .join('\n\n');

    final prefix = text.isEmpty ? '' : '$text\n\n';
    return '${prefix}Contenido de los documentos adjuntos:\n\n$content';
  }

  /// Los elementos de [_notebookId], resueltos en el momento (F16, D1):
  /// `null` si no hay cuaderno elegido —"toda la bóveda"—, sea manual o por
  /// consulta guardada, `NotebookRepository.resolveQuery` ya deja una sola
  /// `LibraryQuery` para las dos formas.
  Future<Set<String>?> _resolveScopeIds() async {
    final notebookId = _notebookId;
    if (notebookId == null) return null;
    final query = await ref
        .read(notebookRepositoryProvider)
        .resolveQuery(notebookId);
    // Solo hacen falta los ids, no los elementos enteros —el benchmark de
    // F16 (16.2, commit 13) encontró que `list()` arma cada `KnowledgeItem`
    // con sus renditions/etiquetas/propiedades para descartarlas todas acá
    // mismo, y eso sacaba a un cuaderno de 500 elementos del objetivo de
    // 300 ms; `matchingIds()` es la misma consulta sin ese armado—.
    final result = await ref.read(libraryRepositoryProvider).matchingIds(query);
    return result.match((_) => const {}, (ids) => ids.toSet());
  }

  Future<PersistedChatMessage> _answerVault({
    required String text,
    required String promptText,
    required List<Uint8List> images,
    required String conversationId,
    required String id,
    required DateTime Function() clock,
    required AppLocalizations l10n,
  }) async {
    final query = text.isEmpty ? promptText : text;
    final scopeIds = await _resolveScopeIds();

    if (!_modelReady) {
      final result = await ref.read(askVaultQuestionUseCaseProvider)(
        AskVaultQuestionParams(question: query, scopeIds: scopeIds),
      );
      return result.match(
        (failure) => PersistedChatMessage(
          id: id,
          conversationId: conversationId,
          isUser: false,
          text: '',
          createdAt: clock(),
          error: failure.localizedMessage(l10n),
        ),
        (answer) => PersistedChatMessage(
          id: id,
          conversationId: conversationId,
          isUser: false,
          text: answer.text ?? '',
          sources: answer.sources,
          createdAt: clock(),
        ),
      );
    }

    try {
      final sources = await ref
          .read(vaultRetrieverProvider)
          .retrieve(
            query,
            scopeIds: scopeIds,
            limit: promptText.length > text.length
                ? _kSourcesWithAttachments
                : kChatMaxSources,
          );

      final conversation = _vaultConversation ??= await ref
          .read(chatModelProvider)
          .startVaultConversation();

      final reply = await _follow(
        conversation.send(
          message: promptText,
          sources: sources,
          images: images,
        ),
      );
      return _replyMessage(
        reply,
        id: id,
        conversationId: conversationId,
        clock: clock,
        l10n: l10n,
        sources: sources,
      );
      // El motor de inferencia es de terceros (flutter_gemma); puede fallar
      // de formas que no tienen un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return _replyMessage(
        (text: '', error: e),
        id: id,
        conversationId: conversationId,
        clock: clock,
        l10n: l10n,
      );
    }
  }

  Future<PersistedChatMessage> _answerFree({
    required String promptText,
    required List<Uint8List> images,
    required String conversationId,
    required String id,
    required DateTime Function() clock,
    required AppLocalizations l10n,
  }) async {
    // Sin el modelo no hay con qué contestar: a diferencia del modo con la
    // bóveda, acá no hay ninguna búsqueda de respaldo que ofrecer.
    if (!_modelReady) {
      return PersistedChatMessage(
        id: id,
        conversationId: conversationId,
        isUser: false,
        text: '',
        createdAt: clock(),
        error: _modelStatus == null
            ? l10n.chatFreeModelRequired
            : languageModelMissingMessage(
                context,
                _modelStatus!,
                downloadMessage: l10n.chatFreeModelRequired,
              ),
      );
    }

    try {
      final conversation = _conversation ??= await ref
          .read(chatModelProvider)
          .startConversation();

      final reply = await _follow(
        conversation.send(promptText, images: images),
      );
      return _replyMessage(
        reply,
        id: id,
        conversationId: conversationId,
        clock: clock,
        l10n: l10n,
      );
      // El motor de inferencia es de terceros (flutter_gemma); puede fallar
      // de formas que no tienen un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return _replyMessage(
        (text: '', error: e),
        id: id,
        conversationId: conversationId,
        clock: clock,
        l10n: l10n,
      );
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selection = ref.watch(chatSelectionProvider);
    final isFree = selection.isFree;
    final conversationId = selection.conversationId;
    // Elegir otra cuenta o proveedor, cargar una clave o quedarse sin cuota
    // cambia lo que el chat puede hacer sin salir de él (F32).
    ref.listen(languageModelStatusProvider, (_, next) {
      if (next.valueOrNull case final status?) _showModelStatus(status);
    });

    return Scaffold(
      // F42: arriba, limpio —☰, la píldora del modelo con dónde se
      // pregunta, ✎—; el historial es el panel de la izquierda.
      appBar: ChatTopBar(
        textScaler: MediaQuery.textScalerOf(context),
        onOpenPanel: () => unawaited(showChatConversationsPanel(context)),
        onNewConversation: conversationId == null ? null : _newConversation,
        onOpenRoute: (route) => unawaited(_openModelScreen(route)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_modelStatus case final status? when !status.isReady)
              _ModelBanner(
                message: switch (status) {
                  LanguageModelNeedsDownload() =>
                    isFree
                        ? l10n.chatFreeModelRequired
                        : l10n.chatModelNotReadyBanner,
                  // Con la nube, lo que falta (F32); en el modo con la
                  // bóveda, además, que mientras se ven las fuentes.
                  _ => [
                    languageModelMissingMessage(context, status),
                    if (!isFree) l10n.chatSourcesMeanwhile,
                  ].join(' '),
                },
                action: languageModelMissingAction(
                  l10n,
                  status,
                  downloadLabel: l10n.chatModelDownloadAction,
                ),
                onDownload: _openModelScreen,
              ),
            Expanded(
              child: conversationId == null
                  ? _EmptyState(
                      explanation: isFree
                          ? l10n.chatFreeEmptyExplanation
                          : l10n.chatEmptyExplanation,
                    )
                  : _MessagesList(
                      conversationId: conversationId,
                      mode: _mode,
                      asking:
                          _asking && _askingConversationId == conversationId,
                      streaming: _streamingText,
                      scrollController: _scrollController,
                    ),
            ),
            if (_pendingAttachments.isNotEmpty)
              _AttachmentChips(
                attachments: _pendingAttachments,
                onRemove: _removeAttachment,
              ),
            // El lector flotante se para encima de la caja, no sobre
            // "Enviar" (F25).
            ReadAloudClearance(
              child: _Composer(
                controller: _controller,
                enabled: !_asking,
                attaching: _attaching,
                onSend: _send,
                onStop: _stopReply == null
                    ? null
                    : () => unawaited(_stopReply?.call()),
                onAttach: _attaching ? null : _pickAttachmentKind,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que se lee en voz alta de una conversación (F25): los mensajes, en
/// orden —los del usuario y las respuestas—, cada uno con su resaltado. Sin
/// los avisos de error ni los mensajes que son solo adjuntos. Se arma de
/// nuevo solo cuando llega un mensaje.
final _readableProvider = Provider.autoDispose
    .family<ReadableDocument?, ({String conversationId, String title})>((
      ref,
      chat,
    ) {
      final messages = ref
          .watch(chatMessagesProvider(chat.conversationId))
          .valueOrNull;
      if (messages == null) return null;
      return documentFrom('chat:${chat.conversationId}', chat.title, [
        for (final message in messages)
          if (message.error == null && message.text.isNotEmpty)
            (
              sourceKey: _messageKey(message.id),
              text: message.text,
              markdown: false,
              transcript: false,
            ),
      ]);
    });

/// Con qué nombre conoce el lector flotante a un mensaje (F25).
String _messageKey(String messageId) => 'chat:$messageId';

class _MessagesList extends ConsumerWidget {
  const _MessagesList({
    required this.conversationId,
    required this.mode,
    required this.asking,
    required this.streaming,
    required this.scrollController,
  });

  final String conversationId;
  final ChatConversationMode mode;

  /// Si en esta conversación se está esperando una respuesta.
  final bool asking;

  /// La respuesta mientras se escribe (F30).
  final ValueListenable<String?> streaming;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final messagesAsync = ref.watch(chatMessagesProvider(conversationId));

    ref.listen(chatMessagesProvider(conversationId), (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    });

    return messagesAsync.when(
      data: (messages) {
        if (messages.isEmpty && !asking) {
          return _EmptyState(
            explanation: mode == ChatConversationMode.free
                ? l10n.chatFreeEmptyExplanation
                : l10n.chatEmptyExplanation,
          );
        }
        return ReadableRegion(
          document: ref.watch(
            _readableProvider((
              conversationId: conversationId,
              title: l10n.chatTitle,
            )),
          ),
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length + (asking ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= messages.length) {
                return ValueListenableBuilder<String?>(
                  valueListenable: streaming,
                  builder: (context, text, _) => text == null || text.isEmpty
                      ? const _TypingBubble()
                      : _StreamingBubble(text: text),
                );
              }
              return _MessageBubble(message: messages[index]);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, stackTrace) => Center(child: Text(l10n.globalErrorUnexpected)),
    );
  }
}

class _ModelBanner extends StatelessWidget {
  const _ModelBanner({
    required this.message,
    required this.action,
    required this.onDownload,
  });

  final String message;

  /// Qué dice el botón y adónde lleva.
  final ({String label, String route}) action;
  final void Function(String route) onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
          TextButton(
            onPressed: () => onDownload(action.route),
            child: Text(action.label),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.explanation});

  final String explanation;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(icon: Icons.chat_bubble_outline, title: explanation);
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 24),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// La respuesta mientras el modelo la escribe (F30): crece palabra por
/// palabra. Las fuentes aparecen al terminar, con el mensaje guardado.
class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('chat-streaming-reply'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final PersistedChatMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final attachment in message.attachments)
                      _AttachmentPreview(attachment: attachment),
                  ],
                ),
              ),
            if (message.text.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ReadAloudText(
                    message.text,
                    sourceKey: _messageKey(message.id),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final error = message.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.text.isNotEmpty) ...[
            ReadAloudText(
              message.text,
              sourceKey: _messageKey(message.id),
              style: theme.textTheme.bodyLarge,
            ),
            // Lo que alcanzó a escribir antes de un error se muestra igual,
            // con el aviso debajo (F30).
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (message.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final source in message.sources) _SourceCard(source: source),
            ],
          ] else if (error != null)
            Text(error, style: TextStyle(color: theme.colorScheme.error))
          else if (message.sources.isNotEmpty) ...[
            Text(
              l10n.chatSourcesOnlyExplanation,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final source in message.sources) _SourceCard(source: source),
          ] else
            Text(l10n.chatNoSourcesFound, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends ConsumerWidget {
  const _AttachmentPreview({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (attachment.kind == ChatAttachmentKind.image) {
      final bytesAsync = ref.watch(
        chatAttachmentBytesProvider(attachment.relativePath),
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: bytesAsync.maybeWhen(
          data: (bytes) => bytes == null
              ? _AttachmentPlaceholder(theme: theme)
              : Image.memory(
                  bytes,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  // Una foto adjunta son millones de píxeles: se decodifica
                  // al tamaño de la miniatura, no entera.
                  cacheWidth: thumbnailDecodeWidth(context, 96),
                  // Bytes corruptos o truncados no deberían tirar abajo el
                  // mensaje entero: un ícono genérico es peor que una
                  // miniatura, pero mucho mejor que una pantalla roja.
                  errorBuilder: (context, error, stackTrace) =>
                      _AttachmentPlaceholder(theme: theme),
                ),
          orElse: () => _AttachmentPlaceholder(theme: theme),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 18),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(attachment.name, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPlaceholder extends StatelessWidget {
  const _AttachmentPlaceholder({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Icon(
        Icons.image_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final ChatSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(RoutePaths.itemDetail(source.itemId)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(source.itemTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                source.excerpt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentChips extends StatelessWidget {
  const _AttachmentChips({required this.attachments, required this.onRemove});

  final List<_PendingAttachment> attachments;
  final void Function(_PendingAttachment) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final pending in attachments)
            InputChip(
              avatar: pending.attachment.kind == ChatAttachmentKind.image
                  ? ClipOval(
                      child: Image.memory(
                        pending.bytes,
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                        cacheWidth: thumbnailDecodeWidth(context, 24),
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.image_outlined, size: 18),
                      ),
                    )
                  : const Icon(Icons.description_outlined, size: 18),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  pending.attachment.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              deleteButtonTooltipMessage: l10n.chatAttachRemoveTooltip,
              onDeleted: () => onRemove(pending),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.attaching,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool attaching;
  final VoidCallback onSend;

  /// Corta la respuesta que se está escribiendo; `null` si no hay ninguna.
  /// Mientras haya una, el botón de enviar es el de detener (F30).
  final VoidCallback? onStop;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            icon: attaching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file),
            tooltip: l10n.chatAttachTooltip,
            onPressed: onAttach,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(hintText: l10n.chatInputHint),
            ),
          ),
          const SizedBox(width: 8),
          if (onStop case final stop?)
            IconButton.filledTonal(
              icon: const Icon(Icons.stop),
              tooltip: l10n.chatStopTooltip,
              onPressed: stop,
            )
          else
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: enabled ? onSend : null,
            ),
        ],
      ),
    );
  }
}

/// Cómo terminó una respuesta: todo lo que el modelo alcanzó a escribir y,
/// si no terminó sola, por qué —un error, o [_Stopped]—.
typedef _Reply = ({String text, Object? error});

/// La persona cortó la respuesta.
class _Stopped {
  const _Stopped();
}
