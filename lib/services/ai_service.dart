import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'auth_service.dart';
import 'drive_service.dart';

/// Resultado de la IA con la acción a ejecutar en Drive
class AiAction {
  final String type; // 'create_file' | 'create_folder' | 'append' | 'update'
  final String targetName;       // nombre del archivo/carpeta
  final String? targetId;        // ID si modifica uno existente
  final String? parentId;        // ID de la carpeta donde crear
  final String? content;         // contenido del archivo
  final String userMessage;      // mensaje para mostrar al usuario en el chat

  AiAction({
    required this.type,
    required this.targetName,
    this.targetId,
    this.parentId,
    this.content,
    required this.userMessage,
  });
}

class AiService {
  static const String _baseUrl =
      'https://openrouter.ai/api/v1/chat/completions';
  static const String _model = 'meta-llama/llama-3.1-8b-instruct:free';

  final AuthService _auth = AuthService();
  final DriveService _drive = DriveService();

  Future<AiAction> processVoiceText(String rawText) async {
    final apiKey = await _auth.getAiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API Key no configurada. Ve a Configuración.');
    }

    final now = DateTime.now();
    final dateStr = DateFormat("d 'de' MMMM yyyy, HH:mm", 'es').format(now);

    // Obtener lista de archivos existentes
    final existingFiles = await _drive.listAll();
    final rootId = await _drive.getOrCreateRootFolder();

    final fileList = existingFiles.isEmpty
        ? '(vacío, no hay archivos aún)'
        : existingFiles.map((f) => '  ${f.toString()}').join('\n');

    final systemPrompt = '''
Sos un asistente de notas de voz. El usuario te habla en español y vos procesás su pedido para gestionar archivos en Google Drive.

Fecha y hora actual: $dateStr

Carpeta raíz ID: $rootId

Archivos y carpetas existentes dentro de "Notas de Voz IA":
$fileList

Tu tarea:
1. Entender qué quiere hacer el usuario
2. Decidir la acción correcta
3. Responder ÚNICAMENTE con un JSON válido, sin backticks ni texto adicional

Acciones posibles:

- Crear archivo nuevo:
{
  "type": "create_file",
  "target_name": "nombre del archivo",
  "parent_id": "ID de la carpeta donde crearlo (usar rootId si no especifica)",
  "content": "contenido en markdown",
  "user_message": "mensaje confirmando lo que hiciste"
}

- Crear carpeta nueva:
{
  "type": "create_folder",
  "target_name": "nombre de la carpeta",
  "parent_id": "ID de la carpeta padre",
  "content": null,
  "user_message": "mensaje confirmando lo que hiciste"
}

- Agregar contenido a archivo existente (sin borrar lo anterior):
{
  "type": "append",
  "target_name": "nombre del archivo",
  "target_id": "ID del archivo existente",
  "content": "contenido nuevo a agregar en markdown",
  "user_message": "mensaje confirmando lo que hiciste"
}

- Reemplazar contenido de archivo existente:
{
  "type": "update",
  "target_name": "nombre del archivo",
  "target_id": "ID del archivo existente",
  "content": "nuevo contenido completo en markdown",
  "user_message": "mensaje confirmando lo que hiciste"
}

Reglas importantes:
- Si el usuario menciona un archivo/carpeta que ya existe en la lista, usá su ID
- Si no menciona carpeta específica, usá el rootId como parent_id
- El content siempre debe estar bien formateado en markdown
- El user_message debe ser natural, en español, confirmando la acción realizada
- Si el usuario dice "anotá", "agregá", "añadí" → probablemente quiere append o create_file
- Si dice "creá una carpeta" → create_folder
- Si dice "reemplazá", "cambiá", "modificá" → update
''';

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
        'HTTP-Referer': 'com.example.voice_notes_ai',
        'X-Title': 'Voice Notes AI',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': rawText},
        ],
        'max_tokens': 1500,
        'temperature': 0.2,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(
          'Error de OpenRouter: ${error['error']?['message'] ?? response.body}');
    }

    final data = jsonDecode(response.body);
    final text = data['choices'][0]['message']['content'] as String;
    final cleaned =
        text.trim().replaceAll('```json', '').replaceAll('```', '').trim();

    try {
      final json = jsonDecode(cleaned);
      return AiAction(
        type: json['type'] ?? 'create_file',
        targetName: json['target_name'] ?? 'nota',
        targetId: json['target_id'],
        parentId: json['parent_id'] ?? rootId,
        content: json['content'],
        userMessage: json['user_message'] ?? 'Listo.',
      );
    } catch (e) {
      // Fallback: crear archivo simple con la transcripción
      return AiAction(
        type: 'create_file',
        targetName:
            'nota_${now.day}_${now.month}_${now.hour}_${now.minute}',
        parentId: rootId,
        content: '# Nota\n\n$rawText',
        userMessage: 'Guardé tu nota en Drive.',
      );
    }
  }

  /// Ejecuta la acción decidida por la IA en Drive
  Future<String> executeAction(AiAction action) async {
    final rootId = await _drive.getOrCreateRootFolder();

    switch (action.type) {
      case 'create_file':
        await _drive.createFile(
          name: action.targetName,
          content: action.content ?? '',
          parentId: action.parentId ?? rootId,
        );
        return action.userMessage;

      case 'create_folder':
        await _drive.createFolder(
          name: action.targetName,
          parentId: action.parentId ?? rootId,
        );
        return action.userMessage;

      case 'append':
        if (action.targetId == null) {
          throw Exception(
              'No encontré el archivo "${action.targetName}" para agregar contenido.');
        }
        await _drive.appendToFile(
          fileId: action.targetId!,
          contentToAppend: action.content ?? '',
        );
        return action.userMessage;

      case 'update':
        if (action.targetId == null) {
          throw Exception(
              'No encontré el archivo "${action.targetName}" para modificar.');
        }
        await _drive.updateFile(
          fileId: action.targetId!,
          newContent: action.content ?? '',
        );
        return action.userMessage;

      default:
        throw Exception('Acción desconocida: ${action.type}');
    }
  }
}