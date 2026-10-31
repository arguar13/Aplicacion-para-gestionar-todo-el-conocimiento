import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
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
import 'package:sinapsis/features/ai_models/domain/services/model_thinking.dart';
import 'package:sinapsis/features/ai_models/presentation/language_model_missing.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/camera_chooser.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/usecases/ask_vault_question_usecase.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_selection.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_think_more_provider.dart';
import 'package:sinapsis/features/chat/presentation/widgets/add_to_chat_sheet.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_ambient_glow.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_attachments.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_composer.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_conversations_panel.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_message_list.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_model_notice.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_stage_transition.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_top_bar.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_welcome.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
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

/// De dónde viene lo que se adjunta: las tres tarjetas de «Agregar al chat»
/// (F42).
enum _AttachSource { camera, photos, files }

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
  final _composerFocus = FocusNode();
  final _scrollController = ScrollController();
  final List<PendingChatAttachment> _pendingAttachments = [];

  /// Si el modelo elegido puede contestar y, si no, qué le falta (F32):
  /// bajar Gemma, una clave, la cuota. `null` mientras se mira.
  LanguageModelStatus? _modelStatus;
  bool get _modelReady => _modelStatus?.isReady ?? false;
  var _asking = false;
  var _attaching = false;

  /// «Pensar más», prendido desde «Agregar al chat» (F42). Vale para lo que
  /// se pregunte mientras el chat esté abierto, en los dos modos; no se
  /// guarda, porque pensar a fondo tarda y gasta más cuota, y eso se elige
  /// a sabiendas cada vez. Solo llega al modelo si el que escribe tiene cómo
  /// ([_thinkingMore]).
  var _thinkMore = false;

  /// Si «Pensar más» vale ahora: prendido y con un modelo que lo permite.
  bool get _thinkingMore =>
      _thinkMore &&
      ref.read(chatThinkMoreSupportProvider).support ==
          ThinkMoreSupport.supported;

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

  /// Las fuentes de la respuesta que se está escribiendo, en el modo con la
  /// bóveda: las que se le dieron al modelo para esta vuelta.
  List<ChatSource> _streamingSources = const [];

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
    _statusChecked = _refreshModelStatus();
    // Una pregunta que trae otra pantalla (F43): la que ya esperaba al
    // abrirse el chat, o la que llega con el chat ya abierto. Se toma fuera
    // del armado de la pantalla, que no deja cambiar el estado.
    ref.listenManual(chatHandoffProvider, (_, handoff) {
      if (handoff != null) unawaited(Future.microtask(_takeHandoff));
    }, fireImmediately: true);
  }

  /// La primera vez que se miró si el modelo puede contestar: una pregunta
  /// que llega de otra pantalla la espera, para contestarse con el modelo si
  /// se puede.
  late final Future<void> _statusChecked;

  /// Toma la pregunta que dejó otra pantalla ([chatHandoffProvider]): una
  /// conversación nueva con la bóveda —acotada al cuaderno, si vino de uno—,
  /// la pregunta en el campo y, si pidió mandarse, mandada.
  Future<void> _takeHandoff() async {
    if (!mounted) return;
    final handoff = ref.read(chatHandoffProvider);
    if (handoff == null) return;
    ref.read(chatHandoffProvider.notifier).state = null;
    ref.read(chatSelectionProvider.notifier)
      ..changeMode(ChatConversationMode.vault)
      ..selectNotebook(handoff.notebookId)
      ..startNew();
    _controller.value = TextEditingValue(
      text: handoff.question,
      selection: TextSelection.collapsed(offset: handoff.question.length),
    );
    await _statusChecked;
    if (!mounted) return;
    if (handoff.send && !_asking) {
      await _send();
    } else {
      _composerFocus.requestFocus();
    }
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
    _composerFocus.dispose();
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

  /// La hoja «Agregar al chat» del «+» (F42): adjuntar, dónde se pregunta
  /// y «Pensar más». Lo que se cambia ahí vale en el acto.
  ///
  /// Como «Dónde pregunto», llega a lo sumo al 85 % del alto: con la letra
  /// grande en un teléfono chico lo de adentro se desplaza, y arriba sigue a
  /// la vista el chat, que la cierra con un toque.
  Future<void> _openAddSheet() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: AddToChatSheet(
          thinkMore: _thinkMore,
          hasImage: _pendingAttachments.any((a) => a.isImage),
          onCamera: () => unawaited(_attachFrom(_AttachSource.camera)),
          onPhotos: () => unawaited(_attachFrom(_AttachSource.photos)),
          onFiles: () => unawaited(_attachFrom(_AttachSource.files)),
          onThinkMoreChanged: (on) => setState(() => _thinkMore = on),
        ),
      ),
    );
  }

  /// Trae un archivo de [source] —la cámara, la galería o el selector de
  /// archivos— y lo clasifica **por sus bytes**, no por la tarjeta que se
  /// tocó: «Archivos» abre el selector sin filtrar —igual que
  /// `SystemFileChooser`, que tampoco confía en la extensión— y es
  /// `FileFormat.sourceKind` quien decide si es una imagen o un documento.
  Future<void> _attachFrom(_AttachSource source) async {
    final l10n = AppLocalizations.of(context)!;

    final CapturedFile? chosen;
    try {
      chosen = await switch (source) {
        _AttachSource.camera => ref.read(cameraChooserProvider).takePhoto(),
        _AttachSource.photos =>
          ref.read(photoLibraryChooserProvider).pickPhoto(),
        _AttachSource.files => ref.read(fileChooserProvider).pickOne(),
      };
    } on FileAccessDeniedException {
      if (!mounted) return;
      _showSnack(l10n.captureFileAccessDenied);
      return;
    } on CameraAccessDeniedException {
      if (!mounted) return;
      _showSnack(l10n.captureCameraAccessDenied);
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
      if (_pendingAttachments.any((a) => a.isImage)) {
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
          PendingChatAttachment(
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
          PendingChatAttachment(
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

  void _removeAttachment(PendingChatAttachment attachment) {
    setState(() => _pendingAttachments.remove(attachment));
  }

  /// Una sugerencia del chat vacío (F42): la que es una pregunta entera se
  /// manda; la que hay que completar queda en el campo, con el cursor al
  /// final y el teclado abierto.
  void _useSuggestion(ChatSuggestionPick pick) {
    _controller.value = TextEditingValue(
      text: pick.text,
      selection: TextSelection.collapsed(offset: pick.text.length),
    );
    if (pick.send) {
      unawaited(_send());
    } else {
      _composerFocus.requestFocus();
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final attachments = List<PendingChatAttachment>.of(_pendingAttachments);
    if ((text.isEmpty && attachments.isEmpty) || _asking) return;

    setState(() {
      _controller.clear();
      _pendingAttachments.clear();
    });
    await _ask(text, attachments);
  }

  /// «Editar y reenviar» (F42): [text] corregido, con los mismos adjuntos
  /// que [original], como un mensaje nuevo al final de la conversación.
  Future<void> _resend(PersistedChatMessage original, String text) async {
    if (_asking) return;
    final attachments = await _reloadingAttachments(original);
    if (attachments == null) return;
    await _ask(text, attachments);
  }

  /// «Volver a generar» la última respuesta (F42): se borra y se vuelve a
  /// pedir con la pregunta que la originó, sin repetir la pregunta en el
  /// historial. La sesión del modelo sigue: lo conversado antes no se pierde.
  Future<void> _regenerate(PersistedChatMessage answer) async {
    if (_asking) return;
    final messages =
        ref.read(chatMessagesProvider(answer.conversationId)).valueOrNull ??
        const <PersistedChatMessage>[];
    final at = messages.indexWhere((m) => m.id == answer.id);
    final question = at <= 0 ? null : messages[at - 1];
    if (question == null || !question.isUser) return;

    final attachments = await _reloadingAttachments(question);
    if (attachments == null) return;
    await ref.read(chatConversationRepositoryProvider).deleteMessage(answer.id);
    if (!mounted) return;
    await _ask(question.text, attachments, repeating: true);
  }

  /// Los adjuntos de un mensaje ya guardado, listos para mandarse otra vez:
  /// las fotos se vuelven a leer del almacén; un documento ya trae su texto.
  ///
  /// `null` —y un aviso— si una foto ya no está: el modelo nunca contesta
  /// como si la foto no estuviera (F30).
  ///
  /// El chat queda ocupado desde que empieza a releerlos —antes de esperar
  /// nada—: un segundo toque en ese rato no arma otra pregunta. Si no se
  /// puede seguir, vuelve a estar libre.
  Future<List<PendingChatAttachment>?> _reloadingAttachments(
    PersistedChatMessage message,
  ) async {
    setState(() => _asking = true);
    final reloaded = await _reloadAttachments(message);
    if (!mounted) return null;
    if (reloaded == null) setState(() => _asking = false);
    return reloaded;
  }

  Future<List<PendingChatAttachment>?> _reloadAttachments(
    PersistedChatMessage message,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final store = ref.read(fileStoreProvider);
    final reloaded = <PendingChatAttachment>[];
    for (final attachment in message.attachments) {
      final bytes = attachment.kind == ChatAttachmentKind.image
          ? await store.read(attachment.relativePath)
          : Uint8List(0);
      if (bytes == null) {
        if (mounted) _showSnack(l10n.globalErrorUnexpected);
        return null;
      }
      reloaded.add(PendingChatAttachment(attachment: attachment, bytes: bytes));
    }
    return reloaded;
  }

  /// Pregunta [text], con [attachments], en la conversación abierta —o en una
  /// nueva— y guarda la respuesta. Con [repeating], la pregunta ya está en el
  /// historial: no se vuelve a guardar.
  Future<void> _ask(
    String text,
    List<PendingChatAttachment> attachments, {
    bool repeating = false,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final repo = ref.read(chatConversationRepositoryProvider);
    final ids = ref.read(idGeneratorProvider);
    final clock = ref.read(clockProvider);
    final mode = _mode;

    setState(() => _asking = true);
    // Una vibración corta, si el teléfono la tiene: salió (F42).
    unawaited(HapticFeedback.lightImpact());
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

    if (!repeating) {
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
    }
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
      _streamingSources = const [];
    });
    // Y otra al terminar (F42).
    unawaited(HapticFeedback.lightImpact());
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
  String _buildPrompt(String text, List<PendingChatAttachment> attachments) {
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

  /// Los documentos procesados de [_notebookId], resueltos en el momento (F16,
  /// D1; F41, paso 5): `null` si no hay cuaderno elegido —"toda la bóveda"—.
  /// Manual o por consulta, `NotebookRepository.memberIds` responde lo mismo
  /// para las dos formas, y solo con procesados: el chat acotado a un cuaderno
  /// lee solo su texto procesado.
  Future<Set<String>?> _resolveScopeIds() async {
    final notebookId = _notebookId;
    if (notebookId == null) return null;
    final result = await ref
        .read(notebookRepositoryProvider)
        .memberIds(notebookId);
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

      // Las citas de lo que se escribe ya son chips (F42).
      if (mounted) setState(() => _streamingSources = sources);
      final reply = await _follow(
        conversation.send(
          message: promptText,
          sources: sources,
          images: images,
          thinkMore: _thinkingMore,
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
        conversation.send(promptText, images: images, thinkMore: _thinkingMore),
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(scrollChatToEnd(_scrollController, animate: true)),
    );
  }

  /// Lo que le falta al modelo para contestar, con el botón que lo resuelve
  /// (F42; antes, una franja arriba de todo): en el vacío, una tarjeta
  /// debajo de las sugerencias; en una conversación, [compact], una línea
  /// arriba del campo. `null` si ya puede contestar o todavía se está
  /// mirando.
  Widget? _modelNotice({required bool compact}) {
    final status = _modelStatus;
    if (status == null || status.isReady) return null;
    final l10n = AppLocalizations.of(context)!;
    final isFree = _mode == ChatConversationMode.free;
    final action = languageModelMissingAction(
      l10n,
      status,
      downloadLabel: l10n.chatModelDownloadAction,
    );
    return ChatModelNotice(
      compact: compact,
      icon: switch (status) {
        LanguageModelNeedsDownload() => Icons.download_rounded,
        LanguageModelOutOfQuota() => Icons.hourglass_bottom_rounded,
        _ => Icons.key_rounded,
      },
      message: switch (status) {
        LanguageModelNeedsDownload() =>
          isFree ? l10n.chatFreeModelRequired : l10n.chatModelNotReadyBanner,
        // Con la nube, lo que falta (F32); en el modo con la bóveda, además,
        // que mientras se ven las fuentes.
        _ => [
          languageModelMissingMessage(context, status),
          if (!isFree) l10n.chatSourcesMeanwhile,
        ].join(' '),
      },
      actionLabel: action.label,
      onAction: () => unawaited(_openModelScreen(action.route)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selection = ref.watch(chatSelectionProvider);
    final isFree = selection.isFree;
    final conversationId = selection.conversationId;
    final thinkingMore =
        _thinkMore &&
        ref.watch(chatThinkMoreSupportProvider).support ==
            ThinkMoreSupport.supported;
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
      body: Stack(
        children: [
          // El brillo del vacío va detrás de todo, también del campo: sube
          // desde abajo (F42).
          Positioned.fill(
            child: ChatStageTransition(
              inConversation: conversationId != null,
              slide: false,
              child: conversationId == null
                  ? const ChatAmbientGlow()
                  : const SizedBox.shrink(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  // Del vacío a la conversación, con un fundido (F42).
                  child: ChatStageTransition(
                    inConversation: conversationId != null,
                    child: conversationId == null
                        ? ChatWelcome(
                            mode: selection.mode,
                            notebookId: isFree ? null : selection.notebookId,
                            onSuggestion: _useSuggestion,
                            notice: _modelNotice(compact: false),
                          )
                        // La conversación (F42, paso 3): sus piezas viven en
                        // `chat_message_list.dart`.
                        : ChatMessageList(
                            conversationId: conversationId,
                            mode: selection.mode,
                            asking:
                                _asking &&
                                _askingConversationId == conversationId,
                            streaming: _streamingText,
                            streamingSources: _streamingSources,
                            scrollController: _scrollController,
                            // Una conversación abierta, todavía sin mensajes.
                            empty: ChatWelcome(mode: selection.mode),
                            onRegenerate: _asking
                                ? null
                                : (answer) => unawaited(_regenerate(answer)),
                            onResend: _asking
                                ? null
                                : (original, text) =>
                                      unawaited(_resend(original, text)),
                          ),
                  ),
                ),
                // En una conversación, lo que le falta al modelo sigue a la
                // vista, en una línea arriba del campo.
                if (conversationId != null) ?_modelNotice(compact: true),
                // El lector flotante se para encima del campo, no sobre
                // "Enviar" (F25).
                ReadAloudClearance(
                  child: ChatComposer(
                    controller: _controller,
                    focusNode: _composerFocus,
                    hintText: isFree
                        ? l10n.chatComposerFreeHint
                        : l10n.chatComposerVaultHint,
                    attachments: _pendingAttachments,
                    onRemoveAttachment: _removeAttachment,
                    onSend: () => unawaited(_send()),
                    onStop: _stopReply == null
                        ? null
                        : () => unawaited(_stopReply?.call()),
                    onAdd: _attaching ? null : _openAddSheet,
                    asking: _asking,
                    attaching: _attaching,
                    thinkMore: thinkingMore,
                    onThinkMoreOff: () => setState(() => _thinkMore = false),
                  ),
                ),
              ],
            ),
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
