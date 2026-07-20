import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  // Texto ya finalizado por el motor (segmentos completos)
  String _accumulatedWords = '';
  // Texto del segmento actual, todavía no finalizado por el motor,
  // pero ya visible en pantalla vía el callback parcial
  String _currentPartial = '';

  String get lastWords => _currentFullText;

  String get _currentFullText {
    if (_currentPartial.isEmpty) return _accumulatedWords;
    return _accumulatedWords.isEmpty
        ? _currentPartial
        : '$_accumulatedWords $_currentPartial';
  }

  Function(String)? _onResultCallback;
  Function(String)? _onPartialCallback;
  Function(String)? _onErrorCallback;

  bool _isStoppingManually = false;
  bool _restartScheduled = false;
  bool _listenStarting = false;
  String? _activeLocale;
  Timer? _silenceTimer;

  static const _silenceTimeout = Duration(seconds: 10);

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (error) {
        print('STT Error: ${error.errorMsg}');

        const transient = [
          'error_no_match',
          'error_client',
          'error_speech_timeout',
        ];

        if (_isStoppingManually || transient.contains(error.errorMsg)) return;

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

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceTimeout, () {
      print('STT: 10s de silencio — procesando automáticamente');
      _finalize();
    });
  }

  void _finalize() {
    _silenceTimer?.cancel();
    _isStoppingManually = true;
    _restartScheduled = false;
    _speech.cancel();
    final words = _currentFullText;
    _accumulatedWords = '';
    _currentPartial = '';
    final callback = _onResultCallback;
    _onResultCallback = null;
    _onPartialCallback = null;
    _onErrorCallback = null;
    callback?.call(words);
  }

  Future<void> _doListen() async {
  if (_isStoppingManually || _onResultCallback == null) return;
  if (_listenStarting || _speech.isListening) return;
  _restartScheduled = false;
  _listenStarting = true;
  try {
    await _speech.listen(
      onResult: _onSTTResult,
      listenOptions: SpeechListenOptions(
        cancelOnError: false,
        partialResults: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 30),
        localeId: _activeLocale,
      ),
    );
  } catch (e) {
    print('STT: error en listen: $e');
  } finally {
    _listenStarting = false;
  }
}

  void _onSTTResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords;
    print('STT result: "$words" final=${result.finalResult}');

    if (result.finalResult && words.isNotEmpty) {
      _accumulatedWords = _accumulatedWords.isEmpty
          ? words
          : '$_accumulatedWords $words';
      _currentPartial = '';
      print('STT acumulado: "$_accumulatedWords"');

      _resetSilenceTimer();
      _onPartialCallback?.call(_accumulatedWords);

      _restartScheduled = true;
      Future.delayed(const Duration(milliseconds: 150), _doListen);
    } else if (!result.finalResult && words.isNotEmpty) {
      _resetSilenceTimer();
      _currentPartial = words;
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
    _currentPartial = '';
    _onResultCallback = onResult;
    _onPartialCallback = onPartial;
    _onErrorCallback = onError;
    _isStoppingManually = false;
    _restartScheduled = false;
    _silenceTimer?.cancel();

    await Future.delayed(const Duration(milliseconds: 300));

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

    _activeLocale = bestLocale?.replaceAll('_', '-');
    print('Locale: $bestLocale → $_activeLocale');

    _resetSilenceTimer();

    await _doListen();
  }

  /// El usuario tocó el botón stop.
  /// Devuelve el texto acumulado + lo que se estaba diciendo en ese momento,
  /// sin depender de que el motor confirme un resultado final.
  Future<String> stopListening() async {
    _silenceTimer?.cancel();
    _isStoppingManually = true;
    _restartScheduled = false;

    final words = _currentFullText;

    await _speech.stop();

    _accumulatedWords = '';
    _currentPartial = '';
    _onResultCallback = null;
    _onPartialCallback = null;
    _onErrorCallback = null;
    return words;
  }

  Future<void> cancel() async {
    _silenceTimer?.cancel();
    _isStoppingManually = true;
    _restartScheduled = false;
    await _speech.cancel();
    _accumulatedWords = '';
    _currentPartial = '';
    _onResultCallback = null;
    _onPartialCallback = null;
    _onErrorCallback = null;
  }

  Future<List<LocaleName>> getAvailableLocales() async {
    if (!_initialized) await initialize();
    return await _speech.locales();
  }
}