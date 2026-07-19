import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/speech_service.dart';
import '../services/ai_service.dart';
import '../widgets/waveform_widget.dart';

// Modelo de mensaje de conversación
class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  final bool isError;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.isError = false,
  });
}

enum AppState { idle, listening, processing }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _speechService = SpeechService();
  final _aiService = AiService();
  final _scrollController = ScrollController();

  AppState _appState = AppState.idle;
  String _partialText = '';
  bool _hasAudioInput = false;

  final List<_ChatMessage> _messages = [];
  bool get _hasMessages => _messages.isNotEmpty;

  // Typing animation — sin cambios
  final String _welcomeMessage =
      '¡Hola! Soy tu asistente de notas. Tocá el micrófono y decime qué querés anotar.';
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

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.4, end: 0.85).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _speechService.initialize();
    _startTypingAnimation();
  }

  void _startTypingAnimation() {
    Future.delayed(const Duration(milliseconds: 600), _typeNextChar);
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
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Lógica de grabación ──────────────────────────────────────────────────

  Future<void> _toggleListening() async {
    if (_appState == AppState.listening) {
      final lastText = _speechService.lastWords;
      await _speechService.stopListening();
      if (lastText.isNotEmpty) {
        await _processText(lastText);
      } else {
        setState(() {
          _appState = AppState.idle;
          _partialText = '';
          _hasAudioInput = false;
        });
      }
    } else if (_appState == AppState.idle) {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _addMessage('Se necesita permiso del micrófono.', isUser: false, isError: true);
      return;
    }

    setState(() {
      _appState = AppState.listening;
      _partialText = '';
      _hasAudioInput = true;
    });

    await _speechService.startListening(
      onPartial: (text) => setState(() {
        _partialText = text;
        _hasAudioInput = text.isNotEmpty;
      }),
      onResult: (text) async {
        if (text.isEmpty) {
          setState(() {
            _appState = AppState.idle;
            _partialText = '';
            _hasAudioInput = false;
          });
          return;
        }
        await _processText(text);
      },
      onError: (error) {
        _addMessage('Error al escuchar: $error', isUser: false, isError: true);
        setState(() {
          _appState = AppState.idle;
          _partialText = '';
          _hasAudioInput = false;
        });
      },
    );
  }

  Future<void> _processText(String text) async {
    setState(() {
      _appState = AppState.processing;
      _partialText = '';
      _hasAudioInput = false;
    });

    // Agregar mensaje del usuario
    _addMessage(text, isUser: true);

    try {
      final action = await _aiService.processVoiceText(text);
      final result = await _aiService.executeAction(action);

      _addMessage(result, isUser: false);
    } catch (e) {
      _addMessage(
        e.toString().replaceAll('Exception: ', ''),
        isUser: false,
        isError: true,
      );
    }

    setState(() => _appState = AppState.idle);
  }

  void _addMessage(String text, {required bool isUser, bool isError = false}) {
    setState(() {
      _messages.add(_ChatMessage(
        text: text,
        isUser: isUser,
        time: DateTime.now(),
        isError: isError,
      ));
    });
    _scrollToBottom();
  }

  // ── Colores por estado ───────────────────────────────────────────────────

  Color get _stateColor {
    switch (_appState) {
      case AppState.idle:
        return const Color(0xFF6C63FF);
      case AppState.listening:
        return const Color(0xFFFF4D6D);
      case AppState.processing:
        return const Color(0xFFFFC857);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: Stack(
        children: [
          // Fondo con glow — sin cambios
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
                  gradient: RadialGradient(colors: [
                    _stateColor.withOpacity(_glowAnimation.value * 0.18),
                    Colors.transparent,
                  ]),
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
                  gradient: RadialGradient(colors: [
                    _stateColor.withOpacity(_glowAnimation.value * 0.12),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          // UI principal
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _stateColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: _stateColor.withOpacity(0.3), width: 1),
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
                    boxShadow: [
                      BoxShadow(
                          color: _stateColor.withOpacity(0.8), blurRadius: 6)
                    ],
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
    // Sin mensajes: pantalla de bienvenida intacta
    if (!_hasMessages && _appState != AppState.listening) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: _buildWelcomeContent(),
          ),
        ],
      );
    }
    // Con mensajes (o escuchando): vista de conversación
    return _buildConversation();
  }

  // Pantalla de bienvenida — idéntica al original
  Widget _buildWelcomeContent() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                _stateColor.withOpacity(0.7),
                _stateColor.withOpacity(0.3)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: _stateColor.withOpacity(0.3), blurRadius: 20)
            ],
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 26),
        ),
        const SizedBox(height: 20),
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

  // Vista de conversación
  Widget _buildConversation() {
    final extraItems = (_appState == AppState.listening ? 1 : 0) +
        (_appState == AppState.processing ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _messages.length + extraItems,
      itemBuilder: (context, index) {
        if (index < _messages.length) {
          return _buildMessageBubble(_messages[index]);
        }
        if (_appState == AppState.listening) return _buildLiveBubble();
        if (_appState == AppState.processing) return _buildProcessingBubble();
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isUser) ...[
            _buildAvatar(
              icon: msg.isError
                  ? Icons.error_outline_rounded
                  : Icons.auto_awesome_rounded,
              color: msg.isError
                  ? const Color(0xFFFF4D6D)
                  : const Color(0xFF6C63FF),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: msg.isUser
                    ? const Color(0xFF6C63FF).withOpacity(0.22)
                    : msg.isError
                        ? const Color(0xFFFF4D6D).withOpacity(0.08)
                        : const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                  bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                ),
                border: Border.all(
                  color: msg.isUser
                      ? const Color(0xFF6C63FF).withOpacity(0.28)
                      : msg.isError
                          ? const Color(0xFFFF4D6D).withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                ),
              ),
              child: _buildMessageText(msg),
            ),
          ),
          if (msg.isUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(
              icon: Icons.person_rounded,
              color: const Color(0xFF6C63FF),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar({required IconData icon, required Color color}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(icon, color: Colors.white, size: 14),
    );
  }

  Widget _buildMessageText(_ChatMessage msg) {
    if (msg.isUser) {
      return Text(
        msg.text,
        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
      );
    }

    // Markdown simple para mensajes de IA
    final lines = msg.text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.startsWith('**') && line.endsWith('**')) {
          return Text(
            line.replaceAll('**', ''),
            style: TextStyle(
              color: msg.isError ? const Color(0xFFFF4D6D) : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
          );
        }
        if (line.startsWith('_') && line.endsWith('_')) {
          return Text(
            line.replaceAll('_', ''),
            style: const TextStyle(
              color: Colors.white30,
              fontSize: 12,
              fontStyle: FontStyle.italic,
              height: 2.0,
            ),
          );
        }
        if (line.startsWith('#')) {
          return Text(
            line.replaceAll('#', '').trim(),
            style: const TextStyle(
                color: Color(0xFF6C63FF), fontSize: 12, height: 2.0),
          );
        }
        if (line.isEmpty) return const SizedBox(height: 4);
        return Text(
          line,
          style: TextStyle(
            color: msg.isError
                ? const Color(0xFFFF4D6D).withOpacity(0.85)
                : Colors.white60,
            fontSize: 14,
            height: 1.5,
          ),
        );
      }).toList(),
    );
  }

  // Burbuja "en vivo" mientras escucha
  Widget _buildLiveBubble() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4D6D).withOpacity(0.12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
                border: Border.all(
                    color: const Color(0xFFFF4D6D).withOpacity(0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WaveformWidget(isActive: _hasAudioInput),
                  if (_partialText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _partialText,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildAvatar(
              icon: Icons.person_rounded, color: const Color(0xFFFF4D6D)),
        ],
      ),
    );
  }

  // Burbuja "procesando"
  Widget _buildProcessingBubble() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildAvatar(
              icon: Icons.auto_awesome_rounded,
              color: const Color(0xFFFFC857)),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFC857)),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Procesando...',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 48, top: 16),
      child: Column(
        children: [
          _buildHint(),
          const SizedBox(height: 28),
          _buildMicButton(),
        ],
      ),
    );
  }

  Widget _buildHint() {
    if (_appState == AppState.processing) return const SizedBox.shrink();
    final isListening = _appState == AppState.listening;
    return AnimatedOpacity(
      opacity: (_hasMessages || _typingDone) ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isListening ? Icons.stop_circle_outlined : Icons.touch_app_rounded,
            color: Colors.white24,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            isListening ? 'Tocá para terminar' : 'Tocá para hablar',
            style: const TextStyle(
                color: Colors.white24, fontSize: 12, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    final isListening = _appState == AppState.listening;
    final isProcessing = _appState == AppState.processing;

    return GestureDetector(
      onTap: isProcessing ? null : _toggleListening,
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
                if (!isProcessing)
                  Container(
                    width: 148,
                    height: 148,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        _stateColor.withOpacity(
                            glowIntensity * (isListening ? 0.35 : 0.15)),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _stateColor
                          .withOpacity(isListening ? 0.5 : 0.2),
                      width: 1,
                    ),
                  ),
                ),
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
                              _stateColor.withOpacity(0.7)
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
                              color: _stateColor
                                  .withOpacity(glowIntensity * 0.6),
                              blurRadius: isListening ? 40 : 24,
                              spreadRadius: isListening ? 6 : 2,
                            ),
                          ],
                  ),
                  child: _buildMicIcon(isProcessing),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMicIcon(bool isProcessing) {
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
    if (_appState == AppState.listening) {
      return const Icon(Icons.stop_rounded, color: Colors.white, size: 34);
    }
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
  }
}