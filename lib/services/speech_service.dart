import 'package:speech_to_text/speech_to_text.dart';

enum SpeechState { idle, listening, processing, done, error }

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  String _lastWords = '';
  String get lastWords => _lastWords;

  /// Inicializa el reconocimiento de voz
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (error) => print('STT Error: $error'),
      onStatus: (status) => print('STT Status: $status'),
    );
    return _initialized;
  }

  bool get isListening => _speech.isListening;
  bool get isAvailable => _initialized;

  /// Comienza a escuchar — llama onResult con el texto final
  Future<void> startListening({
    required Function(String text) onResult,
    required Function(String partial) onPartial,
    required Function(String error) onError,
    String localeId = 'es_AR', // Español Argentina
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) {
        onError('No se pudo inicializar el micrófono');
        return;
      }
    }

    _lastWords = '';

    await _speech.listen(
      onResult: (result) {
        _lastWords = result.recognizedWords;
        if (result.finalResult) {
          onResult(_lastWords);
        } else {
          onPartial(_lastWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: localeId,
      cancelOnError: true,
      partialResults: true,
      listenMode: ListenMode.dictation,
    );
  }

  /// Detiene la escucha
  Future<void> stopListening() async {
    await _speech.stop();
  }

  /// Cancela sin procesar
  Future<void> cancel() async {
    await _speech.cancel();
    _lastWords = '';
  }

  /// Lista los idiomas disponibles en el dispositivo
  Future<List<LocaleName>> getAvailableLocales() async {
    if (!_initialized) await initialize();
    return await _speech.locales();
  }
}
