import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/speech_service.dart';
import '../services/ai_service.dart';
import '../services/drive_service.dart';
import '../models/note_model.dart';
import '../widgets/waveform_widget.dart';
import '../widgets/note_result_card.dart';

enum AppState { idle, listening, processing, saved, error }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _speechService = SpeechService();
  final _aiService = AiService();
  final _driveService = DriveService();

  AppState _appState = AppState.idle;
  String _partialText = '';
  String _statusMessage = '';
  NoteModel? _lastNote;
  String? _errorMessage;
  bool _hasAudioInput = false;

  // Typing animation
  final String _welcomeMessage = '¡Hola! Soy tu asistente de notas. Mantené presionado el micrófono y decime qué querés anotar.';
  String _displayedWelcome = '';
  int _typingIndex = 0;
  bool _typingDone = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse for mic button while listening
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Glow idle animation
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.4, end: 0.85).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Fade in for UI
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _speechService.initialize();
    _startTypingAnimation();
  }

  void _startTypingAnimation() {
    Future.delayed(const Duration(milliseconds: 600), () {
      _typeNextChar();
    });
  }

  void _typeNextChar() {
    if (!mounted) return;
    if (_typingIndex < _welcomeMessage.length) {
      setState(() {
        _displayedWelcome += _welcomeMessage[_typingIndex];
        _typingIndex++;
      });
      Future.delayed(const Duration(milliseconds: 28), _typeNextChar);
    } else {
      setState(() => _typingDone = true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.microphone.request();
    if (status.isDenied) _setError('Se necesita permiso del micrófono');
  }

  Future<void> _startListening() async {
    await _requestPermissions();
    if (!(await Permission.microphone.isGranted)) return;
    setState(() {
      _appState = AppState.listening;
      _partialText = '';
      _lastNote = null;
      _errorMessage = null;
    });
    await _speechService.startListening(
      onPartial: (text) => setState(() {
        _partialText = text;
        _hasAudioInput = text.isNotEmpty;
      }),
      onResult: (text) async {
        if (text.isEmpty) {
          setState(() => _appState = AppState.idle);
          return;
        }
        await _processText(text);
      },
      onError: (error) => _setError('Error al escuchar: $error'),
    );
  }

  Future<void> _stopListening() async {
    await _speechService.stopListening();
  }

  Future<void> _processText(String text) async {
    setState(() {
      _appState = AppState.processing;
      _statusMessage = 'Procesando con IA...';
    });
    try {
      final note = await _aiService.processVoiceText(text);
      setState(() => _statusMessage = 'Guardando en Drive...');
      await _driveService.saveNote(note);
      setState(() {
        _appState = AppState.saved;
        _lastNote = note;
      });
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _setError(String message) {
    setState(() {
      _appState = AppState.error;
      _errorMessage = message;
    });
  }

  void _reset() {
    setState(() {
      _appState = AppState.idle;
      _partialText = '';
      _hasAudioInput = false;
      _lastNote = null;
      _errorMessage = null;
      _statusMessage = '';
    });
  }

  // Colors per state
  Color get _stateColor {
    switch (_appState) {
      case AppState.idle:      return const Color(0xFF6C63FF);
      case AppState.listening: return const Color(0xFFFF4D6D);
      case AppState.processing:return const Color(0xFFFFC857);
      case AppState.saved:     return const Color(0xFF43E97B);
      case AppState.error:     return const Color(0xFFFF4D6D);
    }
  }

  Color get _stateColorDim => _stateColor.withOpacity(0.18);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: Stack(
        children: [
          // Background ambient glow
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (_, __) => Positioned(
              top: -120,
              left: -80,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _stateColor.withOpacity(_glowAnimation.value * 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (_, __) => Positioned(
              bottom: -100,
              right: -60,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _stateColor.withOpacity(_glowAnimation.value * 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Main UI
          FadeTransition(
            opacity: _fadeAnimation,
            child: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: _buildBody()),
                  _buildBottomSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Logo / indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _stateColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _stateColor.withOpacity(0.3), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _stateColor,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: _stateColor.withOpacity(0.8), blurRadius: 6)],
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'Voice Notes AI',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white38, size: 22),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_appState == AppState.saved && _lastNote != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            NoteResultCard(note: _lastNote!),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _reset,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white38, size: 18),
                    SizedBox(width: 6),
                    Text('Nueva nota', style: TextStyle(color: Colors.white38, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Welcome / status area
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: _buildCenterContent(),
        ),
      ],
    );
  }

  Widget _buildCenterContent() {
    if (_appState == AppState.idle) {
      return Column(
        children: [
          // AI avatar icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [_stateColor.withOpacity(0.7), _stateColor.withOpacity(0.3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [BoxShadow(color: _stateColor.withOpacity(0.3), blurRadius: 20)],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 20),

          // Typing welcome message
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.6,
                letterSpacing: 0.2,
              ),
              children: [
                TextSpan(text: _displayedWelcome),
                if (!_typingDone)
                  WidgetSpan(
                    child: AnimatedBuilder(
                      animation: _glowController,
                      builder: (_, __) => Opacity(
                        opacity: _glowAnimation.value,
                        child: Container(
                          width: 2,
                          height: 16,
                          margin: const EdgeInsets.only(left: 2, bottom: 2),
                          color: _stateColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    if (_appState == AppState.listening) {
      return Column(
        children: [
          WaveformWidget(isActive: _hasAudioInput),
          const SizedBox(height: 28),
          if (_partialText.isNotEmpty)
            Text(
              _partialText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                height: 1.55,
                fontWeight: FontWeight.w400,
              ),
            )
          else
            const Text(
              'Escuchando...',
              style: TextStyle(color: Colors.white38, fontSize: 15, letterSpacing: 1),
            ),
        ],
      );
    }

    if (_appState == AppState.processing) {
      return Column(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_stateColor),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _statusMessage,
            style: const TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 0.5),
          ),
        ],
      );
    }

    if (_appState == AppState.error) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _stateColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline_rounded, color: _stateColor, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Error desconocido',
            textAlign: TextAlign.center,
            style: TextStyle(color: _stateColor.withOpacity(0.85), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Tocá el botón para reintentar',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBottomSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 48, top: 16),
      child: Column(
        children: [
          _buildHoldHint(),
          const SizedBox(height: 28),
          _buildMicButton(),
        ],
      ),
    );
  }

  Widget _buildHoldHint() {
    if (_appState != AppState.idle) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: _typingDone ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_rounded, color: Colors.white24, size: 14),
          const SizedBox(width: 6),
          const Text(
            'Mantené presionado para hablar',
            style: TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    final isListening = _appState == AppState.listening;
    final isProcessing = _appState == AppState.processing;
    final isError = _appState == AppState.error;

    return GestureDetector(
      onLongPressStart: (_) { if (_appState == AppState.idle) _startListening(); },
      onLongPressEnd: (_) { if (isListening) _stopListening(); },
      onTap: () {
        if (isError) _reset();
        if (isListening) _stopListening();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnimation, _glowAnimation]),
        builder: (context, child) {
          final scale = isListening ? _pulseAnimation.value : 1.0;
          final glowIntensity = isListening ? 1.0 : _glowAnimation.value;

          return Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring
                if (!isProcessing)
                  Container(
                    width: 148,
                    height: 148,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _stateColor.withOpacity(glowIntensity * (isListening ? 0.35 : 0.15)),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                // Second ring
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _stateColor.withOpacity(isListening ? 0.5 : 0.2),
                      width: 1,
                    ),
                  ),
                ),

                // Main button
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isProcessing
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _stateColor,
                              _stateColor.withOpacity(0.7),
                            ],
                          ),
                    color: isProcessing ? Colors.transparent : null,
                    border: isProcessing
                        ? Border.all(color: _stateColor, width: 2)
                        : null,
                    boxShadow: isProcessing
                        ? []
                        : [
                            BoxShadow(
                              color: _stateColor.withOpacity(glowIntensity * 0.6),
                              blurRadius: isListening ? 40 : 24,
                              spreadRadius: isListening ? 6 : 2,
                            ),
                          ],
                  ),
                  child: _buildMicButtonIcon(isProcessing),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMicButtonIcon(bool isProcessing) {
    if (isProcessing) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(_stateColor),
          ),
        ),
      );
    }

    switch (_appState) {
      case AppState.idle:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
            const SizedBox(height: 2),
            Text(
              'REC',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ],
        );
      case AppState.listening:
        return const Icon(Icons.stop_rounded, color: Colors.white, size: 34);
      case AppState.saved:
        return const Icon(Icons.check_rounded, color: Colors.white, size: 34);
      case AppState.error:
        return const Icon(Icons.refresh_rounded, color: Colors.white, size: 34);
      default:
        return const SizedBox.shrink();
    }
  }
}