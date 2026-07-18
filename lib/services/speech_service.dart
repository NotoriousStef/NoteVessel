import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  // Texto acumulado de todos los segmentos de esta sesión
  String _accumulatedWords = '';
  String get lastWords => _accumulatedWords;

  Function(String)? _onResultCallback;
  Function(String)? _onPartialCallback;
  Function(String)? _onErrorCallback;

  bool _isStoppingManually = false;
  bool _restartScheduled = false;
  String? _activeLocale;
  Timer? _silenceTimer;

  static const _silenceTimeout = Duration(seconds: 10);

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (error) {
        print('STT Error: ${error.errorMsg}');

        // Errores transitorios: ignorar y dejar que onStatus maneje el reinicio
        const transient = [
          'error_no_match',
          'error_client',
          'error_speech_timeout',
        ];

        if (_isStoppingManually || transient.contains(error.errorMsg)) return;

        // Error real y fatal: parar todo antes de propagar
        // así el servicio no queda en estado inconsistente
        _silenceTimer?.cancel();
        _isStoppingManually = true;
        _restartScheduled = false;
        final callback = _onErrorCallback;
        _onResultCallback = null;
        _onPartialCallback = null;
        _onErrorCallback = null;
        callback?.call(error.errorMsg);
      },
      onStatus: (status) {
        print('STT Status: $status');
        // Android paró sin resultado → reiniciar si el usuario no tocó stop
        if ((status == 'notListening' || status == 'done') &&
            !_isStoppingManually &&
            !_restartScheduled) {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (!_isStoppingManually &&
                _onResultCallback != null &&
                !_restartScheduled) {
              _doListen();
            }
          });
        }
      },
    );
    return _initialized;
  }

  // Timer de silencio: se resetea cada vez que el usuario habla.
  // Si pasan 10s sin voz, procesa automáticamente.
  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceTimeout, () {
      print('STT: 10s de silencio — procesando automáticamente');
      _finalize();
    });
  }

  // Finaliza la sesión y dispara el resultado
  void _finalize() {
    _silenceTimer?.cancel();
    _isStoppingManually = true;
    _restartScheduled = false;
    _speech.cancel();
    final words = _accumulatedWords;
    _accumulatedWords = '';
    final callback = _onResultCallback;
    _onResultCallback = null;
    _onPartialCallback = null;
    _onErrorCallback = null;
    callback?.call(words); // Llamar siempre, incluso con string vacío
  }

  // Inicia (o reinicia) una sesión de escucha
  Future<void> _doListen() async {
    if (_isStoppingManually || _onResultCallback == null) return;
    _restartScheduled = false;
    try {
      await _speech.listen(
        onResult: _onSTTResult,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 30),
        localeId: _activeLocale,
        listenOptions: SpeechListenOptions(
          cancelOnError: false,
          partialResults: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      print('STT: error en listen: $e');
    }
  }

  void _onSTTResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords;
    print('STT result: "$words" final=${result.finalResult}');

    if (result.finalResult && words.isNotEmpty) {
      // Acumular segmento
      _accumulatedWords = _accumulatedWords.isEmpty
          ? words
          : '$_accumulatedWords $words';
      print('STT acumulado: "$_accumulatedWords"');

      // Resetear timer — el usuario habló, dar 10s más
      _resetSilenceTimer();

      // Mostrar texto acumulado en la UI
      _onPartialCallback?.call(_accumulatedWords);

      // Reiniciar escucha para el próximo segmento
      _restartScheduled = true;
      Future.delayed(const Duration(milliseconds: 150), _doListen);
    } else if (!result.finalResult && words.isNotEmpty) {
      // Parcial: mostrar acumulado + lo que está diciendo ahora
      final display = _accumulatedWords.isEmpty
          ? words
          : '$_accumulatedWords $words';
      _onPartialCallback?.call(display);
    }
  }

  bool get isListening => _speech.isListening;
  bool get isAvailable => _initialized;

  Future<void> startListening({
    required Function(String text) onResult,
    required Function(String partial) onPartial,
    required Function(String error) onError,
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) {
        onError('No se pudo inicializar el micrófono');
        return;
      }
    }

    _accumulatedWords = '';
    _onResultCallback = onResult;
    _onPartialCallback = onPartial;
    _onErrorCallback = onError;
    _isStoppingManually = false;
    _restartScheduled = false;
    _silenceTimer?.cancel();

    await Future.delayed(const Duration(milliseconds: 300));

    // Detectar locale español
    final locales = await _speech.locales();
    String? bestLocale;
    for (final preferred in ['es_US', 'es_ES', 'es_AR', 'es_MX', 'es_BO']) {
      if (locales.any((l) => l.localeId == preferred)) {
        bestLocale = preferred;
        break;
      }
    }
    bestLocale ??=
        locales.where((l) => l.localeId.startsWith('es')).firstOrNull?.localeId;

    // Android necesita el locale con guión (es-US) no guión bajo (es_US)
    _activeLocale = bestLocale?.replaceAll('_', '-');
    print('Locale: $bestLocale → $_activeLocale');

    // Iniciar timer de silencio desde el principio
    _resetSilenceTimer();

    await _doListen();
  }

  /// El usuario tocó el botón stop
  Future<void> stopListening() async {
    _silenceTimer?.cancel();
    _isStoppingManually = true;
    _restartScheduled = false;
    await _speech.cancel();
    // NO limpiar _accumulatedWords — home_screen lo lee via lastWords
    _onResultCallback = null;
    _onPartialCallback = null;
    _onErrorCallback = null;
  }

  Future<void> cancel() async {
    _silenceTimer?.cancel();
    _isStoppingManually = true;
    _restartScheduled = false;
    await _speech.cancel();
    _accumulatedWords = '';
    _onResultCallback = null;
    _onPartialCallback = null;
    _onErrorCallback = null;
  }

  Future<List<LocaleName>> getAvailableLocales() async {
    if (!_initialized) await initialize();
    return await _speech.locales();
  }
}
