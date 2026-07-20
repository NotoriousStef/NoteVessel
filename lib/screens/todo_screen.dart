import 'package:flutter/material.dart';
import '../models/todo_item.dart';
import '../services/todo_service.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final _todoService = TodoService();
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();

  List<TodoItem> _items = [];
  bool _loading = true;

  static const _accentColor = Color(0xFF6C63FF);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _todoService.getAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _addItem() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    await _todoService.add(text, source: 'user');
    await _load();
  }

  Future<void> _toggleItem(String id) async {
    await _todoService.toggle(id);
    await _load();
  }

  Future<void> _deleteItem(String id) async {
    await _todoService.delete(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Tareas',
          style: TextStyle(color: Colors.white70, fontSize: 17),
        ),
        iconTheme: const IconThemeData(color: Colors.white54),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.checklist_rounded,
                  color: Colors.white24, size: 40),
              const SizedBox(height: 16),
              Text(
                'No tenés tareas todavía. Agregá una acá abajo, o pedíselo por voz o texto al asistente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13.5, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _items.length,
      itemBuilder: (context, index) => _buildItem(_items[index]),
    );
  }

  Widget _buildItem(TodoItem item) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4D6D).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Color(0xFFFF4D6D)),
      ),
      onDismissed: (_) => _deleteItem(item.id),
      child: GestureDetector(
        onTap: () => _toggleItem(item.id),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isDone
                  ? Colors.white.withValues(alpha: 0.04)
                  : _accentColor.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.isDone
                      ? _accentColor
                      : Colors.transparent,
                  border: Border.all(
                    color: item.isDone
                        ? _accentColor
                        : Colors.white38,
                    width: 1.5,
                  ),
                ),
                child: item.isDone
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 15)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.text,
                  style: TextStyle(
                    color: item.isDone ? Colors.white30 : Colors.white,
                    fontSize: 14.5,
                    height: 1.4,
                    decoration: item.isDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
              ),
              if (item.source == 'ai') ...[
                const SizedBox(width: 6),
                Icon(Icons.auto_awesome_rounded,
                    color: _accentColor.withValues(alpha: 0.5), size: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 28,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        border: Border(
          top: BorderSide(color: _accentColor.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _inputFocusNode.hasFocus
                      ? _accentColor.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Nueva tarea...',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addItem(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _addItem,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_accentColor, _accentColor.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.add_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}