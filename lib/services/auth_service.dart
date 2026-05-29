import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file', // Crear/editar archivos propios
    ],
  );

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;

  /// Retorna true si hay sesión activa
  Future<bool> isSignedIn() async {
    _currentUser = await _googleSignIn.signInSilently();
    return _currentUser != null;
  }

  /// Inicia sesión con Google
  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser;
    } catch (e) {
      return null;
    }
  }

  /// Cierra sesión
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  /// Obtiene los headers de autenticación para las APIs de Google
  Future<Map<String, String>> getAuthHeaders() async {
    final account = _currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) throw Exception('No hay sesión activa');
    final auth = await account.authentication;
    return {
      'Authorization': 'Bearer ${auth.accessToken}',
      'Content-Type': 'application/json',
    };
  }

  /// Guarda la API Key de forma segura
  Future<void> saveAiApiKey(String key) async {
    await _storage.write(key: 'ai_api_key', value: key);
  }

  /// Obtiene la API Key
  Future<String?> getAiApiKey() async {
    return await _storage.read(key: 'ai_api_key');
  }

  /// Guarda el folder ID de Drive
  Future<void> saveDriveFolderId(String id) async {
    await _storage.write(key: 'drive_folder_id', value: id);
  }

  /// Obtiene el folder ID de Drive
  Future<String?> getDriveFolderId() async {
    return await _storage.read(key: 'drive_folder_id');
  }
}
