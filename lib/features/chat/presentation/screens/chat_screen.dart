import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/chat_attachment.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/usecases/ask_vault_question_usecase.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántos caracteres del texto extraído de un documento adjunto se le
/// mandan al modelo. Un libro entero adjunto desbordaría la ventana de
/// contexto del modelo antes de llegar a la pregunta misma; con un tope, el
/// modelo ve el principio del documento —donde suele estar lo más
/// relevante para orientarse— y el resto sigue disponible desde la
/// biblioteca si hace falta más.
const _kAttachmentTextBudget = 6000;

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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_PendingAttachment> _pendingAttachments = [];
  var _mode = ChatConversationMode.vault;
  var _modelReady = false;
  var _asking = false;
  var _attaching = false;

  /// A qué cuaderno queda acotado el modo con la bóveda (F16, D1). `null`
  /// es "toda la bóveda". Solo tiene sentido en `ChatConversationMode.
  /// vault`; el modo libre lo ignora.
  String? _notebookId;

  String? _vaultConversationId;
  String? _freeConversationId;

  /// La sesión de la conversación libre en curso. Vive mientras dure la
  /// charla —no se abre y se cierra pregunta a pregunta—, para que el
  /// modelo tenga todo lo dicho antes como contexto.
  FreeConversation? _conversation;

  /// Lo mismo, para el modo con la bóveda.
  VaultConversation? _vaultConversation;

  String? get _currentConversationId => switch (_mode) {
    ChatConversationMode.vault => _vaultConversationId,
    ChatConversationMode.free => _freeConversationId,
  };

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    unawaited(_conversation?.close());
    unawaited(_vaultConversation?.close());
    super.dispose();
  }

  Future<void> _refreshModelStatus() async {
    final ready = await ref.read(chatModelManagerProvider).isReady();
    if (!mounted) return;
    setState(() => _modelReady = ready);
  }

  Future<void> _openModelScreen() async {
    await context.push(RoutePaths.chatModel);
    if (!mounted) return;
    unawaited(_refreshModelStatus());
  }

  void _changeMode(ChatConversationMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  /// Cambia a qué cuaderno queda acotado el modo con la bóveda. Si ya había
  /// una conversación con mensajes, arranca una nueva —el cuaderno de una
  /// conversación queda fijo desde que se crea, no cambia bajo lo ya dicho—,
  /// mismo criterio que [_newConversation].
  void _selectNotebook(String? notebookId) {
    if (notebookId == _notebookId) return;
    if (_vaultConversationId != null) {
      unawaited(_vaultConversation?.close());
      setState(() {
        _notebookId = notebookId;
        _vaultConversation = null;
        _vaultConversationId = null;
      });
    } else {
      setState(() => _notebookId = notebookId);
    }
  }

  /// Deja el modo activo listo para arrancar una conversación nueva y
  /// vacía, sin borrar ninguna de las guardadas: la próxima vez que se
  /// mande un mensaje, se crea una fila nueva en el historial.
  void _newConversation() {
    switch (_mode) {
      case ChatConversationMode.free:
        unawaited(_conversation?.close());
        setState(() {
          _conversation = null;
          _freeConversationId = null;
        });
      case ChatConversationMode.vault:
        unawaited(_vaultConversation?.close());
        setState(() {
          _vaultConversation = null;
          _vaultConversationId = null;
        });
    }
  }

  void _openConversation(ChatConversation conversation) {
    switch (conversation.mode) {
      case ChatConversationMode.free:
        unawaited(_conversation?.close());
        setState(() {
          _conversation = null;
          _freeConversationId = conversation.id;
        });
      case ChatConversationMode.vault:
        unawaited(_vaultConversation?.close());
        setState(() {
          _vaultConversation = null;
          _vaultConversationId = conversation.id;
          _notebookId = conversation.notebookId;
        });
    }
    Navigator.of(context).pop();
    _scrollToEnd();
  }

  Future<void> _deleteConversation(ChatConversation conversation) async {
    await ref
        .read(chatConversationRepositoryProvider)
        .deleteConversation(conversation.id);
    if (!mounted) return;
    if (conversation.id == _currentConversationId) {
      switch (conversation.mode) {
        case ChatConversationMode.free:
          unawaited(_conversation?.close());
          setState(() {
            _conversation = null;
            _freeConversationId = null;
          });
        case ChatConversationMode.vault:
          unawaited(_vaultConversation?.close());
          setState(() {
            _vaultConversation = null;
            _vaultConversationId = null;
          });
      }
    }
  }

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
  /// [FileFormat.sourceKind] quien decide si es una imagen o un documento.
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
      _setConversationId(mode, conversationId);
    }

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

    await repo.addMessage(answer);
    if (!mounted) return;
    setState(() => _asking = false);
    _scrollToEnd();
  }

  void _setConversationId(ChatConversationMode mode, String id) {
    switch (mode) {
      case ChatConversationMode.vault:
        _vaultConversationId = id;
      case ChatConversationMode.free:
        _freeConversationId = id;
    }
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

    final content = docs
        .map((doc) {
          final extracted = doc.extractedText!;
          final truncated = extracted.length > _kAttachmentTextBudget
              ? '${extracted.substring(0, _kAttachmentTextBudget)}…'
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
          .retrieve(query, scopeIds: scopeIds);

      var conversation = _vaultConversation;
      conversation ??= await ref
          .read(chatModelProvider)
          .startVaultConversation();
      _vaultConversation = conversation;

      final text = await conversation.send(
        message: promptText,
        sources: sources,
        images: images,
      );
      return PersistedChatMessage(
        id: id,
        conversationId: conversationId,
        isUser: false,
        text: text,
        sources: sources,
        createdAt: clock(),
      );
      // El motor de inferencia es de terceros (flutter_gemma); puede fallar
      // de formas que no tienen un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return PersistedChatMessage(
        id: id,
        conversationId: conversationId,
        isUser: false,
        text: '',
        createdAt: clock(),
        error: l10n.globalErrorUnexpected,
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
        error: l10n.chatFreeModelRequired,
      );
    }

    try {
      var conversation = _conversation;
      conversation ??= await ref.read(chatModelProvider).startConversation();
      _conversation = conversation;

      final answer = await conversation.send(promptText, images: images);
      return PersistedChatMessage(
        id: id,
        conversationId: conversationId,
        isUser: false,
        text: answer,
        createdAt: clock(),
      );
      // El motor de inferencia es de terceros (flutter_gemma); puede fallar
      // de formas que no tienen un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return PersistedChatMessage(
        id: id,
        conversationId: conversationId,
        isUser: false,
        text: '',
        createdAt: clock(),
        error: l10n.globalErrorUnexpected,
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
    final isFree = _mode == ChatConversationMode.free;
    final conversationId = _currentConversationId;

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _HistoryDrawer(
        mode: _mode,
        activeConversationId: conversationId,
        onSelect: _openConversation,
        onNew: () {
          _newConversation();
          Navigator.of(context).pop();
        },
        onDelete: _deleteConversation,
      ),
      appBar: AppBar(
        title: Text(l10n.chatTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.chatHistoryTooltip,
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          if (conversationId != null)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: l10n.chatNewConversationTooltip,
              onPressed: _newConversation,
            ),
          IconButton(
            icon: Icon(
              _modelReady ? Icons.smart_toy_outlined : Icons.download_outlined,
            ),
            tooltip: l10n.chatModelTooltip,
            onPressed: _openModelScreen,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isFree ? 48 : 88),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                Center(
                  child: SegmentedButton<ChatConversationMode>(
                    segments: [
                      ButtonSegment(
                        value: ChatConversationMode.vault,
                        label: Text(l10n.chatModeVault),
                        icon: const Icon(Icons.folder_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: ChatConversationMode.free,
                        label: Text(l10n.chatModeFree),
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) =>
                        _changeMode(selection.first),
                  ),
                ),
                if (!isFree)
                  _NotebookScopeSelector(
                    notebookId: _notebookId,
                    onChanged: _selectNotebook,
                  ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_modelReady)
              _ModelBanner(
                message: isFree
                    ? l10n.chatFreeModelRequired
                    : l10n.chatModelNotReadyBanner,
                actionLabel: l10n.chatModelDownloadAction,
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
                      asking: _asking,
                      scrollController: _scrollController,
                    ),
            ),
            if (_pendingAttachments.isNotEmpty)
              _AttachmentChips(
                attachments: _pendingAttachments,
                onRemove: _removeAttachment,
              ),
            _Composer(
              controller: _controller,
              enabled: !_asking,
              attaching: _attaching,
              onSend: _send,
              onAttach: _attaching ? null : _pickAttachmentKind,
            ),
          ],
        ),
      ),
    );
  }
}

/// A qué cuaderno acotar el modo con la bóveda (F16, D1). Solo se muestra en
/// ese modo —en el libre el concepto no aplica—. `null` es "toda la
/// bóveda", la primera opción de la lista.
class _NotebookScopeSelector extends ConsumerWidget {
  const _NotebookScopeSelector({required this.notebookId, this.onChanged});

  final String? notebookId;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? const [];
    // Si el cuaderno elegido se borró mientras tanto, el valor que muestra
    // el desplegable cae a "toda la bóveda" — no puede seguir mostrando un
    // valor que no está entre sus opciones sin que Flutter reviente.
    final shownValue = notebooks.any((n) => n.id == notebookId)
        ? notebookId
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          key: const Key('chat-notebook-scope'),
          isDense: true,
          isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          value: shownValue,
          items: [
            DropdownMenuItem(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text(l10n.chatNotebookScopeAll),
                ],
              ),
            ),
            for (final notebook in notebooks)
              DropdownMenuItem(
                value: notebook.id,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_stories_outlined, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        notebook.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _HistoryDrawer extends ConsumerWidget {
  const _HistoryDrawer({
    required this.mode,
    required this.activeConversationId,
    required this.onSelect,
    required this.onNew,
    required this.onDelete,
  });

  final ChatConversationMode mode;
  final String? activeConversationId;
  final ValueChanged<ChatConversation> onSelect;
  final VoidCallback onNew;
  final ValueChanged<ChatConversation> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final conversationsAsync = ref.watch(chatConversationsProvider(mode));

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.chatHistoryTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_comment_outlined),
                    tooltip: l10n.chatHistoryNewAction,
                    onPressed: onNew,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: conversationsAsync.when(
                data: (conversations) {
                  if (conversations.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.chatHistoryEmpty,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }
                  final locale = Localizations.localeOf(context).toString();
                  final dateFormat = DateFormat.MMMd(locale).add_Hm();

                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      final selected = conversation.id == activeConversationId;
                      return ListTile(
                        selected: selected,
                        leading: Icon(
                          mode == ChatConversationMode.vault
                              ? Icons.folder_outlined
                              : Icons.chat_bubble_outline,
                        ),
                        title: Text(
                          conversation.title ?? l10n.chatHistoryUntitled,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: _ConversationSubtitle(
                          conversation: conversation,
                          dateFormat: dateFormat,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l10n.chatHistoryDeleteTooltip,
                          onPressed: () =>
                              _confirmDelete(context, l10n, conversation),
                        ),
                        onTap: () => onSelect(conversation),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, stackTrace) =>
                    Center(child: Text(l10n.globalErrorUnexpected)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppLocalizations l10n,
    ChatConversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chatHistoryDeleteConfirmTitle),
        content: Text(l10n.chatHistoryDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.chatHistoryDeleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed ?? false) onDelete(conversation);
  }
}

/// La fecha de la conversación y, si quedó acotada a un cuaderno, su
/// nombre — para distinguir en el historial "Tesis" de "toda la bóveda"
/// sin tener que abrir cada una.
class _ConversationSubtitle extends ConsumerWidget {
  const _ConversationSubtitle({
    required this.conversation,
    required this.dateFormat,
  });

  final ChatConversation conversation;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = dateFormat.format(conversation.updatedAt);
    final notebookId = conversation.notebookId;
    if (notebookId == null) return Text(date);

    final notebook = ref.watch(notebookByIdProvider(notebookId)).valueOrNull;
    if (notebook == null) return Text(date);

    return Text('$date · ${notebook.name}');
  }
}

class _MessagesList extends ConsumerWidget {
  const _MessagesList({
    required this.conversationId,
    required this.mode,
    required this.asking,
    required this.scrollController,
  });

  final String conversationId;
  final ChatConversationMode mode;
  final bool asking;
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
        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length + (asking ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= messages.length) return const _TypingBubble();
            return _MessageBubble(message: messages[index]);
          },
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
    required this.actionLabel,
    required this.onDownload,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onDownload;

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
          TextButton(onPressed: onDownload, child: Text(actionLabel)),
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
                  child: Text(
                    message.text,
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
          if (error != null)
            Text(error, style: TextStyle(color: theme.colorScheme.error))
          else if (message.text.isNotEmpty) ...[
            Text(message.text, style: theme.textTheme.bodyLarge),
            if (message.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final source in message.sources) _SourceCard(source: source),
            ],
          ] else if (message.sources.isNotEmpty) ...[
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
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool attaching;
  final VoidCallback onSend;
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
          IconButton.filled(
            icon: const Icon(Icons.send),
            onPressed: enabled ? onSend : null,
          ),
        ],
      ),
    );
  }
}
