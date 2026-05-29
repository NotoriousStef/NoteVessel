import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../models/note_model.dart';

class DriveService {
  final AuthService _auth = AuthService();

  static const String _driveApi = 'https://www.googleapis.com/drive/v3';
  static const String _uploadApi = 'https://www.googleapis.com/upload/drive/v3';
  static const String _defaultFolderName = 'Notas de Voz IA';

  /// Obtiene o crea la carpeta de notas en Drive
  Future<String> getOrCreateFolder() async {
    // Verificar si ya tenemos el ID guardado
    final savedId = await _auth.getDriveFolderId();
    if (savedId != null && savedId.isNotEmpty) {
      final exists = await _folderExists(savedId);
      if (exists) return savedId;
    }

    // Buscar carpeta existente con ese nombre
    final headers = await _auth.getAuthHeaders();
    final searchUrl = Uri.parse(
      '$_driveApi/files?q=name%3D%22$_defaultFolderName%22+and+mimeType%3D%22application/vnd.google-apps.folder%22+and+trashed%3Dfalse&fields=files(id,name)',
    );

    final searchResponse = await http.get(searchUrl, headers: headers);
    final searchData = jsonDecode(searchResponse.body);
    final files = searchData['files'] as List;

    if (files.isNotEmpty) {
      final folderId = files[0]['id'] as String;
      await _auth.saveDriveFolderId(folderId);
      return folderId;
    }

    // Crear la carpeta
    final createResponse = await http.post(
      Uri.parse('$_driveApi/files'),
      headers: headers,
      body: jsonEncode({
        'name': _defaultFolderName,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );

    final createData = jsonDecode(createResponse.body);
    final folderId = createData['id'] as String;
    await _auth.saveDriveFolderId(folderId);
    return folderId;
  }

  Future<bool> _folderExists(String folderId) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_driveApi/files/$folderId?fields=id,trashed'),
        headers: headers,
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data['trashed'] != true;
    } catch (e) {
      return false;
    }
  }

  /// Guarda una nota como archivo .md en Drive
  Future<String> saveNote(NoteModel note) async {
    final folderId = await getOrCreateFolder();
    final headers = await _auth.getAuthHeaders();

    final fileName = _sanitizeFileName(note.title);
    final fileContent = note.toMarkdown();

    // Multipart upload para crear el archivo
    final metadata = jsonEncode({
      'name': '$fileName.md',
      'mimeType': 'text/markdown',
      'parents': [folderId],
    });

    final boundary = 'flutter_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: text/markdown\r\n\r\n'
        '$fileContent\r\n'
        '--$boundary--';

    final uploadHeaders = Map<String, String>.from(headers);
    uploadHeaders['Content-Type'] = 'multipart/related; boundary=$boundary';

    final response = await http.post(
      Uri.parse('$_uploadApi/files?uploadType=multipart&fields=id,name,webViewLink'),
      headers: uploadHeaders,
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('Error al guardar en Drive: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['webViewLink'] ?? data['id'];
  }

  /// Lista las últimas notas guardadas
  Future<List<Map<String, dynamic>>> listRecentNotes({int limit = 10}) async {
    final folderId = await getOrCreateFolder();
    final headers = await _auth.getAuthHeaders();

    final query = Uri.encodeComponent(
      "'$folderId' in parents and mimeType='text/markdown' and trashed=false",
    );

    final response = await http.get(
      Uri.parse(
        '$_driveApi/files?q=$query&orderBy=createdTime+desc&pageSize=$limit&fields=files(id,name,createdTime,webViewLink)',
      ),
      headers: headers,
    );

    final data = jsonDecode(response.body);
    return List<Map<String, dynamic>>.from(data['files'] ?? []);
  }

  String _sanitizeFileName(String title) {
    final now = DateTime.now();
    final datePrefix = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final clean = title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(' ', '_')
        .toLowerCase();
    return '${datePrefix}_$clean';
  }
}
