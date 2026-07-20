import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'auth_service.dart';
import 'drive_service.dart';
import 'todo_service.dart';
import 'package:intl/date_symbol_data_local.dart';

class AiAction {
  final String type; // 'create_file' | 'create_folder' | 'append' | 'update' | 'read' | 'chat' | 'add_todo' | 'complete_todo' | 'delete_todo'
  final String targetName;
  final String? targetId;
  final String? parentId;
  final String? content;
  final String userMessage;

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
  static const String _model = 'openrouter/free'; // Asegura asignar un modelo gratuito pero no podemos saber cual se esta asignando
  static bool _dateFormattingInitialized = false;

  final AuthService _auth = AuthService();
  final DriveService _drive = DriveService();
  final TodoService _todos = TodoService();

  Future<AiAction> processVoiceText(String rawText) async {
    final apiKey = await _auth.getAiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API Key no configurada. Ve a Configuración.');
    }

    if (!_dateFormattingInitialized) {
      await initializeDateFormatting('es');
      _dateFormattingInitialized = true;
    }

    final now = DateTime.now();
    final dateStr = DateFormat("d 'de' MMMM yyyy, HH:mm", 'es').format(now);

    final existingFiles = await _drive.listAll();
    final rootId = await _drive.getOrCreateRootFolder();

    final fileList = existingFiles.isEmpty
        ? '(vacío, no hay archivos aún)'
        : existingFiles.map((f) => '  ${f.toString()}').join('\n');

    final todoList = await _todos.summaryForPrompt();

    final systemPrompt = '''
Sos un asistente de notas de voz inteligente. El usuario te habla en español y vos procesás su pedido.
Podés tener conversaciones normales Y gestionar archivos en Google Drive, Y gestionar la ToDo List del usuario, según lo que necesite.

Fecha y hora actual: $dateStr
Carpeta raíz ID: $rootId

Archivos y carpetas existentes en "Notas de Voz IA":
$fileList

Tareas actuales en la ToDo List (formato: [x]=hecha [ ]=pendiente, con su id):
$todoList

Tu tarea:
1. Entender la intención del usuario
2. Elegir la acción correcta
3. Responder ÚNICAMENTE con un JSON válido, sin backticks ni texto adicional

═══════════════════════════════
ACCIONES DISPONIBLES:
═══════════════════════════════

1. CHAT — Para saludos, preguntas generales, charla que NO requiere Drive ni ToDo:
{
  "type": "chat",
  "target_name": "",
  "target_id": null,
  "parent_id": null,
  "content": null,
  "user_message": "tu respuesta natural y amigable en español"
}

2. LEER ARCHIVO — Para preguntas sobre el contenido de notas existentes:
{
  "type": "read",
  "target_name": "nombre del archivo",
  "target_id": "ID del archivo a leer",
  "parent_id": null,
  "content": null,
  "user_message": "mensaje mientras busco la información"
}

3. CREAR ARCHIVO — Para guardar una nota nueva:
{
  "type": "create_file",
  "target_name": "nombre descriptivo del archivo",
  "target_id": null,
  "parent_id": "ID de la carpeta donde crearlo (usar rootId si no especifica)",
  "content": "contenido en markdown bien formateado",
  "user_message": "mensaje confirmando lo que hiciste"
}

4. CREAR CARPETA — Para organizar en subcarpetas:
{
  "type": "create_folder",
  "target_name": "nombre de la carpeta",
  "target_id": null,
  "parent_id": "ID de la carpeta padre",
  "content": null,
  "user_message": "mensaje confirmando lo que hiciste"
}

5. AGREGAR A ARCHIVO — Para añadir contenido sin borrar lo anterior:
{
  "type": "append",
  "target_name": "nombre del archivo",
  "target_id": "ID del archivo existente",
  "parent_id": null,
  "content": "contenido nuevo a agregar en markdown",
  "user_message": "mensaje confirmando lo que hiciste"
}

6. REEMPLAZAR ARCHIVO — Para modificar completamente el contenido:
{
  "type": "update",
  "target_name": "nombre del archivo",
  "target_id": "ID del archivo existente",
  "parent_id": null,
  "content": "nuevo contenido completo en markdown",
  "user_message": "mensaje confirmando lo que hiciste"
}

7. AGREGAR TAREA A LA TODO LIST — Cuando el usuario quiere anotar un pendiente:
{
  "type": "add_todo",
  "target_name": "texto corto y claro de la tarea",
  "target_id": null,
  "parent_id": null,
  "content": null,
  "user_message": "mensaje confirmando que agregaste la tarea"
}

8. MARCAR TAREA COMO HECHA — Cuando el usuario dice que ya hizo algo de su ToDo List:
{
  "type": "complete_todo",
  "target_name": "texto de la tarea tal como aparece en la lista (para buscarla si no tenés el id)",
  "target_id": "id de la tarea si lo identificás en la lista de arriba, si no null",
  "parent_id": null,
  "content": null,
  "user_message": "mensaje confirmando que la marcaste como hecha"
}

9. BORRAR TAREA — Cuando el usuario quiere eliminar una tarea de la ToDo List:
{
  "type": "delete_todo",
  "target_name": "texto de la tarea tal como aparece en la lista",
  "target_id": "id de la tarea si lo identificás en la lista de arriba, si no null",
  "parent_id": null,
  "content": null,
  "user_message": "mensaje confirmando que la borraste"
}

═══════════════════════════════
REGLAS DE DECISIÓN:
═══════════════════════════════
- Saludos, preguntas generales, charla → "chat"
- "¿Qué dice mi nota de...?", "¿Qué anoté sobre...?", "Leeme...", "¿Tengo algo sobre...?" → "read"
- "Anotá", "Guardá", "Creá una nota" (contenido largo, tipo nota) → "create_file"
- "Creá una carpeta" → "create_folder"
- "Agregá", "Añadí", "Sumá" a algo existente (un archivo) → "append"
- "Cambiá", "Reemplazá", "Modificá" algo existente (un archivo) → "update"
- "Agregá a mi lista de tareas", "tengo que hacer...", "recordame que tengo que...", "anotá en pendientes" → "add_todo"
- "Ya hice...", "terminé...", "marcá como hecho...", "completé..." referido a una tarea de la ToDo List → "complete_todo"
- "Borrá de mis tareas...", "sacá ... de la lista", "eliminá la tarea de..." → "delete_todo"
- Si el usuario pide algo ambiguo entre nota (archivo) y tarea (todo), preferí "add_todo" si es un pendiente corto y accionable ("comprar pan"), y "create_file" si es contenido más largo o informativo.
- Si menciona un archivo/carpeta de la lista → usá su ID
- Si no menciona carpeta específica → usá rootId como parent_id
- El contenido siempre debe estar bien formateado en markdown
- Los user_message deben ser naturales, en español, primera persona
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
        type: json['type'] ?? 'chat',
        targetName: json['target_name'] ?? '',
        targetId: json['target_id'],
        parentId: json['parent_id'] ?? rootId,
        content: json['content'],
        userMessage: json['user_message'] ?? 'Listo.',
      );
    } catch (e) {
      // Fallback: respuesta de chat genérica
      return AiAction(
        type: 'chat',
        targetName: '',
        userMessage: 'Entendí tu mensaje, pero no pude procesarlo correctamente. ¿Podés repetirlo?',
      );
    }
  }

  /// Ejecuta la acción y devuelve el mensaje final para mostrar al usuario
  Future<String> executeAction(AiAction action) async {
    final rootId = await _drive.getOrCreateRootFolder();

    switch (action.type) {

      case 'chat':
        return action.userMessage;

      case 'read':
        if (action.targetId == null) {
          return 'No encontré el archivo "${action.targetName}" en tus notas.';
        }
        // Leer el archivo y hacer una segunda llamada para responder la pregunta
        final fileContent = await _drive.readFile(action.targetId!);
        return await _answerAboutFile(fileContent, action.targetName);

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
          return 'No encontré el archivo "${action.targetName}" para agregar contenido.';
        }
        await _drive.appendToFile(
          fileId: action.targetId!,
          contentToAppend: action.content ?? '',
        );
        return action.userMessage;

      case 'update':
        if (action.targetId == null) {
          return 'No encontré el archivo "${action.targetName}" para modificar.';
        }
        await _drive.updateFile(
          fileId: action.targetId!,
          newContent: action.content ?? '',
        );
        return action.userMessage;

      case 'add_todo':
        if (action.targetName.trim().isEmpty) {
          return 'No entendí qué tarea querías agregar. ¿Podés repetirlo?';
        }
        await _todos.add(action.targetName, source: 'ai');
        return action.userMessage;

      case 'complete_todo':
        final id = await _resolveTodoId(action);
        if (id == null) {
          return 'No encontré "${action.targetName}" en tu ToDo List.';
        }
        await _todos.markDone(id, done: true);
        return action.userMessage;

      case 'delete_todo':
        final id = await _resolveTodoId(action);
        if (id == null) {
          return 'No encontré "${action.targetName}" en tu ToDo List.';
        }
        await _todos.delete(id);
        return action.userMessage;

      default:
        return 'No entendí qué querías hacer. ¿Podés repetirlo?';
    }
  }

  /// Resuelve el id de una tarea a partir de la acción: usa target_id si la
  /// IA lo identificó correctamente contra el prompt, y si no, cae a buscar
  /// por texto (para cuando la IA no copió bien el id).
  Future<String?> _resolveTodoId(AiAction action) async {
    if (action.targetId != null && action.targetId!.isNotEmpty) {
      final existing = await _todos.getById(action.targetId!);
      if (existing != null) return existing.id;
    }
    final found = await _todos.findByText(action.targetName);
    return found?.id;
  }

  /// Segunda llamada a la IA para responder preguntas sobre el contenido leído
  Future<String> _answerAboutFile(String fileContent, String fileName) async {
    final apiKey = await _auth.getAiApiKey();
    if (apiKey == null) throw Exception('API Key no configurada.');

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
          {
            'role': 'system',
            'content':
                'Sos un asistente que responde preguntas sobre notas del usuario. '
                'Respondé de forma natural, concisa y en español. '
                'Si la nota tiene una lista, resumila claramente.'
          },
          {
            'role': 'user',
            'content':
                'Este es el contenido del archivo "$fileName":\n\n$fileContent\n\n'
                'Resumímelo o respondé mi pregunta sobre él de forma clara y natural.'
          },
        ],
        'max_tokens': 800,
        'temperature': 0.3,
      }),
    );

    if (response.statusCode != 200) {
      return 'Leí el archivo "$fileName" pero no pude procesarlo.';
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }
}