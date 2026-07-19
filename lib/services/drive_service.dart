import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class DriveFile {
  final String id;
  final String name;
  final String mimeType;
  final String? parentId;

  DriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    this.parentId,
  });

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';

  @override
  String toString() => '${isFolder ? "[carpeta]" : "[archivo]"} $name (id: $id)';
}

class DriveService {
  final AuthService _auth = AuthService();

  static const String _driveApi = 'https://www.googleapis.com/drive/v3';
  static const String _uploadApi = 'https://www.googleapis.com/upload/drive/v3';
  static const String _rootFolderName = 'Notas de Voz IA';

  // ── Carpeta raíz ─────────────────────────────────────────────────────────

  Future<String> getOrCreateRootFolder() async {
    final savedId = await _auth.getDriveFolderId();
    if (savedId != null && savedId.isNotEmpty) {
      final exists = await _itemExists(savedId);
      if (exists) return savedId;
    }

    final headers = await _auth.getAuthHeaders();
    final query = Uri.encodeComponent(
      'name="$_rootFolderName" and mimeType="application/vnd.google-apps.folder" and trashed=false',
    );
    final searchRes = await http.get(
      Uri.parse('$_driveApi/files?q=$query&fields=files(id,name)'),
      headers: headers,
    );
    final searchData = jsonDecode(searchRes.body);
    final files = searchData['files'] as List;

    if (files.isNotEmpty) {
      final id = files[0]['id'] as String;
      await _auth.saveDriveFolderId(id);
      return id;
    }

    // Crear carpeta raíz
    final createRes = await http.post(
      Uri.parse('$_driveApi/files'),
      headers: headers,
      body: jsonEncode({
        'name': _rootFolderName,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );
    final id = jsonDecode(createRes.body)['id'] as String;
    await _auth.saveDriveFolderId(id);
    return id;
  }

  Future<bool> _itemExists(String id) async {
    try {
      final headers = await _auth.getAuthHeaders();
      final res = await http.get(
        Uri.parse('$_driveApi/files/$id?fields=id,trashed'),
        headers: headers,
      );
      if (res.statusCode != 200) return false;
      return jsonDecode(res.body)['trashed'] != true;
    } catch (_) {
      return false;
    }
  }

  // ── Listar contenido ─────────────────────────────────────────────────────

  /// Lista todos los archivos y carpetas dentro de la carpeta raíz (recursivo)
  Future<List<DriveFile>> listAll() async {
    final rootId = await getOrCreateRootFolder();
    return await _listInFolder(rootId, parentId: rootId);
  }

  Future<List<DriveFile>> _listInFolder(String folderId,
      {String? parentId}) async {
    final headers = await _auth.getAuthHeaders();
    final query = Uri.encodeComponent(
      '"$folderId" in parents and trashed=false',
    );
    final res = await http.get(
      Uri.parse(
          '$_driveApi/files?q=$query&fields=files(id,name,mimeType)&orderBy=name'),
      headers: headers,
    );
    final data = jsonDecode(res.body);
    final items = (data['files'] as List).map((f) {
      return DriveFile(
        id: f['id'],
        name: f['name'],
        mimeType: f['mimeType'],
        parentId: folderId,
      );
    }).toList();

    // Recursivo: listar subcarpetas también
    final result = <DriveFile>[];
    for (final item in items) {
      result.add(item);
      if (item.isFolder) {
        final children = await _listInFolder(item.id, parentId: item.id);
        result.addAll(children);
      }
    }
    return result;
  }

  // ── Operaciones ──────────────────────────────────────────────────────────

  /// Crea un archivo de texto nuevo
  Future<String> createFile({
    required String name,
    required String content,
    required String parentId,
  }) async {
    final headers = await _auth.getAuthHeaders();
    final fileName = name.endsWith('.md') ? name : '$name.md';
    final metadata = jsonEncode({
      'name': fileName,
      'mimeType': 'text/markdown',
      'parents': [parentId],
    });

    final boundary = 'boundary_${DateTime.now().millisecondsSinceEpoch}';
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: text/markdown\r\n\r\n'
        '$content\r\n'
        '--$boundary--';

    final uploadHeaders = Map<String, String>.from(headers);
    uploadHeaders['Content-Type'] =
        'multipart/related; boundary=$boundary';

    final res = await http.post(
      Uri.parse(
          '$_uploadApi/files?uploadType=multipart&fields=id,name,webViewLink'),
      headers: uploadHeaders,
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('Error al crear archivo: ${res.body}');
    }
    return jsonDecode(res.body)['name'] ?? name;
  }

  /// Crea una carpeta nueva
  Future<String> createFolder({
    required String name,
    required String parentId,
  }) async {
    final headers = await _auth.getAuthHeaders();
    final res = await http.post(
      Uri.parse('$_driveApi/files'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'mimeType': 'application/vnd.google-apps.folder',
        'parents': [parentId],
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Error al crear carpeta: ${res.body}');
    }
    return jsonDecode(res.body)['id'] as String;
  }

  /// Sobreescribe el contenido de un archivo existente
  Future<void> updateFile({
    required String fileId,
    required String newContent,
  }) async {
    final headers = await _auth.getAuthHeaders();
    headers['Content-Type'] = 'text/markdown';
    final res = await http.patch(
      Uri.parse('$_uploadApi/files/$fileId?uploadType=media'),
      headers: headers,
      body: newContent,
    );
    if (res.statusCode != 200) {
      throw Exception('Error al actualizar archivo: ${res.body}');
    }
  }

  /// Lee el contenido actual de un archivo
  Future<String> readFile(String fileId) async {
    final headers = await _auth.getAuthHeaders();
    final res = await http.get(
      Uri.parse('$_driveApi/files/$fileId?alt=media'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Error al leer archivo: ${res.body}');
    }
    return res.body;
  }

  /// Agrega contenido al final de un archivo existente
  Future<void> appendToFile({
    required String fileId,
    required String contentToAppend,
  }) async {
    final existing = await readFile(fileId);
    final updated = '$existing\n\n$contentToAppend';
    await updateFile(fileId: fileId, newContent: updated);
  }
}
