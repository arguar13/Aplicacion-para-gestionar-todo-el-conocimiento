import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:sinapsis/features/ai_models/data/on_device/stable_diffusion_runtime.dart';

/// La versión de la puerta (`SINAPSIS_SD_ABI` en `sinapsis_sd.h`) con que se
/// escribió este lado. Si la biblioteca dice otra, no se usa.
const kSinapsisSdAbi = 1;

/// El nombre de la biblioteca que arma `android/app/src/main/cpp`.
const kSinapsisSdLibrary = 'libsinapsis_sd.so';

// Los códigos de `sinapsis_sd.h` que se distinguen; los demás (no cargó, no
// dibujó) son una falla de dibujo con su código en el detalle.
const _ok = 0;
const _errCancelled = 3;
const _errMemory = 4;
const _errArgs = 5;

typedef _GenerateDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      int,
      int,
      int,
      double,
      int,
      Pointer<Pointer<Uint8>>,
      Pointer<Int32>,
      Pointer<Int32>,
    );
typedef _ContextNative = Void Function(Pointer<Void>);
typedef _ContextDart = void Function(Pointer<Void>);

/// Las funciones de `libsinapsis_sd.so`, a mano y no generadas: son pocas,
/// con tipos simples, y la forma de las estructuras de stable-diffusion.cpp
/// queda del lado de C++ (ver `sinapsis_sd.h`).
class SdNativeLibrary {
  SdNativeLibrary._(DynamicLibrary library)
    : _abi = library.lookupFunction<Int32 Function(), int Function()>(
        'sinapsis_sd_abi',
      ),
      _load = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>, Int32, Pointer<Int32>),
            Pointer<Void> Function(Pointer<Utf8>, int, Pointer<Int32>)
          >('sinapsis_sd_load'),
      _generate = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Int32,
              Int32,
              Int32,
              Float,
              Int64,
              Pointer<Pointer<Uint8>>,
              Pointer<Int32>,
              Pointer<Int32>,
            ),
            _GenerateDart
          >('sinapsis_sd_generate'),
      _freePixels = library
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('sinapsis_sd_free_pixels'),
      _cancel = library.lookupFunction<_ContextNative, _ContextDart>(
        'sinapsis_sd_cancel',
      ),
      _free = library.lookupFunction<_ContextNative, _ContextDart>(
        'sinapsis_sd_free',
      );

  /// La biblioteca, si la app la trae y es de esta versión; `null` si no
  /// (se armó sin `-Psinapsis.imagenesEnElTelefono=true`, o no es Android de
  /// 64 bits).
  static SdNativeLibrary? open() {
    try {
      final library = SdNativeLibrary._(
        DynamicLibrary.open(kSinapsisSdLibrary),
      );
      return library._abi() == kSinapsisSdAbi ? library : null;
      // `DynamicLibrary.open` y `lookupFunction` dicen «no está» con un
      // `ArgumentError`: la app se armó sin el motor, o con otro.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return null;
    }
  }

  final int Function() _abi;
  final Pointer<Void> Function(Pointer<Utf8>, int, Pointer<Int32>) _load;
  final _GenerateDart _generate;
  final void Function(Pointer<Uint8>) _freePixels;
  final _ContextDart _cancel;
  final _ContextDart _free;

  /// Ver `sinapsis_sd_load`.
  Pointer<Void> load(Pointer<Utf8> path, int threads, Pointer<Int32> error) =>
      _load(path, threads, error);

  /// Ver `sinapsis_sd_generate`.
  int generate(
    Pointer<Void> context,
    Pointer<Utf8> prompt,
    int width,
    int height,
    int steps,
    double cfg,
    int seed,
    Pointer<Pointer<Uint8>> pixels,
    Pointer<Int32> outWidth,
    Pointer<Int32> outHeight,
  ) => _generate(
    context,
    prompt,
    width,
    height,
    steps,
    cfg,
    seed,
    pixels,
    outWidth,
    outHeight,
  );

  void freePixels(Pointer<Uint8> pixels) => _freePixels(pixels);

  /// Desde cualquier isolate, mientras otro dibuja.
  void cancel(Pointer<Void> context) => _cancel(context);

  void free(Pointer<Void> context) => _free(context);
}

/// [StableDiffusionRuntime] sobre `libsinapsis_sd.so`, en un isolate propio
/// que vive mientras haga falta: carga el modelo una vez y dibuja las
/// imágenes de una creación sin volver a cargarlo.
///
/// Cancelar se hace desde este isolate, directo sobre la memoria del
/// contexto (el isolate que dibuja está ocupado dentro de C++ y no lee
/// mensajes hasta terminar): por eso el que dibuja avisa la dirección del
/// contexto apenas lo carga.
class IsolateStableDiffusionRuntime implements StableDiffusionRuntime {
  IsolateStableDiffusionRuntime(this._library);

  final SdNativeLibrary _library;

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _replies;
  final _pending = <int, Completer<_Reply>>{};
  var _nextId = 0;

  /// La dirección del contexto cargado, para cancelar; 0 sin modelo.
  var _context = 0;
  var _drawing = false;

  /// De a uno: lo que llega mientras dibuja espera su turno.
  Future<void> _turn = Future.value();

  @override
  bool get isLoaded => _context != 0;

  Future<SendPort> _worker() async {
    if (_commands case final commands?) return commands;
    final replies = ReceivePort();
    _replies = replies;
    final ready = Completer<SendPort>();
    replies.listen((Object? message) {
      switch (message) {
        case final SendPort port:
          ready.complete(port);
        case _Loaded(:final address):
          _context = address;
        case final _Reply reply:
          _pending.remove(reply.id)?.complete(reply);
      }
    });
    _isolate = await Isolate.spawn(
      _workerMain,
      replies.sendPort,
      debugName: 'stable-diffusion',
    );
    return _commands = await ready.future;
  }

  Future<_Reply> _send(_Command Function(int id) command) async {
    final port = await _worker();
    final id = _nextId++;
    final done = Completer<_Reply>();
    _pending[id] = done;
    port.send(command(id));
    return done.future;
  }

  Future<T> _inTurn<T>(Future<T> Function() work) {
    final result = _turn.then((_) => work());
    _turn = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<StableDiffusionImage> generate(StableDiffusionJob job) =>
      _inTurn(() async {
        _drawing = true;
        final _Reply reply;
        try {
          reply = await _send((id) => _Generate(id, job));
        } finally {
          _drawing = false;
        }
        if (reply case _Drawn(
          :final png,
          :final width,
          :final height,
          :final drawMicros,
          :final loadMicros,
        )) {
          return StableDiffusionImage(
            png: png.materialize().asUint8List(),
            width: width,
            height: height,
            drawTime: Duration(microseconds: drawMicros),
            loadTime: loadMicros == null
                ? null
                : Duration(microseconds: loadMicros),
          );
        }
        final failed = reply as _Failed;
        throw StableDiffusionException(failed.failure, failed.detail);
      });

  @override
  Future<void> cancel() async {
    final context = _context;
    if (!_drawing || context == 0) return;
    _library.cancel(Pointer<Void>.fromAddress(context));
  }

  @override
  Future<void> release() => _inTurn(() async {
    if (_commands == null) return;
    await _send(_Release.new);
    _context = 0;
  });

  /// Suelta el modelo y cierra el isolate.
  Future<void> dispose() async {
    await release();
    _isolate?.kill();
    _replies?.close();
    _isolate = null;
    _commands = null;
  }
}

// ── El isolate que dibuja ──────────────────────────────────────────────────

sealed class _Command {
  const _Command(this.id);

  final int id;
}

final class _Generate extends _Command {
  const _Generate(super.id, this.job);

  final StableDiffusionJob job;
}

final class _Release extends _Command {
  const _Release(super.id);
}

final class _Loaded {
  const _Loaded(this.address);

  final int address;
}

sealed class _Reply {
  const _Reply(this.id);

  final int id;
}

final class _Drawn extends _Reply {
  const _Drawn(
    super.id, {
    required this.png,
    required this.width,
    required this.height,
    required this.drawMicros,
    this.loadMicros,
  });

  final TransferableTypedData png;
  final int width;
  final int height;
  final int drawMicros;
  final int? loadMicros;
}

final class _Failed extends _Reply {
  const _Failed(super.id, this.failure, [this.detail]);

  final StableDiffusionFailure failure;
  final String? detail;
}

final class _Released extends _Reply {
  const _Released(super.id);
}

void _workerMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  final library = SdNativeLibrary.open();
  var context = nullptr.cast<Void>();
  String? loadedPath;

  void releaseModel() {
    if (context != nullptr) library?.free(context);
    context = nullptr.cast<Void>();
    loadedPath = null;
    replies.send(const _Loaded(0));
  }

  commands.listen((Object? message) {
    switch (message) {
      case _Release(:final id):
        releaseModel();
        replies.send(_Released(id));
      case _Generate(:final id, :final job):
        if (library == null) {
          replies.send(_Failed(id, StableDiffusionFailure.unavailable));
          return;
        }
        int? loadMicros;
        if (loadedPath != job.modelPath) {
          releaseModel();
          final watch = Stopwatch()..start();
          final path = job.modelPath.toNativeUtf8();
          final error = calloc<Int32>();
          try {
            context = library.load(path, job.threads, error);
            if (context == nullptr) {
              replies.send(
                _Failed(
                  id,
                  error.value == _errMemory
                      ? StableDiffusionFailure.memory
                      : StableDiffusionFailure.load,
                ),
              );
              return;
            }
          } finally {
            calloc
              ..free(path)
              ..free(error);
          }
          loadMicros = watch.elapsedMicroseconds;
          loadedPath = job.modelPath;
          replies.send(_Loaded(context.address));
        }
        replies.send(_draw(library, context, id, job, loadMicros));
    }
  });
}

_Reply _draw(
  SdNativeLibrary library,
  Pointer<Void> context,
  int id,
  StableDiffusionJob job,
  int? loadMicros,
) {
  final prompt = job.prompt.toNativeUtf8();
  final pixels = calloc<Pointer<Uint8>>();
  final width = calloc<Int32>();
  final height = calloc<Int32>();
  try {
    final watch = Stopwatch()..start();
    final code = library.generate(
      context,
      prompt,
      job.width,
      job.height,
      job.steps,
      job.cfg,
      job.seed,
      pixels,
      width,
      height,
    );
    final drawMicros = watch.elapsedMicroseconds;
    final failure = switch (code) {
      _ok => null,
      _errCancelled => StableDiffusionFailure.cancelled,
      _errMemory => StableDiffusionFailure.memory,
      _errArgs => StableDiffusionFailure.arguments,
      _ => StableDiffusionFailure.generate,
    };
    if (failure != null) return _Failed(id, failure, 'código $code');
    final w = width.value;
    final h = height.value;
    final rgb = pixels.value.asTypedList(w * h * 3);
    // A PNG acá mismo, fuera del isolate de la pantalla.
    final png = img.encodePng(
      img.Image.fromBytes(
        width: w,
        height: h,
        bytes: Uint8List.fromList(rgb).buffer,
        numChannels: 3,
      ),
    );
    library.freePixels(pixels.value);
    return _Drawn(
      id,
      png: TransferableTypedData.fromList([png]),
      width: w,
      height: h,
      drawMicros: drawMicros,
      loadMicros: loadMicros,
    );
  } finally {
    calloc
      ..free(prompt)
      ..free(pixels)
      ..free(width)
      ..free(height);
  }
}
