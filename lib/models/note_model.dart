import 'package:intl/intl.dart';

class NoteModel {
  final String title;
  final String content;
  final List<String> tags;
  final bool hasAction;
  final String? actionSummary;
  final DateTime createdAt;
  final String rawTranscription;

  NoteModel({
    required this.title,
    required this.content,
    required this.tags,
    required this.hasAction,
    this.actionSummary,
    required this.createdAt,
    required this.rawTranscription,
  });

  /// Genera el contenido Markdown del archivo
  String toMarkdown() {
    final formatter = DateFormat("d 'de' MMMM yyyy, HH:mm", 'es');
    final dateStr = formatter.format(createdAt);

    final buffer = StringBuffer();

    // Encabezado YAML frontmatter
    buffer.writeln('---');
    buffer.writeln('title: "$title"');
    buffer.writeln('date: ${createdAt.toIso8601String()}');
    if (tags.isNotEmpty) {
      buffer.writeln('tags: [${tags.map((t) => '"$t"').join(', ')}]');
    }
    if (hasAction) {
      buffer.writeln('has_action: true');
    }
    buffer.writeln('source: voice_note');
    buffer.writeln('---');
    buffer.writeln();

    // Título
    buffer.writeln('# $title');
    buffer.writeln();
    buffer.writeln('> 📅 $dateStr');
    buffer.writeln();

    // Contenido formateado por IA
    buffer.writeln(content);
    buffer.writeln();

    // Acción pendiente si existe
    if (hasAction && actionSummary != null) {
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('## ✅ Acción pendiente');
      buffer.writeln();
      buffer.writeln('- [ ] $actionSummary');
      buffer.writeln();
    }

    // Etiquetas
    if (tags.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('**Etiquetas:** ${tags.map((t) => '`$t`').join(' ')}');
      buffer.writeln();
    }

    // Transcripción original
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('<details>');
    buffer.writeln('<summary>Transcripción original</summary>');
    buffer.writeln();
    buffer.writeln('> $rawTranscription');
    buffer.writeln();
    buffer.writeln('</details>');

    return buffer.toString();
  }
}
