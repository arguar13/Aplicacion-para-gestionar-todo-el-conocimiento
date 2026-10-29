import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';

/// Lo medido de un modelo en este teléfono («Medir en mi teléfono»): cuánto
/// tardó en dibujar una imagen de 512 px y, si la cargó, en cargarse.
@immutable
class OnDeviceMeasurement {
  const OnDeviceMeasurement({
    required this.perImage,
    required this.measuredAt,
    this.load,
  });

  static OnDeviceMeasurement? fromJson(Object? json) {
    if (json is! Map) return null;
    final ms = json['perImageMs'];
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (ms is! int || ms <= 0 || at == null) return null;
    final load = json['loadMs'];
    return OnDeviceMeasurement(
      perImage: Duration(milliseconds: ms),
      load: load is int && load > 0 ? Duration(milliseconds: load) : null,
      measuredAt: at.toUtc(),
    );
  }

  final Duration perImage;

  /// Lo que tarda en cargarse, la primera imagen de una tanda.
  final Duration? load;
  final DateTime measuredAt;

  Map<String, Object> toJson() => {
    'perImageMs': perImage.inMilliseconds,
    if (load != null) 'loadMs': load!.inMilliseconds,
    'at': measuredAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is OnDeviceMeasurement &&
      other.perImage == perImage &&
      other.load == load &&
      other.measuredAt == measuredAt;

  @override
  int get hashCode => Object.hash(perImage, load, measuredAt);
}

/// Lo que se recuerda del modelo del teléfono (F43, «Exigente»), en las
/// preferencias del teléfono —es del teléfono, no de la bóveda—:
///
/// - **lo medido** de cada modelo;
/// - **la marca de «dibujando»**: se pone antes de dibujar y se saca al
///   terminar. Si la app arranca y la encuentra puesta, la app se cerró
///   mientras dibujaba —casi seguro, Android la cerró por falta de memoria—,
///   y ese modelo queda **apagado** ([closedOf]) hasta que la persona lo
///   vuelva a probar.
class PrefsOnDeviceImageStore {
  PrefsOnDeviceImageStore({required SharedPreferences prefs}) : _prefs = prefs;

  static String _measureKey(OnDeviceImageModel model) =>
      'ai_device_image_measure_${model.spec.id}';
  static String _closedKey(OnDeviceImageModel model) =>
      'ai_device_image_closed_${model.spec.id}';
  static const _drawingKey = 'ai_device_image_drawing';

  final SharedPreferences _prefs;
  final _changes = StreamController<void>.broadcast();

  Stream<void> changes() => _changes.stream;

  OnDeviceMeasurement? measurementOf(OnDeviceImageModel model) {
    final raw = _prefs.getString(_measureKey(model));
    if (raw == null) return null;
    try {
      return OnDeviceMeasurement.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> setMeasurement(
    OnDeviceImageModel model,
    OnDeviceMeasurement measurement,
  ) async {
    await _prefs.setString(
      _measureKey(model),
      jsonEncode(measurement.toJson()),
    );
    _changes.add(null);
  }

  /// Cuándo se cerró la app dibujando con [model] por última vez, si quedó
  /// apagado por eso.
  DateTime? closedOf(OnDeviceImageModel model) =>
      DateTime.tryParse(_prefs.getString(_closedKey(model)) ?? '')?.toUtc();

  /// Lo apaga: se quedó sin memoria dibujando con [model] (el motor lo dijo
  /// sin que se cerrara la app).
  Future<void> markClosed(OnDeviceImageModel model, DateTime at) async {
    await _prefs.setString(_closedKey(model), at.toUtc().toIso8601String());
    _changes.add(null);
  }

  /// «Volver a intentar»: lo enciende de nuevo.
  Future<void> clearClosed(OnDeviceImageModel model) async {
    await _prefs.remove(_closedKey(model));
    _changes.add(null);
  }

  /// Antes de dibujar con [model].
  Future<void> markDrawing(OnDeviceImageModel model, DateTime at) =>
      _prefs.setString(
        _drawingKey,
        jsonEncode({
          'model': model.spec.id,
          'at': at.toUtc().toIso8601String(),
        }),
      );

  /// Terminó de dibujar, bien o mal, sin que se cerrara la app.
  Future<void> clearDrawing() => _prefs.remove(_drawingKey);

  /// Al arrancar: si quedó la marca de «dibujando», el modelo que dibujaba
  /// queda apagado. Devuelve cuál, o `null`.
  Future<OnDeviceImageModel?> recoverFromClosedDrawing() async {
    final raw = _prefs.getString(_drawingKey);
    if (raw == null) return null;
    await _prefs.remove(_drawingKey);
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final model = OnDeviceImageModel.byId(json['model'] as String?);
    final at = json['at'];
    if (model == null || at is! String) return null;
    await _prefs.setString(_closedKey(model), at);
    _changes.add(null);
    return model;
  }

  Future<void> dispose() => _changes.close();
}
