import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../models/note_model.dart';

// Renombramos la clase pero mantenemos la misma interfaz
// para no tener que cambiar nada en el resto de la app
class AiService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  final AuthService _auth = AuthService();

  /// Procesa el texto de voz y devuelve una nota formateada
  Future<NoteModel> processVoiceText(String rawText) async {
    final apiKey = await _auth.getAiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key no configurada. Ve a Configuración.');
    }

    final now = DateTime.now();
    final dateStr =
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    final prompt = '''
Sos un asistente que procesa notas de voz en español y las formatea como archivos Markdown.

El usuario dijo: "$rawText"

Tu tarea:
1. Inferir un título corto y descriptivo (máximo 8 palabras)
2. Limpiar y formatear el contenido
3. Extraer etiquetas relevantes (máximo 4)
4. Detectar si hay una tarea pendiente o acción a tomar

Respondé ÚNICAMENTE con un JSON válido sin markdown ni backticks, con esta estructura exacta:
{
  "title": "título de la nota",
  "content": "contenido formateado en markdown",
  "tags": ["etiqueta1", "etiqueta2"],
  "has_action": true,
  "action_summary": "descripción de la acción si existe, sino null"
}

Fecha actual: $dateStr
''';

    final response = await http.post(
      Uri.parse('$_baseUrl?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.3,
          'maxOutputTokens': 1000,
        },
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(
          'Error de Gemini API: ${error['error']?['message'] ?? response.body}');
    }

    final data = jsonDecode(response.body);
    final text =
        data['candidates'][0]['content']['parts'][0]['text'] as String;

    // Limpiar posibles backticks que Gemini a veces agrega
    final cleaned = text
        .trim()
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    try {
      final noteData = jsonDecode(cleaned);
      return NoteModel(
        title: noteData['title'] ?? 'Nota de voz',
        content: noteData['content'] ?? rawText,
        tags: List<String>.from(noteData['tags'] ?? []),
        hasAction: noteData['has_action'] ?? false,
        actionSummary: noteData['action_summary'],
        createdAt: DateTime.now(),
        rawTranscription: rawText,
      );
    } catch (e) {
      // Fallback si Gemini no devuelve JSON válido
      return NoteModel(
        title: 'Nota ${DateTime.now().day}/${DateTime.now().month}',
        content: rawText,
        tags: [],
        hasAction: false,
        actionSummary: null,
        createdAt: DateTime.now(),
        rawTranscription: rawText,
      );
    }
  }
}