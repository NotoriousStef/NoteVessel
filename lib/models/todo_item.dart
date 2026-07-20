/// Representa un ítem de la ToDo List.
/// Se persiste en Hive como un Map plano (sin generación de código).
class TodoItem {
  final String id;
  String text;
  bool isDone;
  final DateTime createdAt;
  DateTime? completedAt;

  /// Quién creó el ítem: 'user' o 'ai'. Útil para mostrar un pequeño
  /// indicador visual de que fue la IA la que agregó la tarea.
  final String source;

  TodoItem({
    required this.id,
    required this.text,
    this.isDone = false,
    required this.createdAt,
    this.completedAt,
    this.source = 'user',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'isDone': isDone,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'source': source,
      };

  factory TodoItem.fromMap(Map<dynamic, dynamic> map) => TodoItem(
        id: map['id'] as String,
        text: map['text'] as String,
        isDone: map['isDone'] as bool? ?? false,
        createdAt: DateTime.parse(map['createdAt'] as String),
        completedAt: map['completedAt'] != null
            ? DateTime.parse(map['completedAt'] as String)
            : null,
        source: map['source'] as String? ?? 'user',
      );
}