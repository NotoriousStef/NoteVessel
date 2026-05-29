import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/drive_service.dart';

class SettingsScreen extends StatefulWidget {
  final bool firstRun;
  const SettingsScreen({super.key, this.firstRun = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _driveService = DriveService();
  final _apiKeyController = TextEditingController();

  bool _isSignedIn = false;
  bool _loading = false;
  String? _userEmail;
  String? _statusMessage;
  bool _apiKeySaved = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final signedIn = await _authService.isSignedIn();
    final apiKey = await _authService.getAiApiKey();
    setState(() {
      _isSignedIn = signedIn;
      _userEmail = _authService.currentUser?.email;
      _apiKeySaved = apiKey != null && apiKey.isNotEmpty;
      if (apiKey != null && apiKey.isNotEmpty) {
        _apiKeyController.text = apiKey;
      }
    });
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    final account = await _authService.signIn();
    setState(() {
      _loading = false;
      _isSignedIn = account != null;
      _userEmail = account?.email;
      _statusMessage = account != null
          ? '✅ Sesión iniciada como ${account.email}'
          : '❌ No se pudo iniciar sesión';
    });
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    setState(() {
      _isSignedIn = false;
      _userEmail = null;
      _statusMessage = 'Sesión cerrada';
    });
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _statusMessage = '❌ Ingresá una API Key válida');
      return;
    }
    await _authService.saveAiApiKey(key);
    setState(() {
      _apiKeySaved = true;
      _statusMessage = '✅ API Key guardada de forma segura';
    });
  }

  Future<void> _testDrive() async {
    setState(() {
      _loading = true;
      _statusMessage = 'Verificando acceso a Drive...';
    });
    try {
      final folderId = await _driveService.getOrCreateFolder();
      setState(() {
        _loading = false;
        _statusMessage = '✅ Carpeta lista en Drive (ID: ${folderId.substring(0, 8)}...)';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _statusMessage = '❌ Error: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  void _done() {
    if (!_isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero iniciá sesión con Google')),
      );
      return;
    }
    if (!_apiKeySaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero guardá tu Gemini API Key')),
      );
      return;
    }
    if (widget.firstRun) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.firstRun ? 'Configuración inicial' : 'Configuración',
          style: const TextStyle(color: Colors.white70),
        ),
        leading: widget.firstRun
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.firstRun) ...[
              const Text(
                'Bienvenido 👋',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Configurá tu cuenta de Google y tu Gemini API Key para empezar.',
                style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
            ],

            // === PASO 1: Google ===
            _buildSectionTitle('1. Cuenta de Google'),
            const SizedBox(height: 12),
            if (_isSignedIn) ...[
              _buildStatusTile(
                icon: Icons.check_circle,
                iconColor: const Color(0xFF34A853),
                title: _userEmail ?? 'Conectado',
                subtitle: 'Sesión iniciada',
                trailing: TextButton(
                  onPressed: _signOut,
                  child: const Text('Cerrar sesión',
                      style: TextStyle(color: Colors.white38)),
                ),
              ),
            ] else ...[
              _buildCard(
                child: Column(
                  children: [
                    const Text(
                      'Necesitás una cuenta de Google para guardar las notas en Drive.',
                      style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _signIn,
                        icon: const Icon(Icons.login),
                        label: const Text('Iniciar sesión con Google'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A73E8),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // === PASO 2: Gemini API Key ===
            _buildSectionTitle('2. Gemini API Key'),
            const SizedBox(height: 8),
            const Text(
              'Gratis en aistudio.google.com → Get API Key',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildCard(
              child: Column(
                children: [
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'AIza...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white38,
                        ),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveApiKey,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _apiKeySaved
                            ? const Color(0xFF34A853)
                            : const Color(0xFF333333),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(_apiKeySaved ? '✅ Guardada' : 'Guardar API Key'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // === PASO 3: Test Drive ===
            if (_isSignedIn) ...[
              _buildSectionTitle('3. Verificar Google Drive'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _testDrive,
                  icon: const Icon(Icons.cloud_done_outlined),
                  label: const Text('Verificar carpeta en Drive'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // === Status ===
            if (_statusMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),

            const SizedBox(height: 32),

            // === Listo ===
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _done,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  widget.firstRun ? 'Empezar' : 'Guardar y volver',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildStatusTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}