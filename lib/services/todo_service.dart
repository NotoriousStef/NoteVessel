import 'package:hive_ce/hive_ce.dart';
import '../models/todo_item.dart';

/// Maneja la persistencia local (Hive) de la ToDo List.
/// Singleton, mismo patrón que SpeechService.
class TodoService {
  static final TodoService _instance = TodoService._internal();
  factory TodoService() => _instance;
  TodoService._internal();

  static const String boxName = 'todos';
  Box? _box;

  Future<Box> get _todoBox async {
    if (_box != null) return _box!;
    _box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await Hive.openBox(boxName);
    return _box!;
  }

  /// Devuelve todas las tareas, pendientes primero y luego por fecha
  /// de creación descendente.
  Future<List<TodoItem>> getAll() async {
    final box = await _todoBox;
    final items = box.values
        .map((e) => TodoItem.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
    items.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return items;
  }

  Future<TodoItem?> getById(String id) async {
    final box = await _todoBox;
    final raw = box.get(id);
    if (raw == null) return null;
    return TodoItem.fromMap(Map<dynamic, dynamic>.from(raw as Map));
  }

  Future<TodoItem> add(String text, {String source = 'user'}) async {
    final box = await _todoBox;
    final item = TodoItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text.trim(),
      createdAt: DateTime.now(),
      source: source,
    );
    await box.put(item.id, item.toMap());
    return item;
  }

  /// Alterna hecho/pendiente. Pensado para uso manual (tocar el checkbox).
  Future<void> toggle(String id) async {
    final item = await getById(id);
    if (item == null) return;
    item.isDone = !item.isDone;
    item.completedAt = item.isDone ? DateTime.now() : null;
    final box = await _todoBox;
    await box.put(id, item.toMap());
  }

  /// Marca como completada explícitamente. Pensado para acciones de la IA,
  /// donde la intención siempre es "completar", no "alternar".
  Future<bool> markDone(String id, {bool done = true}) async {
    final item = await getById(id);
    if (item == null) return false;
    item.isDone = done;
    item.completedAt = done ? DateTime.now() : null;
    final box = await _todoBox;
    await box.put(id, item.toMap());
    return true;
  }

  Future<void> updateText(String id, String newText) async {
    final item = await getById(id);
    if (item == null) return;
    item.text = newText.trim();
    final box = await _todoBox;
    await box.put(id, item.toMap());
  }

  Future<void> delete(String id) async {
    final box = await _todoBox;
    await box.delete(id);
  }

  /// Busca una tarea por coincidencia de texto (exacta primero, luego
  /// parcial). Lo usa la IA cuando el usuario se refiere a una tarea por
  /// nombre en vez de por ID.
  Future<TodoItem?> findByText(String text) async {
    final items = await getAll();
    final lower = text.toLowerCase().trim();
    for (final item in items) {
      if (item.text.toLowerCase().trim() == lower) return item;
    }
    for (final item in items) {
      if (item.text.toLowerCase().contains(lower) ||
          lower.contains(item.text.toLowerCase())) {
        return item;
      }
    }
    return null;
  }

  /// Texto compacto para inyectar en el prompt de la IA, con IDs
  /// referenciables (mismo patrón que la lista de archivos de Drive).
  Future<String> summaryForPrompt() async {
    final items = await getAll();
    if (items.isEmpty) return '(vacía, no hay tareas)';
    return items
        .map((t) => '  - [${t.isDone ? "x" : " "}] (id: ${t.id}) ${t.text}')
        .join('\n');
  }
}