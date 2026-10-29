import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// GStreamer & GObject C Signatures
typedef _GstInitC = Void Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);
typedef _GstInitDart = void Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);

typedef _GstElementFactoryMakeC = Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _GstElementFactoryMakeDart = Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _GstElementSetStateC = Int32 Function(Pointer<Void>, Int32);
typedef _GstElementSetStateDart = int Function(Pointer<Void>, int);

typedef _GObjectSetStringC = Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>);
typedef _GObjectSetStringDart = void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>);

typedef _GObjectSetDoubleC = Void Function(Pointer<Void>, Pointer<Utf8>, Double, Pointer<Void>);
typedef _GObjectSetDoubleDart = void Function(Pointer<Void>, Pointer<Utf8>, double, Pointer<Void>);

typedef _GstElementQueryPositionC = Int32 Function(Pointer<Void>, Int32, Pointer<Int64>);
typedef _GstElementQueryPositionDart = int Function(Pointer<Void>, int, Pointer<Int64>);

typedef _GstElementQueryDurationC = Int32 Function(Pointer<Void>, Int32, Pointer<Int64>);
typedef _GstElementQueryDurationDart = int Function(Pointer<Void>, int, Pointer<Int64>);

typedef _GstElementSeekSimpleC = Int32 Function(Pointer<Void>, Int32, Int32, Int64);
typedef _GstElementSeekSimpleDart = int Function(Pointer<Void>, int, int, int);

typedef _GstElementGetBusC = Pointer<Void> Function(Pointer<Void>);
typedef _GstElementGetBusDart = Pointer<Void> Function(Pointer<Void>);

typedef _GstBusPopFilteredC = Pointer<Void> Function(Pointer<Void>, Int32);
typedef _GstBusPopFilteredDart = Pointer<Void> Function(Pointer<Void>, int);

typedef _GstMessageUnrefC = Void Function(Pointer<Void>);
typedef _GstMessageUnrefDart = void Function(Pointer<Void>);

typedef _GstObjectUnrefC = Void Function(Pointer<Void>);
typedef _GstObjectUnrefDart = void Function(Pointer<Void>);

/// Player de áudio nativo para Linux usando GStreamer playbin via FFI
/// Não requer nenhuma dependência externa e funciona nativamente no Ubuntu/Debian/Arch/Fedora
class LinuxGstPlayer {
  static bool _gstInitialized = false;

  late final DynamicLibrary _gstLib;
  late final DynamicLibrary _gobjectLib;

  late final _GstInitDart _gstInit;
  late final _GstElementFactoryMakeDart _gstElementFactoryMake;
  late final _GstElementSetStateDart _gstElementSetState;
  late final _GObjectSetStringDart _gObjectSetString;
  late final _GObjectSetDoubleDart _gObjectSetDouble;
  late final _GstElementQueryPositionDart _gstElementQueryPosition;
  late final _GstElementQueryDurationDart _gstElementQueryDuration;
  late final _GstElementSeekSimpleDart _gstElementSeekSimple;
  late final _GstElementGetBusDart _gstElementGetBus;
  late final _GstBusPopFilteredDart _gstBusPopFiltered;
  late final _GstMessageUnrefDart _gstMessageUnref;
  late final _GstObjectUnrefDart _gstObjectUnref;

  Pointer<Void>? _pipeline;
  Pointer<Int64>? _posPtr;
  Pointer<Int64>? _durPtr;

  Timer? _pollingTimer;

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  double _volume = 1.0;

  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController = StreamController<Duration>.broadcast();
  final StreamController<bool> _isPlayingController = StreamController<bool>.broadcast();

  VoidCallback? onCompleted;

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  bool get isPlaying => _isPlaying;
  Duration get position => _currentPosition;
  Duration get duration => _currentDuration;
  double get volume => _volume;

  LinuxGstPlayer() {
    _initFfi();
  }

  void _initFfi() {
    try {
      _gstLib = DynamicLibrary.open('libgstreamer-1.0.so.0');
      _gobjectLib = DynamicLibrary.open('libgobject-2.0.so.0');

      _gstInit = _gstLib.lookupFunction<_GstInitC, _GstInitDart>('gst_init');
      _gstElementFactoryMake = _gstLib.lookupFunction<_GstElementFactoryMakeC, _GstElementFactoryMakeDart>('gst_element_factory_make');
      _gstElementSetState = _gstLib.lookupFunction<_GstElementSetStateC, _GstElementSetStateDart>('gst_element_set_state');
      _gObjectSetString = _gobjectLib.lookupFunction<_GObjectSetStringC, _GObjectSetStringDart>('g_object_set');
      _gObjectSetDouble = _gobjectLib.lookupFunction<_GObjectSetDoubleC, _GObjectSetDoubleDart>('g_object_set');
      _gstElementQueryPosition = _gstLib.lookupFunction<_GstElementQueryPositionC, _GstElementQueryPositionDart>('gst_element_query_position');
      _gstElementQueryDuration = _gstLib.lookupFunction<_GstElementQueryDurationC, _GstElementQueryDurationDart>('gst_element_query_duration');
      _gstElementSeekSimple = _gstLib.lookupFunction<_GstElementSeekSimpleC, _GstElementSeekSimpleDart>('gst_element_seek_simple');
      _gstElementGetBus = _gstLib.lookupFunction<_GstElementGetBusC, _GstElementGetBusDart>('gst_element_get_bus');
      _gstBusPopFiltered = _gstLib.lookupFunction<_GstBusPopFilteredC, _GstBusPopFilteredDart>('gst_bus_pop_filtered');
      _gstMessageUnref = _gstLib.lookupFunction<_GstMessageUnrefC, _GstMessageUnrefDart>('gst_message_unref');
      _gstObjectUnref = _gstLib.lookupFunction<_GstObjectUnrefC, _GstObjectUnrefDart>('gst_object_unref');

      if (!_gstInitialized) {
        _gstInit(nullptr, nullptr);
        _gstInitialized = true;
      }

      _posPtr = calloc<Int64>();
      _durPtr = calloc<Int64>();
    } catch (e) {
      debugPrint('Erro ao inicializar GStreamer FFI: $e');
    }
  }

  Future<void> setUrl(String url) async {
    stop();

    try {
      final playbinStr = 'playbin'.toNativeUtf8();
      final nameStr = 'daplayer_gst'.toNativeUtf8();
      _pipeline = _gstElementFactoryMake(playbinStr, nameStr);
      calloc.free(playbinStr);
      calloc.free(nameStr);

      if (_pipeline == null || _pipeline == nullptr) {
        debugPrint('Falha ao instanciar playbin GStreamer.');
        return;
      }

      final uriProp = 'uri'.toNativeUtf8();
      final uriVal = url.toNativeUtf8();
      _gObjectSetString(_pipeline!, uriProp, uriVal, nullptr);
      calloc.free(uriProp);
      calloc.free(uriVal);

      setVolume(_volume);
    } catch (e) {
      debugPrint('Erro ao carregar URL no GStreamer: $e');
    }
  }

  Future<void> play() async {
    if (_pipeline == null || _pipeline == nullptr) return;

    // GST_STATE_PLAYING = 4
    _gstElementSetState(_pipeline!, 4);
    _isPlaying = true;
    _isPlayingController.add(true);

    _startPolling();
  }

  Future<void> pause() async {
    if (_pipeline == null || _pipeline == nullptr) return;

    // GST_STATE_PAUSED = 3
    _gstElementSetState(_pipeline!, 3);
    _isPlaying = false;
    _isPlayingController.add(false);

    _stopPolling();
  }

  Future<void> stop() async {
    _stopPolling();

    if (_pipeline != null && _pipeline != nullptr) {
      // GST_STATE_NULL = 1
      _gstElementSetState(_pipeline!, 1);
      _gstObjectUnref(_pipeline!);
      _pipeline = null;
    }

    _isPlaying = false;
    _currentPosition = Duration.zero;
    _positionController.add(Duration.zero);
    _isPlayingController.add(false);
  }

  Future<void> seek(Duration position) async {
    if (_pipeline == null || _pipeline == nullptr) return;

    final ns = position.inMicroseconds * 1000;
    // GST_FORMAT_TIME = 3, flags: GST_SEEK_FLAG_FLUSH(1) | GST_SEEK_FLAG_KEY_UNIT(4) = 5
    _gstElementSeekSimple(_pipeline!, 3, 5, ns);
    _currentPosition = position;
    _positionController.add(position);
  }

  Future<void> setVolume(double vol) async {
    _volume = vol.clamp(0.0, 1.0);
    if (_pipeline != null && _pipeline != nullptr) {
      final volProp = 'volume'.toNativeUtf8();
      _gObjectSetDouble(_pipeline!, volProp, _volume, nullptr);
      calloc.free(volProp);
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _pollGstStatus();
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _pollGstStatus() {
    if (_pipeline == null || _pipeline == nullptr || !_isPlaying) return;

    // 1. Atualiza Duração
    if (_durPtr != null) {
      final durRes = _gstElementQueryDuration(_pipeline!, 3, _durPtr!);
      if (durRes != 0 && _durPtr!.value > 0) {
        final durMs = _durPtr!.value ~/ 1000000;
        final newDur = Duration(milliseconds: durMs);
        if (newDur != _currentDuration) {
          _currentDuration = newDur;
          _durationController.add(_currentDuration);
        }
      }
    }

    // 2. Atualiza Posição
    if (_posPtr != null) {
      final posRes = _gstElementQueryPosition(_pipeline!, 3, _posPtr!);
      if (posRes != 0 && _posPtr!.value >= 0) {
        final posMs = _posPtr!.value ~/ 1000000;
        _currentPosition = Duration(milliseconds: posMs);
        _positionController.add(_currentPosition);
      }
    }

    // 3. Verifica se a faixa terminou (EOS - End of Stream)
    final bus = _gstElementGetBus(_pipeline!);
    if (bus != nullptr) {
      // GST_MESSAGE_EOS = 1, GST_MESSAGE_ERROR = 2
      final msg = _gstBusPopFiltered(bus, 1 | 2);
      if (msg != nullptr) {
        _gstMessageUnref(msg);
        _stopPolling();
        _isPlaying = false;
        _isPlayingController.add(false);
        onCompleted?.call();
      }
      _gstObjectUnref(bus);
    }
  }

  void dispose() {
    stop();
    if (_posPtr != null) calloc.free(_posPtr!);
    if (_durPtr != null) calloc.free(_durPtr!);
    _positionController.close();
    _durationController.close();
    _isPlayingController.close();
  }
}
